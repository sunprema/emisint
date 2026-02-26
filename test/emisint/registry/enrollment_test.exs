defmodule Emisint.Registry.EnrollmentTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Registry.{Enrollment, Student, AcademicYear}

  defp org_id, do: Ash.UUID.generate()

  defp create_school(oid, building_code \\ "08001") do
    Ash.create!(School, %{name: "Test School", mde_district_code: "80010", mde_building_code: building_code},
      tenant: oid,
      authorize?: false
    )
  end

  defp create_student(oid, uic \\ "1234567") do
    Ash.create!(Student, %{uic: uic, first_name: "Jane", last_name: "Doe"}, tenant: oid, authorize?: false)
  end

  defp create_year(oid, label \\ "2024-2025") do
    Ash.create!(AcademicYear, %{label: label, start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]}, tenant: oid, authorize?: false)
  end

  defp enroll(oid, student, year, school_id, grade \\ :g5) do
    Ash.create(
      Enrollment,
      %{grade_level: grade, enrolled_at: ~D[2024-09-03], student_id: student.id, academic_year_id: year.id, school_id: school_id},
      tenant: oid,
      authorize?: false
    )
  end

  defp enroll!(oid, student, year, school_id, grade \\ :g5) do
    {:ok, enrollment} = enroll(oid, student, year, school_id, grade)
    enrollment
  end

  describe "create/1" do
    test "creates an enrollment with required attrs" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      school = create_school(oid)

      assert {:ok, enrollment} = enroll(oid, student, year, school.id)

      assert enrollment.grade_level == :g5
      assert enrollment.status == :active
      assert enrollment.student_id == student.id
      assert enrollment.academic_year_id == year.id
      assert enrollment.school_id == school.id
      assert enrollment.organization_id == oid
    end

    test "accepts all grade levels" do
      oid = org_id()
      year = create_year(oid)
      school = create_school(oid)

      grade_levels = [:pk, :k, :g1, :g2, :g3, :g4, :g5, :g6, :g7, :g8, :g9, :g10, :g11, :g12]

      for {grade, i} <- Enum.with_index(grade_levels) do
        student = create_student(oid, "UIC#{i}")
        assert {:ok, enrollment} = enroll(oid, student, year, school.id, grade)
        assert enrollment.grade_level == grade
      end
    end

    test "status defaults to :active" do
      oid = org_id()
      school = create_school(oid)
      enrollment = enroll!(oid, create_student(oid), create_year(oid), school.id)
      assert enrollment.status == :active
    end

    test "accepts all status values on update" do
      oid = org_id()
      school = create_school(oid)
      enrollment = enroll!(oid, create_student(oid), create_year(oid), school.id)

      assert {:ok, updated} = Ash.update(enrollment, %{status: :transferred}, tenant: oid, authorize?: false)
      assert updated.status == :transferred

      assert {:ok, withdrawn} = Ash.update(updated, %{status: :withdrawn}, tenant: oid, authorize?: false)
      assert withdrawn.status == :withdrawn
    end

    test "rejects invalid grade_level" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      school = create_school(oid)

      assert {:error, _} =
               Ash.create(
                 Enrollment,
                 %{grade_level: :college, enrolled_at: ~D[2024-09-03], student_id: student.id, academic_year_id: year.id, school_id: school.id},
                 tenant: oid,
                 authorize?: false
               )
    end

    test "enforces unique enrollment per student per year per school" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      school = create_school(oid)

      enroll!(oid, student, year, school.id)

      assert {:error, error} =
               Ash.create(
                 Enrollment,
                 %{grade_level: :g5, enrolled_at: ~D[2024-09-03], student_id: student.id, academic_year_id: year.id, school_id: school.id},
                 tenant: oid,
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field in [:student_id, :academic_year_id, :school_id]))
    end

    test "same student can enroll in different schools in same year" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      school1 = create_school(oid, "08001")
      school2 = create_school(oid, "08002")

      assert {:ok, _} = enroll(oid, student, year, school1.id)
      assert {:ok, _} = enroll(oid, student, year, school2.id)
    end

    test "records exited_at for withdrawn students" do
      oid = org_id()
      school = create_school(oid)
      enrollment = enroll!(oid, create_student(oid), create_year(oid), school.id)

      assert {:ok, updated} =
               Ash.update(enrollment, %{status: :withdrawn, exited_at: ~D[2024-12-15]}, tenant: oid, authorize?: false)

      assert updated.exited_at == ~D[2024-12-15]
    end
  end

  describe "multitenancy" do
    test "read is scoped to organization" do
      oid1 = org_id()
      oid2 = org_id()

      school1 = create_school(oid1)
      school2 = create_school(oid2)

      enroll!(oid1, create_student(oid1), create_year(oid1), school1.id)
      enroll!(oid2, create_student(oid2), create_year(oid2), school2.id)

      {:ok, results} = Ash.read(Enrollment, tenant: oid1, authorize?: false)
      assert length(results) == 1
      assert hd(results).organization_id == oid1
    end
  end
end
