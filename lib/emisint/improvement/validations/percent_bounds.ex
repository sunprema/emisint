defmodule Emisint.Improvement.Validations.PercentBounds do
  @moduledoc """
  Ensures normalized percentage fields stay within 0–1 when the metric's unit
  is `:percent`. The unit is read from the changeset itself (for `Metric`) or
  from the metric that `Changes.ScopeEntry` placed in the context (for entries).

  Options:

    * `:fields` — decimal attributes to check
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    if unit(changeset) == :percent do
      opts
      |> Keyword.fetch!(:fields)
      |> Enum.find_value(:ok, fn field ->
        value = Ash.Changeset.get_attribute(changeset, field)

        if is_nil(value) or in_unit_range?(value),
          do: nil,
          else:
            {:error,
             field: field, message: "must be a proportion between 0 and 1 (e.g. 0.25 for 25%)"}
      end)
    else
      :ok
    end
  end

  defp unit(changeset) do
    case changeset.context[:improvement_metric] do
      %{unit: unit} -> unit
      _ -> Ash.Changeset.get_attribute(changeset, :unit)
    end
  end

  defp in_unit_range?(%Decimal{} = value),
    do: Decimal.compare(value, 0) != :lt and Decimal.compare(value, 1) != :gt

  defp in_unit_range?(_value), do: false
end
