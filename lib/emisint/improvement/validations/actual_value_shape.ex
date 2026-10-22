defmodule Emisint.Improvement.Validations.ActualValueShape do
  @moduledoc """
  Enforces which value fields an `ActualResult` may carry for its `value_state`:

    * `:exact`       — `value` required; no range
    * `:range`       — `range_low` and `range_high` required, low ≤ high; no `value`
    * `:suppressed`  — no value or range (optional verbatim `suppression_reason`)
    * `:unavailable` — no value or range; `notes` must explain why

  Options:

    * `:require_measurement_date?` — require `measurement_date` for `:exact`
      and `:range` results (used by manual entry actions)
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    state = get.(:value_state)

    with :ok <- shape(state, get.(:value), get.(:range_low), get.(:range_high)),
         :ok <- explanation(state, get.(:notes)),
         :ok <- suppression_reason(state, get.(:suppression_reason)) do
      measurement_date(state, get.(:measurement_date), opts[:require_measurement_date?])
    end
  end

  defp shape(:exact, value, low, high) do
    cond do
      is_nil(value) ->
        {:error, field: :value, message: "is required for an exact result"}

      not (is_nil(low) and is_nil(high)) ->
        {:error, field: :range_low, message: "must be blank for an exact result"}

      true ->
        :ok
    end
  end

  defp shape(:range, value, low, high) do
    cond do
      not is_nil(value) ->
        {:error, field: :value, message: "must be blank for a ranged result"}

      is_nil(low) ->
        {:error, field: :range_low, message: "is required for a ranged result"}

      is_nil(high) ->
        {:error, field: :range_high, message: "is required for a ranged result"}

      Decimal.compare(low, high) == :gt ->
        {:error, field: :range_low, message: "must not exceed range_high"}

      true ->
        :ok
    end
  end

  defp shape(state, value, low, high) when state in [:suppressed, :unavailable] do
    if Enum.all?([value, low, high], &is_nil/1),
      do: :ok,
      else: {:error, field: :value, message: "must be blank for a #{state} result"}
  end

  defp shape(_state, _value, _low, _high), do: :ok

  defp explanation(:unavailable, notes) when notes in [nil, ""],
    do: {:error, field: :notes, message: "must explain why the result is unavailable"}

  defp explanation(_state, _notes), do: :ok

  defp suppression_reason(:suppressed, _reason), do: :ok
  defp suppression_reason(_state, nil), do: :ok

  defp suppression_reason(_state, _reason),
    do: {:error, field: :suppression_reason, message: "only applies to suppressed results"}

  defp measurement_date(state, nil, true) when state in [:exact, :range],
    do: {:error, field: :measurement_date, message: "is required"}

  defp measurement_date(_state, _date, _required?), do: :ok
end
