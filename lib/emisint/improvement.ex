defmodule Emisint.Improvement do
  @moduledoc """
  School improvement goals (first used for the ND First MOU pilot).

  Definitions — `GoalPlan`, `Goal`, `Metric`, `ReportingPeriod`,
  `AnnualAssessmentGoal` — are read-only in the pilot and are created by
  `Emisint.Improvement.Seeds`.

  Values are append-only entries kept in separate resources so they never
  overwrite each other:

    * `ActualResult`         — measured metric results
    * `ImplementationRating` — seasonal 0–3 implementation ratings

  Formal review ratings used for payments are a separate, later resource and
  are never derived from either of these.
  """
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Improvement.GoalPlan do
      define :list_goal_plans, action: :read
    end

    resource Emisint.Improvement.Goal do
      define :list_goals, action: :read
    end

    resource Emisint.Improvement.Metric do
      define :list_metrics, action: :read
      define :get_metric, action: :read, get_by: [:id]
    end

    resource Emisint.Improvement.ReportingPeriod do
      define :list_reporting_periods, action: :read
    end

    resource Emisint.Improvement.AnnualAssessmentGoal do
      define :list_annual_assessment_goals, action: :read
    end

    resource Emisint.Improvement.ActualResult do
      define :record_actual_result, action: :record
      define :correct_actual_result, action: :correct
      define :list_current_actual_results, action: :current
      define :list_actual_result_history, action: :history, args: [:metric_id]
    end

    resource Emisint.Improvement.ImplementationRating do
      define :record_implementation_rating, action: :record
      define :correct_implementation_rating, action: :correct
      define :import_workbook_implementation_rating, action: :import_workbook
      define :list_current_implementation_ratings, action: :current
      define :list_implementation_rating_history, action: :history, args: [:metric_id]
    end
  end
end
