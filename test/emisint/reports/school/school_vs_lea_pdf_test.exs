defmodule Emisint.Reports.School.SchoolVsLeaPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{
    MdeBuilding,
    MdeEntityMaster,
    MdeEnrollmentResult,
    MdeIndexThreshold,
    MdeIsd,
    MdeSatResult,
    MdeSchoolIndexResult,
    MdeSchoolVsLeaSnapshot,
    MdeSgpResult
  }

  alias Emisint.Reports.School.SchoolVsLeaPdf

  @building_code "12345"
  @year "24 - 25 School Year"

  defp seed_entity do
    Ash.create!(
      MdeEntityMaster,
      %{entity_code: @building_code, entity_official_name: "Achieve Charter Academy"},
      authorize?: false
    )
  end

  # No `lea_district_code` set — every LEA-comparison branch is nil-safe by
  # design (see `load_lea_enrollment_data/2`, `load_sat_score_bars/3`,
  # `load_econ_grade_breakdown/3`), so this exercises the "no LEA on file"
  # path deliberately rather than needing a second district's full data set.
  defp seed_snapshot do
    Ash.create!(
      MdeSchoolVsLeaSnapshot,
      %{
        building_code: @building_code,
        school_year: @year,
        school_name: "Achieve Charter Academy",
        above_lea: 3,
        below_lea: 1,
        above_state: 4,
        grades_compared: 4,
        subject_comparison: [
          %{
            "subject" => "ELA",
            "school_pct" => 60.0,
            "lea_pct" => nil,
            "state_pct" => 45.0,
            "delta" => nil
          },
          %{
            "subject" => "Mathematics",
            "school_pct" => 55.0,
            "lea_pct" => nil,
            "state_pct" => 40.0,
            "delta" => nil
          }
        ],
        grade_breakdown: [
          %{
            "grade" => "5",
            "school_ela" => 60.0,
            "school_ela_suppressed" => false,
            "school_ela_approximate" => false,
            "school_math" => 55.0,
            "school_math_suppressed" => false,
            "school_math_approximate" => false
          }
        ],
        all_subjects_avg: %{
          "school_pct" => 57.5,
          "lea_pct" => nil,
          "state_pct" => 42.5,
          "delta" => nil
        }
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
  end

  defp seed_dimensions do
    building =
      Ash.create!(
        MdeBuilding,
        %{building_code: @building_code, building_name: "Achieve Charter Academy"},
        authorize?: false
      )

    state_isd = Ash.create!(MdeIsd, %{isd_code: "0", isd_name: "Statewide"}, authorize?: false)
    %{building: building, state_isd: state_isd}
  end

  defp seed_school_index(building) do
    Ash.create!(
      MdeSchoolIndexResult,
      %{
        mde_building_id: building.id,
        school_year: "2024-2025",
        overall_index: Decimal.new("62.5")
      },
      authorize?: false
    )

    Ash.create!(
      MdeIndexThreshold,
      %{school_year: "2024-2025", component: :overall, threshold_value: Decimal.new("35.3")},
      authorize?: false
    )
  end

  defp seed_sgp(building) do
    Ash.create!(
      MdeSgpResult,
      %{
        rollup_level: :building,
        mde_building_id: building.id,
        school_year: @year,
        grade: "5",
        subject: "Mathematics",
        testing_group: "All Students",
        mean_sgp: Decimal.new("48.0"),
        total_included: 50
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
        math_score_average: Decimal.new("510.0"),
        ebrw_score_average: Decimal.new("520.0"),
        all_subject_score_average: Decimal.new("1030.0")
      },
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when a school-vs-LEA snapshot exists" do
      seed_entity()
      seed_snapshot()
      seed_enrollment()
      %{building: building} = seed_dimensions()
      seed_school_index(building)
      seed_sgp(building)
      seed_sat()

      assert {:ok, pdf} = SchoolVsLeaPdf.generate_report(@building_code, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "generates a PDF from an empty database (no snapshot computed yet)" do
      assert {:ok, pdf} = SchoolVsLeaPdf.generate_report("00000", @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end
end
