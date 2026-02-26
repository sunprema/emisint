defmodule Emisint.Compliance do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain, AshPaperTrail.Domain]

  admin do
    show? true
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Emisint.Compliance.CharterContract do
      define :create_charter_contract, action: :create
      define :get_charter_contract, action: :read, get_by: [:id]
      define :list_charter_contracts, action: :read
      define :update_charter_contract, action: :update
    end

    resource Emisint.Compliance.Schedule71Goal do
      define :create_schedule71_goal, action: :create
      define :get_schedule71_goal, action: :read, get_by: [:id]
      define :list_schedule71_goals, action: :read
      define :update_schedule71_goal, action: :update
    end

    resource Emisint.Compliance.GoalEvaluation do
      define :create_goal_evaluation, action: :create
      define :recalculate_goal, action: :recalculate
      define :get_goal_evaluation, action: :read, get_by: [:id]
      define :list_goal_evaluations, action: :read
      define :update_goal_evaluation, action: :update
    end
  end
end
