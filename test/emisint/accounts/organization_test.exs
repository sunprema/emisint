defmodule Emisint.Accounts.OrganizationTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.Organization

  describe "create/1" do
    test "creates an organization with valid attrs" do
      assert {:ok, org} =
               Ash.create(Organization, %{name: "Great Lakes EMO", type: :emo, slug: "great-lakes-emo"},
                 authorize?: false
               )

      assert org.name == "Great Lakes EMO"
      assert org.type == :emo
      assert org.slug == "great-lakes-emo"
      assert org.active == true
      assert org.id != nil
    end

    test "creates an authorizer organization" do
      assert {:ok, org} =
               Ash.create(Organization, %{name: "CMU Authorizer", type: :authorizer, slug: "cmu-auth"},
                 authorize?: false
               )

      assert org.type == :authorizer
    end

    test "requires name" do
      assert {:error, error} =
               Ash.create(Organization, %{type: :emo, slug: "no-name"}, authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :name))
    end

    test "requires type" do
      assert {:error, error} =
               Ash.create(Organization, %{name: "Some Org", slug: "some-org"}, authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :type))
    end

    test "requires slug" do
      assert {:error, error} =
               Ash.create(Organization, %{name: "Some Org", type: :emo}, authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :slug))
    end

    test "rejects invalid type" do
      assert {:error, _error} =
               Ash.create(Organization, %{name: "Bad", type: :invalid, slug: "bad"},
                 authorize?: false
               )
    end

    test "enforces slug uniqueness" do
      Ash.create!(Organization, %{name: "First", type: :emo, slug: "shared-slug"}, authorize?: false)

      assert {:error, error} =
               Ash.create(Organization, %{name: "Second", type: :emo, slug: "shared-slug"},
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :slug))
    end
  end

  describe "read/1" do
    test "reads an organization with system_admin actor" do
      {:ok, org} =
        Ash.create(Organization, %{name: "Test EMO", type: :emo, slug: "test-emo"},
          authorize?: false
        )

      actor = %{role: :system_admin, organization_id: nil, id: Ash.UUID.generate()}

      assert {:ok, [found]} = Ash.read(Organization, actor: actor)
      assert found.id == org.id
    end

    test "actor can read their own organization" do
      {:ok, org} =
        Ash.create(Organization, %{name: "My EMO", type: :emo, slug: "my-emo"}, authorize?: false)

      actor = %{role: :school_leader, organization_id: org.id, id: Ash.UUID.generate()}

      assert {:ok, results} = Ash.read(Organization, actor: actor)
      assert Enum.any?(results, &(&1.id == org.id))
    end

    test "actor cannot read a different organization" do
      {:ok, _other_org} =
        Ash.create(Organization, %{name: "Other EMO", type: :emo, slug: "other-emo"},
          authorize?: false
        )

      {:ok, my_org} =
        Ash.create(Organization, %{name: "My EMO", type: :emo, slug: "my-emo2"},
          authorize?: false
        )

      actor = %{role: :school_leader, organization_id: my_org.id, id: Ash.UUID.generate()}

      assert {:ok, results} = Ash.read(Organization, actor: actor)
      assert length(results) == 1
      assert hd(results).id == my_org.id
    end
  end

  describe "update/1" do
    test "updates name and active with emo_admin actor" do
      {:ok, org} =
        Ash.create(Organization, %{name: "Old Name", type: :emo, slug: "update-test"},
          authorize?: false
        )

      actor = %{role: :emo_admin, organization_id: org.id, id: Ash.UUID.generate()}

      assert {:ok, updated} =
               Ash.update(org, %{name: "New Name", active: false}, actor: actor)

      assert updated.name == "New Name"
      assert updated.active == false
    end
  end

  describe "code interface" do
    test "create_organization/2 works via domain" do
      assert {:ok, org} =
               Emisint.Accounts.create_organization(%{name: "Interface EMO", type: :emo, slug: "iface-emo"},
                 authorize?: false
               )

      assert org.name == "Interface EMO"
    end

    test "get_organization_by_slug/2 works via domain" do
      Ash.create!(Organization, %{name: "Slug EMO", type: :emo, slug: "slug-lookup"},
        authorize?: false
      )

      assert {:ok, org} =
               Emisint.Accounts.get_organization_by_slug("slug-lookup", authorize?: false)

      assert org.slug == "slug-lookup"
    end
  end
end
