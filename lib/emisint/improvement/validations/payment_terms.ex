defmodule Emisint.Improvement.Validations.PaymentTerms do
  @moduledoc """
  Payment terms on a goal plan: when checkpoint allocations are set, both must
  be set, neither may be negative, and together they must equal the payment
  cap exactly.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    cap = Ash.Changeset.get_attribute(changeset, :payment_cap)
    a18 = Ash.Changeset.get_attribute(changeset, :allocation_18m)
    a36 = Ash.Changeset.get_attribute(changeset, :allocation_36m)

    cond do
      is_nil(a18) and is_nil(a36) ->
        :ok

      is_nil(a18) or is_nil(a36) ->
        {:error,
         field: :allocation_18m, message: "both checkpoint allocations must be set together"}

      is_nil(cap) ->
        {:error, field: :payment_cap, message: "is required when checkpoint allocations are set"}

      Decimal.compare(Decimal.add(a18, a36), cap) != :eq ->
        {:error,
         field: :allocation_18m,
         message: "checkpoint allocations (#{a18} + #{a36}) must sum to the payment cap (#{cap})"}

      true ->
        :ok
    end
  end
end
