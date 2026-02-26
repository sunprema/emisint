defmodule Emisint.Registry.StudentTest do
  use Emisint.DataCase, async: true

  alias Emisint.Registry.Student

  defp org_id, do: Ash.UUID.generate()

  defp valid_attrs do
    %{uic: "1234567", first_name: "Jane", last_name: "Doe"}
  end

  describe "create/1" do
    test "creates a student with required attrs" do
      oid = org_id()

      assert {:ok, student} = Ash.create(Student, valid_attrs(), tenant: oid, authorize?: false)

      assert student.uic == "1234567"
      assert student.first_name == "Jane"
      assert student.last_name == "Doe"
      assert student.active == true
      assert student.economically_disadvantaged == false
      assert student.english_learner == false
      assert student.special_education == false
      assert student.organization_id == oid
    end

    test "creates with ESSA subgroup flags" do
      oid = org_id()

      assert {:ok, student} =
               Ash.create(
                 Student,
                 %{uic: "9876543", first_name: "John", last_name: "Smith", economically_disadvantaged: true, english_learner: true},
                 tenant: oid,
                 authorize?: false
               )

      assert student.economically_disadvantaged == true
      assert student.english_learner == true
      assert student.special_education == false
    end

    test "creates with all demographic attrs" do
      oid = org_id()

      assert {:ok, student} =
               Ash.create(
                 Student,
                 %{uic: "1111111", first_name: "Alex", last_name: "Rivera", date_of_birth: ~D[2010-05-15], gender: :nonbinary},
                 tenant: oid,
                 authorize?: false
               )

      assert student.date_of_birth == ~D[2010-05-15]
      assert student.gender == :nonbinary
    end

    test "requires uic" do
      assert {:error, error} =
               Ash.create(Student, %{first_name: "Jane", last_name: "Doe"}, tenant: org_id(), authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :uic))
    end

    test "enforces unique uic per org" do
      oid = org_id()
      Ash.create!(Student, valid_attrs(), tenant: oid, authorize?: false)

      assert {:error, error} = Ash.create(Student, valid_attrs(), tenant: oid, authorize?: false)
      assert error.errors |> Enum.any?(&(&1.field == :uic))
    end

    test "same uic is allowed across different orgs" do
      assert {:ok, _} = Ash.create(Student, valid_attrs(), tenant: org_id(), authorize?: false)
      assert {:ok, _} = Ash.create(Student, valid_attrs(), tenant: org_id(), authorize?: false)
    end

    test "rejects invalid gender" do
      assert {:error, _} =
               Ash.create(Student, Map.put(valid_attrs(), :gender, :unknown), tenant: org_id(), authorize?: false)
    end
  end

  describe "bulk_upsert/1" do
    test "inserts a new student via bulk_upsert" do
      oid = org_id()

      assert {:ok, student} =
               Student
               |> Ash.Changeset.for_create(:bulk_upsert, valid_attrs(), tenant: oid)
               |> Ash.create(authorize?: false)

      assert student.uic == "1234567"
    end

    test "updates an existing student on uic collision via bulk_upsert" do
      oid = org_id()

      Ash.create!(Student, valid_attrs(), tenant: oid, authorize?: false)

      assert {:ok, updated} =
               Student
               |> Ash.Changeset.for_create(:bulk_upsert, Map.put(valid_attrs(), :first_name, "Janet"), tenant: oid)
               |> Ash.create(authorize?: false)

      assert updated.first_name == "Janet"
      assert updated.uic == "1234567"

      {:ok, all} = Ash.read(Student, tenant: oid, authorize?: false)
      assert length(all) == 1
    end
  end

  describe "multitenancy" do
    test "read is scoped to organization" do
      oid1 = org_id()
      oid2 = org_id()

      Ash.create!(Student, valid_attrs(), tenant: oid1, authorize?: false)
      Ash.create!(Student, valid_attrs(), tenant: oid2, authorize?: false)

      {:ok, results} = Ash.read(Student, tenant: oid1, authorize?: false)

      assert length(results) == 1
      assert hd(results).organization_id == oid1
    end
  end
end
