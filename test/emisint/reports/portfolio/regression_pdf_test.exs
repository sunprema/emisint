defmodule Emisint.Reports.Portfolio.RegressionPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{
    MdeEmoContact,
    MdeEntityMaster,
    MdeEnrollmentResult,
    MdeSatResult,
    MdeSchoolVsLeaSnapshot
  }

  alias Emisint.Reports.Portfolio.RegressionPdf

  @emo_name "Cornerstone Education Management"
  @district_code "63010"
  @building_code "12345"
  @year "24 - 25 School Year"

  defp seed_emo_contact do
    Ash.create!(
      MdeEmoContact,
      %{district_code: @district_code, management_organization: @emo_name},
      authorize?: false
    )
  end

  defp seed_school do
    Ash.create!(
      MdeEntityMaster,
      %{
        entity_code: @building_code,
        entity_official_name: "Achieve Charter Academy",
        district_code: @district_code,
        entity_status: "Open-Active"
      },
      authorize?: false
    )
  end

  defp seed_enrollment do
    Ash.create!(
      MdeEnrollmentResult,
      %{
        rollup_level: :building,
        school_year: @year,
        building_code: @building_code,
        total_enrollment: 400,
        economic_disadvantaged_enrollment: 200
      },
      authorize?: false
    )

    Ash.create!(
      MdeEnrollmentResult,
      %{
        rollup_level: :isd,
        school_year: @year,
        isd_code: "0",
        total_enrollment: 1_000_000,
        economic_disadvantaged_enrollment: 503_000
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

    Ash.create!(
      MdeSatResult,
      %{
        rollup_level: :isd,
        school_year: @year,
        isd_code: "0",
        subgroup: "All Students",
        all_subject_score_average: Decimal.new("1000.0")
      },
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when the ESP has a school with data (regression nil under 3 points)" do
      seed_emo_contact()
      seed_school()
      seed_enrollment()
      seed_mstep()
      seed_sat()

      assert {:ok, pdf} = RegressionPdf.generate_report(@emo_name, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "generates a PDF for an ESP with no schools on file" do
      assert {:ok, pdf} = RegressionPdf.generate_report("Nobody EMO", @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end
end
