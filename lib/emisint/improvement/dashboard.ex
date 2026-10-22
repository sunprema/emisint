defmodule Emisint.Improvement.Dashboard do
  @moduledoc """
  Loads school goal data for the LiveViews.

  Every read runs **as the actor, inside the actor's tenant** (via
  `Emisint.Scope`), so the resource policies decide what is visible: a school
  the actor cannot read is simply not found. Author and recorder emails are
  looked up without authorization, but only for entries the actor was already
  allowed to read.
  """
  require Ash.Query

  alias Emisint.Accounts.{School, User}

  alias Emisint.Improvement.{
    ActualResult,
    AnnualAssessmentGoal,
    Goal,
    GoalPlan,
    ImplementationRating,
    Metric,
    Payment,
    ReportingPeriod
  }

  @program "nd_first_mou"

  @doc "Schools the actor can read in the current tenant, by name."
  def list_schools(scope) do
    School
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(scope: scope)
  end

  @doc "Fetches a readable school by slug."
  def fetch_school(scope, slug) when is_binary(slug) do
    School
    |> Ash.Query.filter(slug == ^slug)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %School{} = school} -> {:ok, school}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The school's current goal plan and its definitions: goals, metrics, seasonal
  periods, annual assessment goals and the payment summary.
  """
  def load_plan(scope, school) do
    plan =
      GoalPlan
      |> Ash.Query.filter(school_id == ^school.id and program == @program)
      |> Ash.Query.sort(definition_version: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(scope: scope)

    if plan, do: {:ok, definitions(scope, school, plan)}, else: {:error, :no_plan}
  end

  defp definitions(scope, school, plan) do
    metrics = read_for_plan(Metric, plan, scope, position: :asc)

    %{
      plan: plan,
      goals: read_for_plan(Goal, plan, scope, number: :asc),
      metrics: metrics,
      metrics_by_goal: Enum.group_by(metrics, & &1.goal_id),
      periods:
        Enum.filter(
          read_for_plan(ReportingPeriod, plan, scope, position: :asc),
          &(&1.kind == :seasonal)
        ),
      annual_goals:
        AnnualAssessmentGoal
        |> Ash.Query.filter(school_id == ^school.id)
        |> Ash.Query.sort(school_year: :asc, subject: :asc)
        |> Ash.read!(scope: scope),
      payment: Payment.summary(plan, metrics)
    }
  end

  defp read_for_plan(resource, plan, scope, sort) do
    resource
    |> Ash.Query.filter(goal_plan_id == ^plan.id)
    |> Ash.Query.sort(sort)
    |> Ash.read!(scope: scope)
  end

  @doc """
  Current actual results and ratings for `school` in `period`, keyed by metric
  id, plus the emails of their authors and recorders.
  """
  def load_period(scope, school, period) do
    actuals = current(ActualResult, scope, school, period)
    ratings = current(ImplementationRating, scope, school, period)

    %{
      actuals: Map.new(actuals, &{&1.metric_id, &1}),
      ratings: Map.new(ratings, &{&1.metric_id, &1}),
      users: user_emails(actuals ++ ratings)
    }
  end

  defp current(resource, scope, school, period) do
    resource
    |> Ash.Query.for_read(:current, %{}, scope: scope)
    |> Ash.Query.filter(school_id == ^school.id and reporting_period_id == ^period.id)
    |> Ash.read!()
  end

  @doc """
  The latest seasonal period that has any entry, else the first one. Used as
  the default selection.
  """
  def default_period(scope, school, periods) do
    used =
      [ActualResult, ImplementationRating]
      |> Enum.flat_map(fn resource ->
        resource
        |> Ash.Query.filter(school_id == ^school.id)
        |> Ash.Query.select([:reporting_period_id])
        |> Ash.read!(scope: scope)
      end)
      |> MapSet.new(& &1.reporting_period_id)

    periods |> Enum.filter(&MapSet.member?(used, &1.id)) |> List.last() || List.first(periods)
  end

  @doc """
  Average current seasonal rating per category for a period. Only `:rated`
  entries count; N/A, unavailable and missing ratings are excluded, never
  treated as zero. These averages are informational and never feed payment.
  """
  def seasonal_averages(metrics, ratings) do
    for category <- [:systems, :student_outcome], into: %{} do
      in_category = Enum.filter(metrics, &(&1.category == category))

      scores =
        for metric <- in_category,
            %{rating_state: :rated, score: score} <- [ratings[metric.id]],
            do: score

      average = if scores == [], do: nil, else: Float.round(Enum.sum(scores) / length(scores), 2)
      {category, %{average: average, rated: length(scores), total: length(in_category)}}
    end
  end

  @doc """
  Full history of one metric (actual results and ratings, every period),
  newest first, with each entry marked current or superseded.
  """
  def load_history(scope, plan, code) do
    Metric
    |> Ash.Query.filter(goal_plan_id == ^plan.id and code == ^code)
    |> Ash.read_one(scope: scope)
    |> case do
      {:ok, %Metric{} = metric} ->
        actuals = history(ActualResult, scope, metric)
        ratings = history(ImplementationRating, scope, metric)

        {:ok,
         %{
           metric: metric,
           goal: Ash.get!(Goal, metric.goal_id, scope: scope),
           actuals: actuals,
           ratings: ratings,
           users: user_emails(actuals ++ ratings)
         }}

      _ ->
        {:error, :not_found}
    end
  end

  defp history(resource, scope, metric) do
    resource
    |> Ash.Query.for_read(:history, %{metric_id: metric.id}, scope: scope)
    |> Ash.Query.load(:current?)
    |> Ash.read!()
  end

  defp user_emails(entries) do
    ids =
      entries
      |> Enum.flat_map(&[&1.author_id, &1.recorded_by_id])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      %{}
    else
      User
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, to_string(&1.email)})
    end
  end
end
