defmodule Emisint.Accounts.SchoolTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School

  defp org_id, do: Ash.UUID.generate()

  defp valid_attrs do
    %{name: "Great Lakes Academy", mde_district_code: "80010", mde_building_code: "08001"}
  end

  defp create_school(oid, overrides \\ %{}) do
    Ash.create!(School, Map.merge(valid_attrs(), overrides), tenant: oid, authorize?: false)
  end

  describe "create/1" do
    test "creates a school with required attrs" do
      oid = org_id()

      assert {:ok, school} =
               Ash.create(School, valid_attrs(), tenant: oid, authorize?: false)

      assert school.name == "Great Lakes Academy"
      assert school.mde_district_code == "80010"
      assert school.mde_building_code == "08001"
      assert school.active == true
      assert school.organization_id == oid
    end

    test "creates with all optional attrs" do
      oid = org_id()

      assert {:ok, school} =
               Ash.create(
                 School,
                 %{
                   name: "Northern Academy",
                   mde_district_code: "72000",
                   mde_building_code: "07200",
                   city: "Flint",
                   county: "Genesee"
                 },
                 tenant: oid,
                 authorize?: false
               )

      assert school.city == "Flint"
      assert school.county == "Genesee"
    end

    test "requires name" do
      assert {:error, error} =
               Ash.create(
                 School,
                 %{mde_district_code: "80010", mde_building_code: "08001"},
                 tenant: org_id(),
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :name))
    end

    test "requires mde_district_code" do
      assert {:error, error} =
               Ash.create(
                 School,
                 %{name: "Some School", mde_building_code: "08001"},
                 tenant: org_id(),
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :mde_district_code))
    end

    test "requires mde_building_code" do
      assert {:error, error} =
               Ash.create(
                 School,
                 %{name: "Some School", mde_district_code: "80010"},
                 tenant: org_id(),
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :mde_building_code))
    end

    test "enforces unique building code per org" do
      oid = org_id()
      create_school(oid)

      assert {:error, error} =
               Ash.create(School, valid_attrs(), tenant: oid, authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :mde_building_code))
    end

    test "same building code is allowed in different orgs" do
      assert {:ok, _} = Ash.create(School, valid_attrs(), tenant: org_id(), authorize?: false)
      assert {:ok, _} = Ash.create(School, valid_attrs(), tenant: org_id(), authorize?: false)
    end
  end

  describe "update/1" do
    test "updates name, city, county and active" do
      oid = org_id()
      school = create_school(oid)

      assert {:ok, updated} =
               Ash.update(school, %{name: "Renamed Academy", city: "Detroit", active: false},
                 tenant: oid,
                 authorize?: false
               )

      assert updated.name == "Renamed Academy"
      assert updated.city == "Detroit"
      assert updated.active == false
    end

    test "mde codes are immutable (not in update accept list)" do
      oid = org_id()
      school = create_school(oid)

      # Ash 3.x raises NoSuchInput for fields not in the accept list
      assert {:error, error} =
               Ash.update(school, %{name: "Updated", mde_building_code: "99999"},
                 tenant: oid,
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&match?(%Ash.Error.Invalid.NoSuchInput{input: :mde_building_code}, &1))
    end
  end

  describe "multitenancy" do
    test "read is scoped to organization" do
      oid1 = org_id()
      oid2 = org_id()

      create_school(oid1)
      create_school(oid2)

      {:ok, results} = Ash.read(School, tenant: oid1, authorize?: false)

      assert length(results) == 1
      assert hd(results).organization_id == oid1
    end
  end

  describe "code interface" do
    test "create_school/2 works via domain" do
      assert {:ok, school} =
               Emisint.Accounts.create_school(valid_attrs(), tenant: org_id(), authorize?: false)

      assert school.mde_building_code == "08001"
    end

    test "get_school_by_building_code/2 works via domain" do
      oid = org_id()
      create_school(oid)

      assert {:ok, school} =
               Emisint.Accounts.get_school_by_building_code("08001", tenant: oid, authorize?: false)

      assert school.mde_building_code == "08001"
    end
  end

  describe "enrollment FK" do
    test "enrollment school_id references schools table" do
      alias Emisint.Registry.{Enrollment, Student, AcademicYear}

      oid = org_id()

      school = create_school(oid)

      student =
        Ash.create!(Student, %{uic: "1234567", first_name: "Jane", last_name: "Doe"},
          tenant: oid,
          authorize?: false
        )

      year =
        Ash.create!(AcademicYear, %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
          tenant: oid,
          authorize?: false
        )

      assert {:ok, enrollment} =
               Ash.create(
                 Enrollment,
                 %{
                   grade_level: :g5,
                   enrolled_at: ~D[2024-09-03],
                   student_id: student.id,
                   academic_year_id: year.id,
                   school_id: school.id
                 },
                 tenant: oid,
                 authorize?: false
               )

      assert enrollment.school_id == school.id
    end

    test "enrollment rejects invalid school_id FK" do
      alias Emisint.Registry.{Enrollment, Student, AcademicYear}

      oid = org_id()

      student =
        Ash.create!(Student, %{uic: "7654321", first_name: "Bob", last_name: "Jones"},
          tenant: oid,
          authorize?: false
        )

      year =
        Ash.create!(AcademicYear, %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
          tenant: oid,
          authorize?: false
        )

      assert {:error, _} =
               Ash.create(
                 Enrollment,
                 %{
                   grade_level: :g5,
                   enrolled_at: ~D[2024-09-03],
                   student_id: student.id,
                   academic_year_id: year.id,
                   school_id: Ash.UUID.generate()
                 },
                 tenant: oid,
                 authorize?: false
               )
    end
  end
end
