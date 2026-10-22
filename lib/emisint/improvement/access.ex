defmodule Emisint.Improvement.Access do
  @moduledoc """
  UI-facing permission helpers for school goal data.

  These only decide what to *show*. Every read and write is still authorized
  by the resource policies (`Checks.CanReadSchoolData`,
  `Checks.CanWriteSchoolData`), so a forged event fails even if a control is
  rendered by mistake.
  """
  require Ash.Query

  alias Emisint.Accounts.SchoolMembership

  @doc "Whether `actor` may record or correct actuals and ratings for `school` in `tenant`."
  def can_contribute?(nil, _tenant, _school), do: false
  def can_contribute?(%{role: :system_admin}, _tenant, _school), do: true

  def can_contribute?(%{role: :emo_admin, organization_id: org_id}, tenant, _school),
    do: same_org?(org_id, tenant)

  def can_contribute?(%{id: user_id, organization_id: org_id}, tenant, school) do
    same_org?(org_id, tenant) and
      SchoolMembership
      |> Ash.Query.filter(
        user_id == ^user_id and school_id == ^school.id and role == :contributor
      )
      |> Ash.exists?(tenant: tenant, authorize?: false)
  end

  defp same_org?(nil, _tenant), do: false
  defp same_org?(org_id, tenant), do: to_string(org_id) == to_string(tenant)
end
