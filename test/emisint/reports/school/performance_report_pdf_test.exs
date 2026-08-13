defmodule Emisint.Reports.School.PerformanceReportPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{
    MdeBuilding,
    MdeCompositeResidentDistrict,
    MdeDistrict,
    MdeEmoContact,
    MdeEntityMaster,
    MdeEnrollmentResult,
    MdeIsd,
    MdeSchoolIndexResult,
    MdeSgpResult,
    MdeStateAssessmentResult,
    MdeSssComparisonGroup,
    MdeSssComparisonGroupMember,
    MdeSssSchool
  }

  alias Emisint.Reports.School.PerformanceReportPdf

  @building_code "12345"
  @district_code "63010"
  @year "24 - 25 School Year"

  defp seed_entity do
    Ash.create!(
      MdeEntityMaster,
      %{
        entity_code: @building_code,
        entity_official_name: "Achieve Charter Academy",
        district_code: @district_code,
        entity_physical_street: "100 Main St",
        entity_physical_city: "Lansing",
        entity_physical_state: "MI",
        entity_physical_zip4: "48910",
        entity_authorized_grades: "K-8",
        entity_actual_grades: "K-8",
        entity_open_date: "1999-08-01",
        isd_official_name: "Capital Area ISD",
        entity_chartering_agency_name: "Grand Valley State University",
        entity_status: "Open-Active"
      },
      authorize?: false
    )
  end

  defp seed_dimensions do
    district =
      Ash.create!(
        MdeDistrict,
        %{district_code: @district_code, district_name: "Achieve Charter Academy"},
        authorize?: false
      )

    building =
      Ash.create!(
        MdeBuilding,
        %{
          building_code: @building_code,
          building_name: "Achieve Charter Academy",
          mde_district_id: district.id
        },
        authorize?: false
      )

    state_isd = Ash.create!(MdeIsd, %{isd_code: "0", isd_name: "Statewide"}, authorize?: false)

    %{building: building, state_isd: state_isd}
  end

  defp seed_enrollment do
    Ash.create!(
      MdeEnrollmentResult,
      %{
        rollup_level: :building,
        school_year: @year,
        building_code: @building_code,
        total_enrollment: 400,
        economic_disadvantaged_enrollment: 200,
        special_education_enrollment: 40,
        english_language_learners_enrollment: 20,
        kindergarten_enrollment: 40,
        grade_1_enrollment: 40,
        grade_2_enrollment: 40,
        grade_3_enrollment: 40,
        grade_4_enrollment: 40,
        grade_5_enrollment: 40,
        grade_6_enrollment: 40,
        grade_7_enrollment: 40,
        grade_8_enrollment: 40
      },
      authorize?: false
    )
  end

  defp seed_school_index(building) do
    Ash.create!(
      MdeSchoolIndexResult,
      %{
        mde_building_id: building.id,
        school_year: "2024-2025",
        overall_index: Decimal.new("62.5"),
        subject_participation_index: Decimal.new("98.0"),
        support_category_name: "Universal Support"
      },
      authorize?: false
    )
  end

  defp seed_sgp(building) do
    for {subject, sgp} <- [{"Mathematics", "48.0"}, {"English Language Arts", "52.0"}] do
      Ash.create!(
        MdeSgpResult,
        %{
          rollup_level: :building,
          mde_building_id: building.id,
          school_year: @year,
          grade: "All Grades",
          subject: subject,
          testing_group: "All Students",
          mean_sgp: Decimal.new(sgp),
          total_included: 150
        },
        authorize?: false
      )
    end
  end

  defp seed_proficiency(building, state_isd) do
    for {subject, grade} <- [{"ELA", "05"}, {"Mathematics", "05"}] do
      Ash.create!(
        MdeStateAssessmentResult,
        %{
          rollup_level: :building,
          mde_building_id: building.id,
          school_year: @year,
          test_type: "M-STEP",
          test_population: "Tested Students",
          grade_content_tested: grade,
          subject: subject,
          report_category: "All Students",
          percent_met: Decimal.new("60.0"),
          number_assessed: 50
        },
        authorize?: false
      )

      Ash.create!(
        MdeStateAssessmentResult,
        %{
          rollup_level: :isd,
          mde_isd_id: state_isd.id,
          school_year: @year,
          test_type: "M-STEP",
          test_population: "Tested Students",
          grade_content_tested: grade,
          subject: subject,
          report_category: "All Students",
          percent_met: Decimal.new("45.0"),
          number_assessed: 50_000
        },
        authorize?: false
      )
    end
  end

  defp seed_peer_roster do
    anchor =
      Ash.create!(
        MdeSssSchool,
        %{
          lookup_key: "anchor-#{@building_code}",
          school_code: @building_code,
          school_name: "Achieve Charter Academy"
        },
        authorize?: false
      )

    peer =
      Ash.create!(
        MdeSssSchool,
        %{lookup_key: "peer-54321", school_code: "54321", school_name: "Peer Academy"},
        authorize?: false
      )

    group =
      Ash.create!(
        MdeSssComparisonGroup,
        %{comparison_code: @building_code, anchor_school_id: anchor.id},
        authorize?: false
      )

    Ash.create!(
      MdeSssComparisonGroupMember,
      %{comparison_group_id: group.id, school_id: peer.id},
      authorize?: false
    )
  end

  defp seed_emo_contact do
    Ash.create!(
      MdeEmoContact,
      %{
        district_code: @district_code,
        management_organization: "Cornerstone Education Management"
      },
      authorize?: false
    )
  end

  defp seed_resident_district do
    Ash.create!(
      MdeCompositeResidentDistrict,
      %{
        school_year: @year,
        charter_district_code: @district_code,
        crd_district_code: "opaque-1",
        resident_entity_name: "Lansing School District",
        nonresident_students_enrolled: 120
      },
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when real data is present" do
      seed_entity()
      %{building: building, state_isd: state_isd} = seed_dimensions()
      seed_enrollment()
      seed_school_index(building)
      seed_sgp(building)
      seed_proficiency(building, state_isd)
      seed_peer_roster()
      seed_emo_contact()
      seed_resident_district()

      assert {:ok, pdf} = PerformanceReportPdf.generate_report(@building_code, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "generates a PDF from an empty database (sample-data fallbacks, nil coercion)" do
      assert {:ok, pdf} = PerformanceReportPdf.generate_report("00000", @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end
end
