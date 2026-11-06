defmodule Emisint.Improvement.Seeds do
  @moduledoc """
  Idempotent, non-destructive seeding of ND First pilot definitions and the
  historical workbook ratings.

    * The organization is always explicit. It must already exist; nothing is
      guessed or created — except `ensure_dev_organization!/0`, which is only
      allowed when `config :emisint, :allow_dev_seeds` is true (dev/test).
    * A record that already matches the seed is reported as `:unchanged`.
      A record that differs is reported as `:drift` and **left untouched**.
    * Before seeding Fort Yates, `GrowthPercentile.run/2` applies the
      October 31, 2026 growth-percentile decision to an existing G2-M3 and
      G3-M3 (repeat-safe; reported as `converted`), so an existing database
      ends with the same definitions as a fresh seed.
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
    GrowthPercentile,
    ImplementationRating,
    Metric,
    ReportingPeriod
  }

  alias Emisint.Improvement.Seeds.{FortYates, Oberon, ValleyMiddle}

  # Seeded by default: the current release is the Fort Yates pilot.
  @schools [FortYates]

  # ND First schools whose MOU sheet, PDF targets and InstitutionID map to a
  # single verified building. The others are kept for later expansion and are
  # seeded only when passed explicitly as `schools:`. See PLAN_nd_first.md for
  # the five participants whose district-level sheets do not (yet) map to one
  # building.
  @available_schools [FortYates, Oberon, ValleyMiddle]

  @doc "School definition modules seeded by default."
  def schools, do: @schools

  @doc "Every verified school definition module, including those deferred for expansion."
  def available_schools, do: @available_schools

  @doc "The school definition module for a verified ND InstitutionID, or nil."
  def module_for(institution_id) when is_binary(institution_id),
    do: Enum.find(@available_schools, &(&1.school().state_entity_id == institution_id))

  def module_for(_institution_id), do: nil

  @dev_org_slug "nd-first-pilot-dev"
  @dev_org_name "ND First Pilot — Development"
  @dev_password "nd-first-dev-password"

  @type report :: %{
          created: [String.t()],
          unchanged: [String.t()],
          drift: [%{record: String.t(), fields: map()}]
        }

  @doc """
  Seeds ND First school definitions (and, unless `workbook_ratings?: false`,
  the historical workbook ratings) into `organization_id`.

  Options:

    * `:schools` — school definition modules, default `schools/0`
    * `:actor` — user recorded as `recorded_by` on imported ratings
    * `:workbook_ratings?` — default `true`
  """
  @spec run(String.t(), keyword()) :: {:ok, report()} | {:error, String.t()}
  def run(organization_id, opts \\ [])

  def run(organization_id, opts) when is_binary(organization_id) and organization_id != "" do
    with {:ok, org} <- fetch_organization(organization_id) do
      report =
        opts
        |> Keyword.get(:schools, @schools)
        |> Enum.reduce(empty_report(), fn school, report ->
          report = apply_decisions(org.id, opts[:actor], report, school)
          report = seed_definitions(org.id, report, school)
          report = apply_payment_terms(org.id, report, school)

          if Keyword.get(opts, :workbook_ratings?, true),
            do: import_workbook_ratings(org.id, opts[:actor], report, school),
            else: report
        end)

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
      {"viewer@example.com", "nd-first-viewer@example.com", :school_leader, :viewer},
      # Dev-only system admin, so the ND Insights import page can be tried locally.
      {"sysadmin@example.com", nil, :system_admin, nil}
    ]
  end

  # ---------------------------------------------------------------------------
  # Definitions
  # ---------------------------------------------------------------------------

  defp seed_definitions(org_id, report, school_module) do
    school_attrs = school_module.school()
    {school, report} = ensure(School, [slug: school_attrs.slug], school_attrs, org_id, report)

    plan_attrs = Map.put(school_module.goal_plan(), :school_id, school.id)

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
      Enum.reduce(school_module.reporting_periods(), report, fn attrs, acc ->
        attrs = Map.put(attrs, :goal_plan_id, plan.id)

        {_period, acc} =
          ensure(ReportingPeriod, [goal_plan_id: plan.id, code: attrs.code], attrs, org_id, acc)

        acc
      end)

    {goals_by_number, report} =
      Enum.reduce(school_module.goals(), {%{}, report}, fn attrs, {goals, acc} ->
        attrs = Map.put(attrs, :goal_plan_id, plan.id)

        {goal, acc} =
          ensure(Goal, [goal_plan_id: plan.id, number: attrs.number], attrs, org_id, acc)

        {Map.put(goals, goal.number, goal), acc}
      end)

    report =
      Enum.reduce(school_module.metrics(), report, fn attrs, acc ->
        {goal_number, attrs} = Map.pop!(attrs, :goal_number)
        attrs = Map.put(attrs, :goal_id, Map.fetch!(goals_by_number, goal_number).id)

        {_metric, acc} =
          ensure(Metric, [goal_plan_id: plan.id, code: attrs.code], attrs, org_id, acc)

        acc
      end)

    Enum.reduce(school_module.annual_assessment_goals(), report, fn attrs, acc ->
      attrs = Map.put(attrs, :school_id, school.id)
      key = [school_id: school.id, school_year: attrs.school_year, subject: attrs.subject]
      {_goal, acc} = ensure(AnnualAssessmentGoal, key, attrs, org_id, acc)
      acc
    end)
  end

  defp apply_decisions(org_id, actor, report, FortYates) do
    case GrowthPercentile.run(org_id, actor: actor) do
      {:ok, result} ->
        Enum.reduce(result.converted, report, fn code, acc ->
          add(acc, :converted, "Metric #{code} → growth percentile")
        end)

      {:error, reason} ->
        raise "growth-percentile conversion stopped: #{reason}"
    end
  end

  defp apply_decisions(_org_id, _actor, report, _school), do: report

  # Payment terms are set only through GoalPlan's `:set_payment_terms`
  # (which versions them) and only when they differ, so re-running changes
  # nothing and a recorded estimate keeps the version it used.
  defp apply_payment_terms(org_id, report, school_module) do
    if function_exported?(school_module, :payment_terms, 0) do
      terms = school_module.payment_terms()
      %{program: program, definition_version: version} = school_module.goal_plan()

      school =
        Ash.read_one!(Ash.Query.filter(School, slug == ^school_module.school().slug),
          tenant: org_id,
          authorize?: false
        )

      plan =
        GoalPlan
        |> Ash.Query.filter(
          school_id == ^school.id and program == ^program and definition_version == ^version
        )
        |> Ash.read_one!(tenant: org_id, authorize?: false)

      if map_size(differences(plan, terms)) == 0 do
        report
      else
        plan
        |> Ash.Changeset.for_update(:set_payment_terms, terms,
          tenant: org_id,
          authorize?: false
        )
        |> Ash.update!()

        add(
          report,
          :converted,
          "Goal plan #{school.slug} payment terms → #{terms.payment_terms_status}"
        )
      end
    else
      report
    end
  end

  # ---------------------------------------------------------------------------
  # Workbook ratings
  # ---------------------------------------------------------------------------

  defp import_workbook_ratings(org_id, actor, report, school_module) do
    school =
      Ash.read_one!(Ash.Query.filter(School, slug == ^school_module.school().slug),
        tenant: org_id,
        authorize?: false
      )

    plan =
      Ash.read_one!(
        Ash.Query.filter(
          GoalPlan,
          school_id == ^school.id and program == ^school_module.goal_plan().program
        ),
        tenant: org_id,
        authorize?: false
      )

    metrics = index_by(Metric, plan.id, :code, org_id)
    periods = index_by(ReportingPeriod, plan.id, :code, org_id)

    Enum.reduce(school_module.workbook_ratings(), report, fn {code, period_code, score,
                                                              source_ref},
                                                             acc ->
      metric = Map.fetch!(metrics, code)
      period = Map.fetch!(periods, period_code)
      label = "rating #{school.slug} #{code} #{period_code}"

      # The workbook's validation list is 3, 2, 1, 0 or N/A; N/A is stored as
      # not applicable, never as a score.
      {rating_state, score} =
        if score == :not_applicable, do: {:not_applicable, nil}, else: {:rated, score}

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
              rating_state: rating_state,
              score: score,
              source_ref: source_ref,
              source_last_updated_on: school_module.workbook_last_updated()
            },
            action: :import_workbook,
            tenant: org_id,
            actor: actor,
            authorize?: false
          )

          add(acc, :created, label)

        %{
          source: :workbook_import,
          rating_state: ^rating_state,
          score: ^score,
          source_ref: ^source_ref
        } ->
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

  defp find_user(nil), do: nil

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

  defp empty_report, do: %{created: [], unchanged: [], renamed: [], converted: [], drift: []}

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
