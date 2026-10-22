defmodule Emisint.Improvement.Seeds do
  @moduledoc """
  Idempotent, non-destructive seeding of ND First pilot definitions and the
  historical workbook ratings.

    * The organization is always explicit. It must already exist; nothing is
      guessed or created — except `ensure_dev_organization!/0`, which is only
      allowed when `config :emisint, :allow_dev_seeds` is true (dev/test).
    * A record that already matches the seed is reported as `:unchanged`.
      A record that differs is reported as `:drift` and **left untouched**.
    * Workbook ratings are created once per metric × period through the
      `ImplementationRating` `:import_workbook` action. Existing observations
      (and any corrections made since) are never modified.

  Usage (also from a release via `bin/emisint eval`):

      Emisint.Improvement.Seeds.run(org_id, actor: importing_user)
  """
  require Ash.Query

  alias Emisint.Accounts.{Organization, School, SchoolMembership, User}

  alias Emisint.Improvement.{
    AnnualAssessmentGoal,
    Goal,
    GoalPlan,
    ImplementationRating,
    Metric,
    ReportingPeriod
  }

  alias Emisint.Improvement.Seeds.FortYates

  @dev_org_slug "nd-first-pilot-dev"
  @dev_org_name "ND First Pilot — Development"
  @dev_password "nd-first-dev-password"

  @type report :: %{
          created: [String.t()],
          unchanged: [String.t()],
          drift: [%{record: String.t(), fields: map()}]
        }

  @doc """
  Seeds Fort Yates definitions (and, unless `workbook_ratings?: false`, the
  historical workbook ratings) into `organization_id`.

  Options:

    * `:actor` — user recorded as `recorded_by` on imported ratings
    * `:workbook_ratings?` — default `true`
  """
  @spec run(String.t(), keyword()) :: {:ok, report()} | {:error, String.t()}
  def run(organization_id, opts \\ [])

  def run(organization_id, opts) when is_binary(organization_id) and organization_id != "" do
    with {:ok, org} <- fetch_organization(organization_id) do
      report = seed_definitions(org.id, empty_report())

      report =
        if Keyword.get(opts, :workbook_ratings?, true),
          do: import_workbook_ratings(org.id, opts[:actor], report),
          else: report

      {:ok, finalize(report)}
    end
  end

  def run(_organization_id, _opts), do: {:error, "an explicit organization ID is required"}

  @doc """
  Finds or creates the "#{@dev_org_name}" organization plus demo users and
  memberships. Refuses to run unless `:allow_dev_seeds` is configured.
  Call after `run/2` so the school exists.
  """
  def ensure_dev_organization! do
    unless Application.get_env(:emisint, :allow_dev_seeds, false) do
      raise "development seeds are disabled in this environment"
    end

    case Ash.read_one(Ash.Query.filter(Organization, slug == ^@dev_org_slug), authorize?: false) do
      {:ok, %Organization{} = org} ->
        org

      {:ok, nil} ->
        Ash.create!(Organization, %{name: @dev_org_name, type: :emo, slug: @dev_org_slug},
          authorize?: false
        )
    end
  end

  @doc """
  Creates dev/test demo users for the dev organization: an EMO admin, a
  Fort Yates contributor and a Fort Yates viewer. Same environment guard as
  `ensure_dev_organization!/0`. Existing users in another organization are
  reported as drift and left alone.

  Each demo user also lists its earlier address. A demo account still using
  that address (in the dev organization, with the expected role) is renamed in
  place, keeping its id, password, memberships and sessions, so re-running the
  seed never recreates old accounts. If the new address belongs to anyone
  else, or both addresses exist, nothing is renamed or merged and the
  conflict is reported as drift.
  """
  def ensure_dev_users!(%Organization{slug: @dev_org_slug} = org) do
    unless Application.get_env(:emisint, :allow_dev_seeds, false) do
      raise "development seeds are disabled in this environment"
    end

    school =
      Ash.read_one!(Ash.Query.filter(School, slug == ^FortYates.school().slug),
        tenant: org.id,
        authorize?: false
      )

    dev_users()
    |> Enum.reduce(empty_report(), fn {email, legacy_email, role, membership_role}, report ->
      case ensure_dev_user(email, legacy_email, role, org) do
        {:ok, user, :renamed} ->
          report = add(report, :renamed, "user #{legacy_email} → #{email}")
          ensure_dev_membership(user, school, membership_role, org, report)

        {:ok, user, report_key} ->
          report = add(report, report_key, "user #{email}")
          ensure_dev_membership(user, school, membership_role, org, report)

        {:drift, fields} ->
          add_drift(report, "user #{email}", fields)
      end
    end)
    |> finalize()
  end

  def dev_password, do: @dev_password

  @doc "Demo users as `{email, earlier_email, role, fort_yates_membership_role}`."
  def dev_users do
    [
      {"admin@example.com", "nd-first-admin@example.com", :emo_admin, nil},
      {"school@example.com", "nd-first-contributor@example.com", :school_leader, :contributor},
      {"viewer@example.com", "nd-first-viewer@example.com", :school_leader, :viewer}
    ]
  end

  # ---------------------------------------------------------------------------
  # Definitions
  # ---------------------------------------------------------------------------

  defp seed_definitions(org_id, report) do
    school_attrs = FortYates.school()
    {school, report} = ensure(School, [slug: school_attrs.slug], school_attrs, org_id, report)

    plan_attrs = Map.put(FortYates.goal_plan(), :school_id, school.id)

    {plan, report} =
      ensure(
        GoalPlan,
        [
          school_id: school.id,
          program: plan_attrs.program,
          definition_version: plan_attrs.definition_version
        ],
        plan_attrs,
        org_id,
        report
      )

    report =
      Enum.reduce(FortYates.reporting_periods(), report, fn attrs, acc ->
        attrs = Map.put(attrs, :goal_plan_id, plan.id)

        {_period, acc} =
          ensure(ReportingPeriod, [goal_plan_id: plan.id, code: attrs.code], attrs, org_id, acc)

        acc
      end)

    {goals_by_number, report} =
      Enum.reduce(FortYates.goals(), {%{}, report}, fn attrs, {goals, acc} ->
        attrs = Map.put(attrs, :goal_plan_id, plan.id)

        {goal, acc} =
          ensure(Goal, [goal_plan_id: plan.id, number: attrs.number], attrs, org_id, acc)

        {Map.put(goals, goal.number, goal), acc}
      end)

    report =
      Enum.reduce(FortYates.metrics(), report, fn attrs, acc ->
        {goal_number, attrs} = Map.pop!(attrs, :goal_number)
        attrs = Map.put(attrs, :goal_id, Map.fetch!(goals_by_number, goal_number).id)

        {_metric, acc} =
          ensure(Metric, [goal_plan_id: plan.id, code: attrs.code], attrs, org_id, acc)

        acc
      end)

    Enum.reduce(FortYates.annual_assessment_goals(), report, fn attrs, acc ->
      attrs = Map.put(attrs, :school_id, school.id)
      key = [school_id: school.id, school_year: attrs.school_year, subject: attrs.subject]
      {_goal, acc} = ensure(AnnualAssessmentGoal, key, attrs, org_id, acc)
      acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Workbook ratings
  # ---------------------------------------------------------------------------

  defp import_workbook_ratings(org_id, actor, report) do
    school =
      Ash.read_one!(Ash.Query.filter(School, slug == ^FortYates.school().slug),
        tenant: org_id,
        authorize?: false
      )

    plan =
      Ash.read_one!(
        Ash.Query.filter(
          GoalPlan,
          school_id == ^school.id and program == ^FortYates.goal_plan().program
        ),
        tenant: org_id,
        authorize?: false
      )

    metrics = index_by(Metric, plan.id, :code, org_id)
    periods = index_by(ReportingPeriod, plan.id, :code, org_id)

    Enum.reduce(FortYates.workbook_ratings(), report, fn {code, period_code, score, source_ref},
                                                         acc ->
      metric = Map.fetch!(metrics, code)
      period = Map.fetch!(periods, period_code)
      label = "rating #{code} #{period_code}"

      existing =
        ImplementationRating
        |> Ash.Query.filter(
          metric_id == ^metric.id and reporting_period_id == ^period.id and kind == :observation
        )
        |> Ash.read_one!(tenant: org_id, authorize?: false)

      case existing do
        nil ->
          Ash.create!(
            ImplementationRating,
            %{
              metric_id: metric.id,
              reporting_period_id: period.id,
              rating_state: :rated,
              score: score,
              source_ref: source_ref,
              source_last_updated_on: FortYates.workbook_last_updated()
            },
            action: :import_workbook,
            tenant: org_id,
            actor: actor,
            authorize?: false
          )

          add(acc, :created, label)

        %{source: :workbook_import, score: ^score, source_ref: ^source_ref} ->
          add(acc, :unchanged, label)

        other ->
          add_drift(acc, label, %{
            source: {other.source, :workbook_import},
            score: {other.score, score},
            source_ref: {other.source_ref, source_ref}
          })
      end
    end)
  end

  defp index_by(resource, plan_id, key, org_id) do
    resource
    |> Ash.Query.filter(goal_plan_id == ^plan_id)
    |> Ash.read!(tenant: org_id, authorize?: false)
    |> Map.new(&{Map.fetch!(&1, key), &1})
  end

  # ---------------------------------------------------------------------------
  # Dev users
  # ---------------------------------------------------------------------------

  defp ensure_dev_user(email, legacy_email, role, org) do
    org_id = org.id

    case {find_user(email), find_user(legacy_email)} do
      {nil, %User{organization_id: ^org_id, role: ^role} = legacy} ->
        # Dev-only rename of a seeded demo account; only the email changes.
        {:ok, Ash.Seed.update!(legacy, %{email: email}), :renamed}

      {nil, %User{} = legacy} ->
        {:drift,
         %{
           earlier_email: {legacy_email, "in another organization or role; not renamed"},
           organization_id: {legacy.organization_id, org.id},
           role: {legacy.role, role}
         }}

      {%User{}, %User{}} ->
        {:drift, %{email: {"#{email} and #{legacy_email} both exist", "not merged"}}}

      {_user, nil} ->
        ensure_dev_user(email, role, org)
    end
  end

  defp find_user(email) do
    Ash.read_one!(Ash.Query.filter(User, email == ^email), authorize?: false)
  end

  defp ensure_dev_user(email, role, org) do
    org_id = org.id

    case Ash.read_one(Ash.Query.filter(User, email == ^email), authorize?: false) do
      {:ok, nil} ->
        user =
          User
          |> Ash.Changeset.for_create(
            :register_with_password,
            %{email: email, password: @dev_password, password_confirmation: @dev_password},
            authorize?: false
          )
          |> Ash.create!()
          |> Ash.Changeset.for_update(
            :assign_organization,
            %{organization_id: org.id, role: role},
            authorize?: false
          )
          |> Ash.update!()

        {:ok, user, :created}

      {:ok, %User{organization_id: ^org_id, role: ^role} = user} ->
        {:ok, user, :unchanged}

      {:ok, user} ->
        {:drift, %{organization_id: {user.organization_id, org.id}, role: {user.role, role}}}
    end
  end

  defp ensure_dev_membership(_user, _school, nil, _org, report), do: report

  defp ensure_dev_membership(user, school, role, org, report) do
    attrs = %{user_id: user.id, school_id: school.id, role: role}

    {_membership, report} =
      ensure(SchoolMembership, [user_id: user.id, school_id: school.id], attrs, org.id, report)

    report
  end

  # ---------------------------------------------------------------------------
  # Generic ensure
  # ---------------------------------------------------------------------------

  defp ensure(resource, key, attrs, org_id, report) do
    label = "#{inspect(resource)} #{inspect(Map.new(key))}"

    case Ash.read_one(Ash.Query.do_filter(resource, key), tenant: org_id, authorize?: false) do
      {:ok, nil} ->
        record = Ash.create!(resource, attrs, tenant: org_id, authorize?: false)
        {record, add(report, :created, label)}

      {:ok, record} ->
        case differences(record, attrs) do
          diff when map_size(diff) == 0 -> {record, add(report, :unchanged, label)}
          diff -> {record, add_drift(report, label, diff)}
        end
    end
  end

  defp differences(record, attrs) do
    Enum.reduce(attrs, %{}, fn {field, expected}, diff ->
      actual = Map.get(record, field)
      if same?(actual, expected), do: diff, else: Map.put(diff, field, {actual, expected})
    end)
  end

  defp same?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  defp same?(a, b), do: a == b

  defp empty_report, do: %{created: [], unchanged: [], renamed: [], drift: []}

  defp add(report, key, label), do: Map.update!(report, key, &[label | &1])

  defp add_drift(report, label, fields),
    do: Map.update!(report, :drift, &[%{record: label, fields: fields} | &1])

  defp finalize(report), do: Map.new(report, fn {key, items} -> {key, Enum.reverse(items)} end)

  defp fetch_organization(organization_id) do
    case Ash.get(Organization, organization_id, authorize?: false) do
      {:ok, org} -> {:ok, org}
      {:error, _} -> {:error, "organization #{organization_id} does not exist"}
    end
  end
end
