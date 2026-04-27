# =============================================================================
# Emisint Development Seeds
#
# Run with:
#   mix run priv/repo/seeds.exs
#   (or as part of: mix ash.reset)
#
# Idempotent: skips if an organization with slug "cornerstone-emo" already exists.
# =============================================================================

alias Emisint.Accounts.{Organization, User}

existing_orgs = Ash.read!(Organization, authorize?: false)

if Enum.any?(existing_orgs, &(&1.slug == "cornerstone-emo")) do
  IO.puts("Seeds already applied — skipping. Run `mix ash.reset` to start fresh.")
else
  IO.puts("Seeding Emisint demo data…")

  org =
    Ash.create!(
      Organization,
      %{name: "Cornerstone Education Management", type: :emo, slug: "cornerstone-emo"},
      authorize?: false
    )

  IO.puts("  ✓ Organization: #{org.name}")

  oid = org.id

  create_user = fn email, role ->
    {:ok, user} =
      Ash.create(
        User,
        %{
          email: email,
          password: "Password123!",
          password_confirmation: "Password123!"
        },
        action: :register_with_password,
        authorize?: false
      )

    Ash.update!(user, %{organization_id: oid, role: role},
      action: :assign_organization,
      authorize?: false
    )

    user
    |> Ash.Changeset.for_update(:assign_organization, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(
      :confirmed_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Ash.update!()

    user
  end

  _admin = create_user.("admin@cornerstone-emo.edu", :emo_admin)
  _authorizer = create_user.("authorizer@cmu.edu", :authorizer_liaison)

  IO.puts("""

  ═══════════════════════════════════════════════════════
  ✓ Emisint demo data seeded successfully!

  Organization : Cornerstone Education Management

  Sign in at http://localhost:4000/sign-in
    EMO Admin   admin@cornerstone-emo.edu / Password123!
    Authorizer  authorizer@cmu.edu        / Password123!
  ═══════════════════════════════════════════════════════
  """)
end
