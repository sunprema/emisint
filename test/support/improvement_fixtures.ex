defmodule Emisint.ImprovementFixtures do
  @moduledoc """
  Test helpers for the Improvement domain: organizations seeded with the
  Fort Yates definitions, users by role, and memberships.
  """
  require Ash.Query

  alias Emisint.Accounts.{Organization, School, SchoolMembership, User}
  alias Emisint.Improvement.{Metric, ReportingPeriod, Seeds}

  def organization!(name \\ "Test Org") do
    Ash.create!(
      Organization,
      %{name: name, type: :emo, slug: "org-#{System.unique_integer([:positive])}"},
      authorize?: false
    )
  end

  @doc "An organization with Fort Yates definitions seeded (no workbook ratings unless asked)."
  def seeded_organization!(opts \\ []) do
    org = organization!(Keyword.get(opts, :name, "Seeded Org"))

    {:ok, _report} =
      Seeds.run(org.id, workbook_ratings?: Keyword.get(opts, :workbook_ratings?, false))

    org
  end

  def user!(org_or_nil, role) do
    Ash.Seed.seed!(User, %{
      email: "user-#{System.unique_integer([:positive])}@example.com",
      hashed_password: "not-a-real-hash",
      role: role,
      organization_id: org_or_nil && org_or_nil.id
    })
  end

  def membership!(user, school, role, org) do
    Ash.create!(SchoolMembership, %{user_id: user.id, school_id: school.id, role: role},
      tenant: org.id,
      authorize?: false
    )
  end

  def school!(org, slug \\ "fort-yates-ms") do
    School |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(tenant: org.id, authorize?: false)
  end

  def metric!(org, code) do
    Metric |> Ash.Query.filter(code == ^code) |> Ash.read_one!(tenant: org.id, authorize?: false)
  end

  def period!(org, code) do
    ReportingPeriod
    |> Ash.Query.filter(code == ^code)
    |> Ash.read_one!(tenant: org.id, authorize?: false)
  end

  @doc "A contributor with a Fort Yates membership in `org`."
  def contributor!(org) do
    user = user!(org, :school_leader)
    membership!(user, school!(org), :contributor, org)
    user
  end

  def error_fields(%{errors: errors}), do: Enum.map(errors, &Map.get(&1, :field))

  @doc """
  Signs `user` into `conn` with a stored session token. System admins can pass
  `admin_org_id:` to select an organization, like the org switcher does.
  """
  def log_in(conn, user, session \\ %{}) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user = Ash.Resource.put_metadata(user, :token, token)

    conn
    |> Phoenix.ConnTest.init_test_session(session)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
