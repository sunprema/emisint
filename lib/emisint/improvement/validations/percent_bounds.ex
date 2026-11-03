defmodule Emisint.Improvement.Validations.PercentBounds do
  @moduledoc """
  Ensures normalized percentage fields stay within 0–1 when the metric's unit
  is `:percent`, and growth percentiles within 0–100 when it is `:percentile`. The unit is read from the changeset itself (for `Metric`) or
  from the metric that `Changes.ScopeEntry` placed in the context (for entries).

  Options:

    * `:fields` — decimal attributes to check
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    case bounds(unit(changeset)) do
      nil ->
        :ok

      {max, message} ->
        opts
        |> Keyword.fetch!(:fields)
        |> Enum.find_value(:ok, fn field ->
          value = Ash.Changeset.get_attribute(changeset, field)

          if is_nil(value) or in_range?(value, max),
            do: nil,
            else: {:error, field: field, message: message}
        end)
    end
  end

  defp bounds(:percent), do: {1, "must be a proportion between 0 and 1 (e.g. 0.25 for 25%)"}
  defp bounds(:percentile), do: {100, "must be a growth percentile between 0 and 100"}
  defp bounds(_unit), do: nil

  defp unit(changeset) do
    case changeset.context[:improvement_metric] do
      %{unit: unit} -> unit
      _ -> Ash.Changeset.get_attribute(changeset, :unit)
    end
  end

  defp in_range?(%Decimal{} = value, max),
    do: Decimal.compare(value, 0) != :lt and Decimal.compare(value, max) != :gt

  defp in_range?(_value, _max), do: false
end
