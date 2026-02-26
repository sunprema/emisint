defmodule Emisint.Scope do
  @moduledoc """
  The scope to be passed for multitenancy.
  In eminist, organization_id is the multitenant attribute.
  """

  defstruct [
    :current_user,
    :current_tenant
  ]

  defimpl Ash.Scope.ToOpts do
    def get_actor(%{current_user: current_user}), do: {:ok, current_user}
    def get_tenant(%{current_tenant: current_tenant}), do: {:ok, current_tenant}
    def get_context(context), do: {:ok, %{shared: context}}

    def get_tracer(_), do: :error
    def get_authorize?(_), do: :error
  end
end
