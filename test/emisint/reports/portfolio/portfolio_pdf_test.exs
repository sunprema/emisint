defmodule Emisint.Reports.Portfolio.PortfolioPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{MdeEntityMaster, MdeSatResult, MdeSchoolVsLeaSnapshot}
  alias Emisint.Reports.Portfolio.PortfolioPdf

  @agency_code "AG001"
  @building_code "12345"
  @year "24 - 25 School Year"

  defp seed_school do
    Ash.create!(
      MdeEntityMaster,
      %{
        entity_code: @building_code,
        entity_official_name: "Achieve Charter Academy",
        district_code: "63010",
        entity_county_name: "Ingham",
        entity_actual_grades: "K-8",
        entity_authorized_grades: "K-8",
        entity_status: "Open-Active",
        entity_chartering_agency_code: @agency_code,
        entity_chartering_agency_name: "Grand Valley State University"
      },
      authorize?: false
    )
  end

  defp seed_mstep do
    Ash.create!(
      MdeSchoolVsLeaSnapshot,
      %{
        building_code: @building_code,
        school_year: @year,
        school_name: "Achieve Charter Academy",
        all_subjects_avg: %{
          "school_pct" => 57.5,
          "lea_pct" => 50.0,
          "state_pct" => 45.0,
          "delta" => 7.5
        }
      },
      authorize?: false
    )
  end

  defp seed_sat do
    Ash.create!(
      MdeSatResult,
      %{
        rollup_level: :building,
        school_year: @year,
        building_code: @building_code,
        subgroup: "All Students",
        all_subject_score_average: Decimal.new("1030.0")
      },
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when the agency has a school with data" do
      seed_school()
      seed_mstep()
      seed_sat()

      assert {:ok, pdf} = PortfolioPdf.generate_report(@agency_code, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "generates a PDF for an agency with no schools on file" do
      assert {:ok, pdf} = PortfolioPdf.generate_report("NOBODY", @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end
end
