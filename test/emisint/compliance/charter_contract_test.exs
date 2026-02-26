defmodule Emisint.Compliance.CharterContractTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Compliance.CharterContract

  defp org_id, do: Ash.UUID.generate()

  defp create_school(oid) do
    Ash.create!(School, %{name: "Test School", mde_district_code: "80010", mde_building_code: "08001"},
      tenant: oid,
      authorize?: false
    )
  end

  defp valid_attrs(school_id) do
    %{
      authorizer_name: "CMU",
      contract_start_date: ~D[2022-07-01],
      contract_end_date: ~D[2027-06-30],
      school_id: school_id
    }
  end

  describe "create/1" do
    test "creates a charter contract with required attrs" do
      oid = org_id()
      school = create_school(oid)

      assert {:ok, contract} =
               Ash.create(CharterContract, valid_attrs(school.id), tenant: oid, authorize?: false)

      assert contract.authorizer_name == "CMU"
      assert contract.contract_start_date == ~D[2022-07-01]
      assert contract.contract_end_date == ~D[2027-06-30]
      assert contract.status == :active
      assert contract.school_id == school.id
      assert contract.organization_id == oid
    end

    test "creates with optional reauthorization_date" do
      oid = org_id()
      school = create_school(oid)

      attrs = Map.put(valid_attrs(school.id), :reauthorization_date, ~D[2026-09-01])

      assert {:ok, contract} = Ash.create(CharterContract, attrs, tenant: oid, authorize?: false)

      assert contract.reauthorization_date == ~D[2026-09-01]
    end

    test "accepts all status values" do
      oid = org_id()
      school = create_school(oid)

      for status <- [:active, :expired, :under_review, :reauthorized] do
        attrs = valid_attrs(school.id) |> Map.put(:status, status)
        assert {:ok, contract} = Ash.create(CharterContract, attrs, tenant: oid, authorize?: false)
        assert contract.status == status
      end
    end
  end

  describe "update/1" do
    test "updates status and dates" do
      oid = org_id()
      school = create_school(oid)
      contract = Ash.create!(CharterContract, valid_attrs(school.id), tenant: oid, authorize?: false)

      assert {:ok, updated} =
               Ash.update(contract, %{status: :under_review, reauthorization_date: ~D[2027-01-15]},
                 tenant: oid,
                 authorize?: false
               )

      assert updated.status == :under_review
      assert updated.reauthorization_date == ~D[2027-01-15]
    end
  end

  describe "paper trail" do
    test "creates a version record on update" do
      oid = org_id()
      school = create_school(oid)
      contract = Ash.create!(CharterContract, valid_attrs(school.id), tenant: oid, authorize?: false)

      Ash.update!(contract, %{status: :expired}, tenant: oid, authorize?: false)

      loaded = Ash.load!(contract, :paper_trail_versions, tenant: oid, authorize?: false)
      assert length(loaded.paper_trail_versions) >= 1
    end

    test "version records the changed action type" do
      oid = org_id()
      school = create_school(oid)
      contract = Ash.create!(CharterContract, valid_attrs(school.id), tenant: oid, authorize?: false)

      Ash.update!(contract, %{status: :expired}, tenant: oid, authorize?: false)

      loaded = Ash.load!(contract, :paper_trail_versions, tenant: oid, authorize?: false)
      update_version = Enum.find(loaded.paper_trail_versions, &(&1.version_action_type == :update))
      assert update_version != nil
    end
  end

  describe "code interface" do
    test "create_charter_contract/2 works via domain" do
      oid = org_id()
      school = create_school(oid)

      assert {:ok, contract} =
               Emisint.Compliance.create_charter_contract(valid_attrs(school.id),
                 tenant: oid,
                 authorize?: false
               )

      assert contract.authorizer_name == "CMU"
    end
  end
end
