defmodule Emisint.Workers.GoalRecalculationWorker do
  @moduledoc """
  Oban worker that recalculates all Schedule71Goal evaluations for a school/year.

  Expected job args:
    - `organization_id`   — tenant UUID
    - `school_id`         — UUID of the target school
    - `academic_year_id`  — UUID of the target academic year

  Pipeline:
    1. Load all Schedule71Goals for the school
    2. For each goal, upsert a GoalEvaluation via the :recalculate action
    3. Flag any :below goals as InterventionTriggers; resolve triggers for :meets/:exceeds goals
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  require Ash.Query

  alias Emisint.Analytics.InterventionTrigger
  alias Emisint.Compliance.{GoalEvaluation, Schedule71Goal}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => org_id,
          "school_id" => school_id,
          "academic_year_id" => academic_year_id
        }
      }) do
    # 1. Load all goals for this school
    goals =
      Schedule71Goal
      |> Ash.Query.filter(school_id == ^school_id)
      |> Ash.read!(tenant: org_id, authorize?: false)

    # 2. Recalculate each goal evaluation
    evaluations =
      Enum.map(goals, fn goal ->
        eval =
          Ash.create!(GoalEvaluation,
            %{schedule71_goal_id: goal.id, academic_year_id: academic_year_id},
            action: :recalculate,
            tenant: org_id,
            authorize?: false
          )

        {goal, eval}
      end)

    # 3. Sync InterventionTriggers based on evaluation results
    sync_triggers(evaluations, school_id, academic_year_id, org_id)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Trigger management
  # ---------------------------------------------------------------------------

  defp sync_triggers(evaluations, school_id, academic_year_id, org_id) do
    existing_triggers =
      InterventionTrigger
      |> Ash.Query.filter(
        school_id == ^school_id and
          academic_year_id == ^academic_year_id and
          trigger_type == :goal_at_risk and
          status == :active
      )
      |> Ash.read!(tenant: org_id, authorize?: false)

    active_by_goal = Map.new(existing_triggers, fn t -> {t.schedule71_goal_id, t} end)

    Enum.each(evaluations, fn {goal, eval} ->
      cond do
        eval.status in [:below, :approaching] ->
          severity = if eval.status == :below, do: :high, else: :medium

          if Map.has_key?(active_by_goal, goal.id) do
            # Update severity on existing trigger if it changed
            trigger = active_by_goal[goal.id]
            if trigger.severity != severity do
              Ash.update!(trigger, %{severity: severity}, tenant: org_id, authorize?: false)
            end
          else
            # Create a new trigger
            Ash.create!(InterventionTrigger,
              %{
                trigger_type: :goal_at_risk,
                severity: severity,
                triggered_at: DateTime.utc_now(),
                school_id: school_id,
                academic_year_id: academic_year_id,
                schedule71_goal_id: goal.id
              },
              tenant: org_id,
              authorize?: false
            )
          end

        eval.status in [:meets, :exceeds] ->
          # Resolve any active trigger for this goal
          if Map.has_key?(active_by_goal, goal.id) do
            trigger = active_by_goal[goal.id]
            Ash.update!(trigger, %{resolved_at: DateTime.utc_now()}, action: :resolve, tenant: org_id, authorize?: false)
          end

        true ->
          :ok
      end
    end)
  end
end
