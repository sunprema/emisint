defmodule Emisint.Reports.School.CrdComparisonPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{
    MdeCompositeResidentDistrict,
    MdeDistrict,
    MdeDistrictSnapshot,
    MdeEntityMaster
  }

  alias Emisint.Reports.School.CrdComparisonPdf

  @charter_district_code "63010"
  @resident_district_code "25010"
  @year "24 - 25 School Year"

  defp seed_entity do
    Ash.create!(
      MdeEntityMaster,
      %{
        entity_code: "12345",
        entity_official_name: "Achieve Charter Academy",
        district_code: @charter_district_code,
        entity_status: "Open-Active"
      },
      authorize?: false
    )
  end

  defp seed_charter_snapshot do
    Ash.create!(
      MdeDistrictSnapshot,
      %{
        district_code: @charter_district_code,
        school_year: @year,
        district_name: "Achieve Charter Academy",
        all_subjects: %{
          "ELA" => 60.0,
          "Mathematics" => 55.0,
          "Science" => 50.0,
          "Social Studies" => 52.0
        }
      },
      authorize?: false
    )
  end

  defp seed_resident do
    resident_district =
      Ash.create!(
        MdeDistrict,
        %{district_code: @resident_district_code, district_name: "Flint Community Schools"},
        authorize?: false
      )

    Ash.create!(
      MdeDistrictSnapshot,
      %{
        district_code: @resident_district_code,
        school_year: @year,
        district_name: "Flint Community Schools",
        all_subjects: %{
          "ELA" => 45.0,
          "Mathematics" => 40.0,
          "Science" => 38.0,
          "Social Studies" => 42.0
        }
      },
      authorize?: false
    )

    Ash.create!(
      MdeCompositeResidentDistrict,
      %{
        school_year: @year,
        charter_district_code: @charter_district_code,
        crd_district_code: "opaque-1",
        resident_entity_name: "Flint Community Schools",
        nonresident_students_enrolled: 30,
        mde_district_id: resident_district.id
      },
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when real data is present" do
      seed_entity()
      seed_charter_snapshot()
      seed_resident()

      assert {:ok, pdf} = CrdComparisonPdf.generate_report(@charter_district_code, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "generates a PDF from an empty database (no resident districts on file)" do
      assert {:ok, pdf} = CrdComparisonPdf.generate_report("00000", @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end
end
