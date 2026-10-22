defmodule Emisint.Improvement.Changes.ScopeEntry do
  @moduledoc """
  Scopes an append-only entry (`ActualResult`, `ImplementationRating`) to its
  metric and reporting period, loading both **inside the caller's tenant**.

  * `kind: :observation` — the first value for a metric × period. Requires
    `metric_id` and `reporting_period_id`; the period must belong to the
    metric's plan and be one of `:period_kinds`.
  * `kind: :correction` — replaces exactly one current entry. Requires the
    `corrects_id` argument. Metric, period and school are copied from the
    corrected entry; any supplied `metric_id`/`reporting_period_id` must match.
    The corrected entry must still be current. A unique index on `corrects_id`
    rejects a concurrent correction that slips past this check.

  The loaded metric is stored in the changeset context under
  `:improvement_metric` for unit-aware validations.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Emisint.Improvement.{Metric, ReportingPeriod}

  @impl true
  def change(changeset, opts, _context) do
    changeset = Ash.Changeset.force_change_attribute(changeset, :kind, opts[:kind])

    case opts[:kind] do
      :observation -> scope_observation(changeset, opts)
      :correction -> scope_correction(changeset, opts)
    end
  end

  defp scope_observation(changeset, opts) do
    metric_id = Ash.Changeset.get_attribute(changeset, :metric_id)
    period_id = Ash.Changeset.get_attribute(changeset, :reporting_period_id)

    with {:ok, metric} <- fetch(Metric, metric_id, changeset, :metric_id),
         {:ok, period} <- fetch(ReportingPeriod, period_id, changeset, :reporting_period_id),
         :ok <- same_plan(metric, period),
         :ok <- allowed_period(period, opts[:period_kinds]) do
      changeset
      |> Ash.Changeset.force_change_attribute(:school_id, metric.school_id)
      |> Ash.Changeset.put_context(:improvement_metric, metric)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
      :skip -> changeset
    end
  end

  defp scope_correction(changeset, _opts) do
    corrects_id = Ash.Changeset.get_argument(changeset, :corrects_id)

    with {:ok, corrected} <- fetch(changeset.resource, corrects_id, changeset, :corrects_id),
         :ok <- matches(changeset, :metric_id, corrected.metric_id),
         :ok <- matches(changeset, :reporting_period_id, corrected.reporting_period_id),
         :ok <- still_current(changeset, corrected),
         {:ok, metric} <- fetch(Metric, corrected.metric_id, changeset, :metric_id) do
      changeset
      |> Ash.Changeset.force_change_attribute(:corrects_id, corrected.id)
      |> Ash.Changeset.force_change_attribute(:metric_id, corrected.metric_id)
      |> Ash.Changeset.force_change_attribute(:reporting_period_id, corrected.reporting_period_id)
      |> Ash.Changeset.force_change_attribute(:school_id, corrected.school_id)
      |> Ash.Changeset.put_context(:improvement_metric, metric)
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
      :skip -> changeset
    end
  end

  # Missing IDs are left to the attribute/argument `allow_nil?` errors.
  defp fetch(_resource, nil, _changeset, _field), do: :skip

  defp fetch(resource, id, changeset, field) do
    case Ash.get(resource, id, tenant: changeset.tenant, authorize?: false) do
      {:ok, record} -> {:ok, record}
      {:error, _} -> {:error, field: field, message: "does not exist in this organization"}
    end
  end

  defp same_plan(%{goal_plan_id: plan_id}, %{goal_plan_id: plan_id}), do: :ok

  defp same_plan(_metric, _period),
    do:
      {:error,
       field: :reporting_period_id, message: "belongs to a different goal plan than the metric"}

  defp allowed_period(_period, nil), do: :ok

  defp allowed_period(%{kind: kind}, kinds) do
    if kind in kinds,
      do: :ok,
      else:
        {:error,
         field: :reporting_period_id, message: "must be a #{Enum.join(kinds, " or ")} period"}
  end

  defp matches(changeset, field, expected) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil -> :ok
      ^expected -> :ok
      _other -> {:error, field: field, message: "does not match the entry being corrected"}
    end
  end

  defp still_current(changeset, corrected) do
    already_corrected? =
      changeset.resource
      |> Ash.Query.filter(corrects_id == ^corrected.id)
      |> Ash.exists?(tenant: changeset.tenant, authorize?: false)

    if already_corrected?,
      do:
        {:error,
         field: :corrects_id,
         message: "has already been corrected; correct the current entry instead"},
      else: :ok
  end
end
