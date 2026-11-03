defmodule Emisint.Improvement.Changes.FromNdInsights do
  @moduledoc """
  Fills an `ActualResult` from the published ND Insights value for the
  metric's mapping (`Improvement.GrowthPercentile`), the school's
  InstitutionID and the explicit `source_year` argument.

  * Only growth-percentile metrics, and only at an 18- or 36-month review.
  * The year must be chosen explicitly (the `source_year` argument is
    required); it is never defaulted to the baseline or the latest year.
    Which years are eligible for each checkpoint is not established, so no
    year is refused here other than one with no published row.
  * The value keeps its published shape (exact, range or suppressed) and
    `source_ref` records year, population, measure, version and file.

  Runs after `ScopeEntry`, which loads the metric into the context.
  """
  use Ash.Resource.Change

  alias Emisint.Accounts.School
  alias Emisint.Improvement.{GrowthPercentile, ReportingPeriod}

  @impl true
  def change(%{valid?: false} = changeset, _opts, _context), do: changeset

  def change(changeset, _opts, _context) do
    metric = changeset.context[:improvement_metric]
    year = Ash.Changeset.get_argument(changeset, :source_year)

    with :ok <- mapped(metric),
         :ok <- review(changeset),
         {:ok, row} <- published(changeset, metric, year) do
      changeset
      |> Ash.Changeset.force_change_attributes(values(row))
      |> Ash.Changeset.force_change_attribute(:source, :nd_insights)
      |> Ash.Changeset.force_change_attribute(:source_ref, GrowthPercentile.source_ref(row))
    else
      {:error, field, message} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp mapped(metric) do
    if GrowthPercentile.mapping(metric),
      do: :ok,
      else: {:error, :metric_id, "has no confirmed ND Insights source"}
  end

  defp review(changeset) do
    period_id = Ash.Changeset.get_attribute(changeset, :reporting_period_id)

    case Ash.get(ReportingPeriod, period_id, tenant: changeset.tenant, authorize?: false) do
      {:ok, period} ->
        if GrowthPercentile.review_period?(period),
          do: :ok,
          else:
            {:error, :reporting_period_id,
             "must be an 18- or 36-month review; published annual values are not copied into seasonal periods"}

      _ ->
        {:error, :reporting_period_id, "does not exist in this organization"}
    end
  end

  defp published(changeset, metric, year) do
    school_id = Ash.Changeset.get_attribute(changeset, :school_id)

    with {:ok, %{state_entity_id: id}} when is_binary(id) <-
           Ash.get(School, school_id, tenant: changeset.tenant, authorize?: false),
         %{} = row <- GrowthPercentile.published_row(id, metric, year) do
      {:ok, row}
    else
      _ -> {:error, :source_year, "has no published value for this school, subject and year"}
    end
  end

  defp values(%{value_state: :exact, value: v}), do: %{value_state: :exact, value: v}

  defp values(%{value_state: :range, range_low: l, range_high: h}),
    do: %{value_state: :range, range_low: l, range_high: h}

  defp values(%{value_state: :suppressed}), do: %{value_state: :suppressed}
end
