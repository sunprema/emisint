defmodule Emisint.Improvement.Checks.CanReadSchoolData do
  @moduledoc """
  Filter check for school-scoped tenant data.

  An `emo_admin` may read every record in their own organization. Anyone else
  must hold a `SchoolMembership` for the record's school. Both paths also
  require `organization_id == actor.organization_id`, so passing a forged
  tenant returns nothing. System admins are handled by each resource's bypass.

  Options:

    * `:via` — how to reach the membership from the record:
      * `:self`   — the record is the school (`memberships`)
      * `:school` — the record has a `school` relationship (`school.memberships`)
      * `:user`   — the record is itself a membership (`user_id`)
      * `:none`   — org admins only
  """
  use Ash.Policy.FilterCheck

  @impl true
  def describe(opts), do: "actor can read school data via #{inspect(opts[:via])}"

  @impl true
  def filter(%{role: :emo_admin, organization_id: org_id}, _authorizer, _opts)
      when not is_nil(org_id) do
    expr(organization_id == ^org_id)
  end

  def filter(%{id: user_id, organization_id: org_id}, _authorizer, opts)
      when not is_nil(org_id) do
    case opts[:via] do
      :self ->
        expr(organization_id == ^org_id and exists(memberships, user_id == ^user_id))

      :school ->
        expr(organization_id == ^org_id and exists(school.memberships, user_id == ^user_id))

      :user ->
        expr(organization_id == ^org_id and user_id == ^user_id)

      :none ->
        false
    end
  end

  def filter(_actor, _authorizer, _opts), do: false
end
