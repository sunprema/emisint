defmodule Emisint.Assessments.CompetitorDataTest do
  use Emisint.DataCase, async: true

  alias Emisint.Assessments.CompetitorData

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        district_name: "Flint Community Schools",
        mde_district_code: "25010",
        subject: "math",
        grade_level: "5",
        proficiency_rate: Decimal.new("0.32"),
        academic_year_label: "2024-2025"
      },
      overrides
    )
  end

  describe "create/1" do
    test "creates competitor data with required attrs" do
      assert {:ok, data} = Ash.create(CompetitorData, valid_attrs(), authorize?: false)

      assert data.district_name == "Flint Community Schools"
      assert data.mde_district_code == "25010"
      assert data.subject == "math"
      assert data.grade_level == "5"
      assert Decimal.equal?(data.proficiency_rate, Decimal.new("0.32"))
      assert data.academic_year_label == "2024-2025"
    end

    test "creates with optional fields" do
      attrs = valid_attrs(%{average_sgp: Decimal.new("48.5"), student_count: 312})

      assert {:ok, data} = Ash.create(CompetitorData, attrs, authorize?: false)

      assert Decimal.equal?(data.average_sgp, Decimal.new("48.5"))
      assert data.student_count == 312
    end

    test "enforces unique constraint per district/subject/grade/year" do
      assert {:ok, _} = Ash.create(CompetitorData, valid_attrs(), authorize?: false)

      assert {:error, error} = Ash.create(CompetitorData, valid_attrs(), authorize?: false)

      assert error.errors
             |> Enum.any?(
               &(&1.field in [:mde_district_code, :subject, :grade_level, :academic_year_label])
             )
    end

    test "same district/subject allows different grade levels" do
      assert {:ok, _} = Ash.create(CompetitorData, valid_attrs(%{grade_level: "5"}), authorize?: false)
      assert {:ok, _} = Ash.create(CompetitorData, valid_attrs(%{grade_level: "6"}), authorize?: false)
    end

    test "same district/grade allows different subjects" do
      assert {:ok, _} = Ash.create(CompetitorData, valid_attrs(%{subject: "math"}), authorize?: false)
      assert {:ok, _} = Ash.create(CompetitorData, valid_attrs(%{subject: "ela"}), authorize?: false)
    end
  end

  describe "upsert/1" do
    test "inserts new record when no conflict" do
      assert {:ok, data} =
               Ash.create(CompetitorData, valid_attrs(), action: :upsert, authorize?: false)

      assert data.mde_district_code == "25010"
    end

    test "updates mutable fields on conflict" do
      Ash.create!(CompetitorData, valid_attrs(%{proficiency_rate: Decimal.new("0.32"), student_count: 300}),
        authorize?: false
      )

      assert {:ok, upserted} =
               Ash.create(
                 CompetitorData,
                 valid_attrs(%{proficiency_rate: Decimal.new("0.38"), student_count: 315}),
                 action: :upsert,
                 authorize?: false
               )

      assert Decimal.equal?(upserted.proficiency_rate, Decimal.new("0.38"))
      assert upserted.student_count == 315

      # Only one record exists
      {:ok, all} = Ash.read(CompetitorData, authorize?: false)
      assert length(all) == 1
    end
  end

  describe "no multitenancy (global data)" do
    test "data is readable without a tenant" do
      Ash.create!(CompetitorData, valid_attrs(), authorize?: false)

      assert {:ok, results} = Ash.read(CompetitorData, authorize?: false)
      assert length(results) == 1
    end
  end

  describe "code interface" do
    test "create_competitor_data/1 works via domain" do
      assert {:ok, data} = Emisint.Assessments.create_competitor_data(valid_attrs(), authorize?: false)
      assert data.subject == "math"
    end

    test "list_competitor_data/1 works via domain" do
      Ash.create!(CompetitorData, valid_attrs(%{grade_level: "3"}), authorize?: false)
      Ash.create!(CompetitorData, valid_attrs(%{grade_level: "4"}), authorize?: false)

      assert {:ok, results} = Emisint.Assessments.list_competitor_data(authorize?: false)
      assert length(results) == 2
    end
  end
end
