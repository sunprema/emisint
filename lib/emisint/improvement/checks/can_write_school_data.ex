defmodule Emisint.Improvement.Checks.CanWriteSchoolData do
  @moduledoc """
  Simple check for creates on school-scoped tenant data.

  Passes when the actor belongs to the changeset's tenant organization and is
  either an `emo_admin` or holds a membership on the changeset's `school_id`
  with one of the given `:roles`. With `roles: []` only org admins pass.

  Runs after the action's changes, so `school_id` is already derived from the
  parent record loaded inside the tenant (see `Changes.InheritScope` and
  `Changes.ScopeEntry`).
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias Emisint.Accounts.SchoolMembership

  @impl true
  def describe(opts),
    do: "actor is an org admin or a school member with role in #{inspect(opts[:roles] || [])}"

  @impl true
  def match?(%{organization_id: org_id} = actor, context, opts) when not is_nil(org_id) do
    changeset = context.changeset || context.subject

    same_tenant?(changeset, org_id) and
      (actor.role == :emo_admin or member?(actor, changeset, opts[:roles] || []))
  end

  def match?(_actor, _context, _opts), do: false

  defp same_tenant?(%Ash.Changeset{tenant: tenant}, org_id) when not is_nil(tenant),
    do: to_string(tenant) == to_string(org_id)

  defp same_tenant?(_changeset, _org_id), do: false

  defp member?(_actor, _changeset, []), do: false

  defp member?(actor, changeset, roles) do
    case Ash.Changeset.get_attribute(changeset, :school_id) do
      nil ->
        false

      school_id ->
        SchoolMembership
        |> Ash.Query.filter(user_id == ^actor.id and school_id == ^school_id and role in ^roles)
        |> Ash.exists?(tenant: changeset.tenant, authorize?: false)
    end
  end
end
