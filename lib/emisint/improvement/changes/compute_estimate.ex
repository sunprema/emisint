defmodule Emisint.Improvement.Changes.ComputeEstimate do
  @moduledoc """
  Computes a `PaymentEstimate` on the server from the current formal review
  ratings in the given review period and the plan's current payment terms,
  and stores the result together with every assumption and input used.
  Nothing about the amount is accepted from the caller. Refused unless the
  checkpoint is complete (every metric has a scored review rating).
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Emisint.Improvement.{GoalPlan, ImplementationRating, Metric, Payment, ReportingPeriod}

  @impl true
  def change(%{valid?: false} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    tenant = changeset.tenant
    period_id = Ash.Changeset.get_attribute(changeset, :reporting_period_id)

    with {:ok, period} <- fetch(ReportingPeriod, period_id, tenant, :reporting_period_id),
         :ok <- review(period),
         {:ok, plan} <- fetch(GoalPlan, period.goal_plan_id, tenant, :reporting_period_id),
         %{status: :estimated} = cp <- checkpoint(plan, period, tenant) do
      t = Payment.terms(plan)

      Ash.Changeset.force_change_attributes(changeset, %{
        school_id: period.school_id,
        goal_plan_id: plan.id,
        checkpoint: period.kind,
        amount: cp.estimate,
        allocation: cp.allocation,
        payment_cap: t.cap,
        systems_weight: cp.systems_weight,
        outcomes_weight: cp.outcomes_weight,
        max_rating: plan.max_rating,
        systems_average: cp.systems_average,
        outcomes_average: cp.outcomes_average,
        weighted_score: cp.weighted_score,
        terms_status: t.status,
        terms_version: t.version,
        terms_note: t.note,
        label: Payment.label(),
        formula: Payment.formula(),
        inputs: cp.inputs
      })
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)

      %{} = cp ->
        Ash.Changeset.add_error(changeset,
          field: :reporting_period_id,
          message: "can't be estimated yet: #{Payment.status_text(cp)}"
        )
    end
  end

  defp fetch(resource, id, tenant, field) do
    case Ash.get(resource, id, tenant: tenant, authorize?: false) do
      {:ok, record} -> {:ok, record}
      _ -> {:error, field, "does not exist in this organization"}
    end
  end

  defp review(%{kind: kind}) when kind in [:review_18m, :review_36m], do: :ok

  defp review(_period),
    do: {:error, :reporting_period_id, "must be the 18- or 36-month review"}

  defp checkpoint(plan, period, tenant) do
    metrics =
      Metric
      |> Ash.Query.filter(goal_plan_id == ^plan.id)
      |> Ash.read!(tenant: tenant, authorize?: false)

    ratings =
      ImplementationRating
      |> Ash.Query.for_read(:current, %{}, tenant: tenant, authorize?: false)
      |> Ash.Query.filter(reporting_period_id == ^period.id)
      |> Ash.read!()
      |> Map.new(&{&1.metric_id, &1})

    plan
    |> Payment.summary(metrics, %{period.kind => ratings})
    |> Map.fetch!(:checkpoints)
    |> Enum.find(&(&1.checkpoint == period.kind))
  end
end
