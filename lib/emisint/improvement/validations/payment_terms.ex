defmodule Emisint.Improvement.Validations.PaymentTerms do
  @moduledoc """
  Payment terms on a goal plan. Each checkpoint allocation is set on its own
  (a checkpoint without one is "payment allocation needs confirmation"); a
  set allocation may not be negative and may not exceed the payment cap
  (the workbook's "up to $70,000" ceiling) when a cap is set.

  Until November 13, 2026 the two allocations had to be set together and
  sum to the cap; that encoded the withdrawn $35,000 / $35,000 assumption.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    cap = Ash.Changeset.get_attribute(changeset, :payment_cap)

    [:allocation_18m, :allocation_36m]
    |> Enum.map(&{&1, Ash.Changeset.get_attribute(changeset, &1)})
    |> Enum.find_value(:ok, fn
      {_field, nil} ->
        nil

      {field, amount} ->
        cond do
          Decimal.negative?(amount) ->
            {:error, field: field, message: "can't be negative"}

          cap != nil and Decimal.compare(amount, cap) == :gt ->
            {:error, field: field, message: "can't exceed the payment cap (#{cap})"}

          true ->
            nil
        end
    end)
  end
end
