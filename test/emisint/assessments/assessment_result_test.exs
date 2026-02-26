defmodule Emisint.Assessments.AssessmentResultTest do
  use Emisint.DataCase, async: true

  alias Emisint.Assessments.AssessmentResult
  alias Emisint.Registry.{Student, AcademicYear}

  defp org_id, do: Ash.UUID.generate()

  defp create_student(oid, uic \\ "1234567") do
    Ash.create!(Student, %{uic: uic, first_name: "Jane", last_name: "Doe"}, tenant: oid, authorize?: false)
  end

  defp create_year(oid, label \\ "2024-2025") do
    Ash.create!(AcademicYear, %{label: label, start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
      tenant: oid,
      authorize?: false
    )
  end

  defp result_attrs(student, year, overrides \\ %{}) do
    Map.merge(
      %{
        assessment_type: :m_step,
        subject: "math",
        testing_window: :spring,
        student_id: student.id,
        academic_year_id: year.id
      },
      overrides
    )
  end

  describe "create/1" do
    test "creates a result with required attrs" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)

      assert {:ok, result} =
               Ash.create(AssessmentResult, result_attrs(student, year), tenant: oid, authorize?: false)

      assert result.assessment_type == :m_step
      assert result.subject == "math"
      assert result.testing_window == :spring
      assert result.student_id == student.id
      assert result.academic_year_id == year.id
      assert result.organization_id == oid
    end

    test "creates with all optional score fields" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)

      attrs =
        result_attrs(student, year, %{
          raw_score: Decimal.new("42.5"),
          scale_score: Decimal.new("1582"),
          proficiency_level: "3",
          sgp: 67,
          growth_target: Decimal.new("50.0"),
          percentile: 72,
          test_date: ~D[2025-05-15],
          source: "MiDataHub"
        })

      assert {:ok, result} = Ash.create(AssessmentResult, attrs, tenant: oid, authorize?: false)

      assert result.sgp == 67
      assert result.percentile == 72
      assert result.proficiency_level == "3"
      assert result.source == "MiDataHub"
      assert result.test_date == ~D[2025-05-15]
    end

    test "accepts all assessment types" do
      oid = org_id()
      year = create_year(oid)

      types = [:m_step, :psat_8_9, :psat_10, :sat, :nwea_map, :i_ready]

      for {type, i} <- Enum.with_index(types) do
        student = create_student(oid, "UIC#{i}")

        assert {:ok, result} =
                 Ash.create(
                   AssessmentResult,
                   result_attrs(student, year, %{assessment_type: type}),
                   tenant: oid,
                   authorize?: false
                 )

        assert result.assessment_type == type
      end
    end

    test "rejects invalid assessment_type" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)

      assert {:error, _} =
               Ash.create(
                 AssessmentResult,
                 result_attrs(student, year, %{assessment_type: :unknown_test}),
                 tenant: oid,
                 authorize?: false
               )
    end

    test "enforces unique identity per student/year/type/subject/window" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      attrs = result_attrs(student, year)

      assert {:ok, _} = Ash.create(AssessmentResult, attrs, tenant: oid, authorize?: false)

      assert {:error, error} = Ash.create(AssessmentResult, attrs, tenant: oid, authorize?: false)

      assert error.errors
             |> Enum.any?(
               &(&1.field in [:student_id, :academic_year_id, :assessment_type, :subject, :testing_window])
             )
    end
  end

  describe "bulk_upsert/1" do
    test "inserts a new record when no conflict exists" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)

      assert {:ok, result} =
               Ash.create(
                 AssessmentResult,
                 result_attrs(student, year, %{sgp: 55, source: "CSV"}),
                 action: :bulk_upsert,
                 tenant: oid,
                 authorize?: false
               )

      assert result.sgp == 55
    end

    test "updates score fields on identity conflict" do
      oid = org_id()
      student = create_student(oid)
      year = create_year(oid)
      base_attrs = result_attrs(student, year)

      Ash.create!(AssessmentResult, Map.put(base_attrs, :sgp, 40), tenant: oid, authorize?: false)

      assert {:ok, upserted} =
               Ash.create(
                 AssessmentResult,
                 Map.put(base_attrs, :sgp, 65),
                 action: :bulk_upsert,
                 tenant: oid,
                 authorize?: false
               )

      assert upserted.sgp == 65

      # Confirm only one record exists
      {:ok, results} = Ash.read(AssessmentResult, tenant: oid, authorize?: false)
      assert length(results) == 1
    end
  end

  describe "multitenancy" do
    test "read is scoped to organization" do
      oid1 = org_id()
      oid2 = org_id()

      s1 = create_student(oid1)
      y1 = create_year(oid1)
      Ash.create!(AssessmentResult, result_attrs(s1, y1), tenant: oid1, authorize?: false)

      s2 = create_student(oid2)
      y2 = create_year(oid2)
      Ash.create!(AssessmentResult, result_attrs(s2, y2), tenant: oid2, authorize?: false)

      {:ok, results} = Ash.read(AssessmentResult, tenant: oid1, authorize?: false)
      assert length(results) == 1
      assert hd(results).organization_id == oid1
    end
  end

  describe "FK constraints" do
    test "rejects invalid student_id" do
      oid = org_id()
      year = create_year(oid)

      assert {:error, _} =
               Ash.create(
                 AssessmentResult,
                 %{
                   assessment_type: :m_step,
                   subject: "math",
                   testing_window: :spring,
                   student_id: Ash.UUID.generate(),
                   academic_year_id: year.id
                 },
                 tenant: oid,
                 authorize?: false
               )
    end
  end
end
