defmodule Emisint.Accounts.Validations.UserInTenant do
  @moduledoc """
  Ensures the changeset's `user_id` belongs to a user whose `organization_id`
  equals the changeset's tenant.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :user_id) do
      nil ->
        :ok

      user_id ->
        case Ash.get(Emisint.Accounts.User, user_id, authorize?: false) do
          {:ok, %{organization_id: org_id}} when not is_nil(org_id) ->
            if to_string(org_id) == to_string(changeset.tenant),
              do: :ok,
              else: {:error, field: :user_id, message: "belongs to a different organization"}

          {:ok, _user} ->
            {:error, field: :user_id, message: "is not assigned to an organization"}

          {:error, _} ->
            {:error, field: :user_id, message: "does not exist"}
        end
    end
  end
end
