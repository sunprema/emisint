defmodule Emisint.Reports.School.CustomSchoolReportPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Reports.School.{
    CustomSchoolReportPdf,
    ReportSectionRegistry,
    ReportTemplateRegistry,
    SchoolReportData
  }

  @year "24 - 25 School Year"

  test "registries expose stable keys and validate input" do
    assert Enum.map(ReportTemplateRegistry.list(), & &1.key) == [
             :compact_portrait,
             :detailed_landscape
           ]

    assert ReportTemplateRegistry.default_key() == :compact_portrait
    assert {:ok, %{key: :detailed_landscape}} = ReportTemplateRegistry.fetch("detailed_landscape")
    assert {:error, :unknown_template} = ReportTemplateRegistry.fetch("not-a-template")

    assert ReportSectionRegistry.default_keys() == [
             :school_profile,
             :mission_statement,
             :charter_contract,
             :board_roster,
             :performance_overview,
             :enrollment_demographics,
             :resident_districts,
             :sss_peer_roster,
             :accountability,
             :academic_trends,
             :proficiency_trends,
             :academic_compliance_appendix,
             :financial_testing_appendix
           ]

    assert {:ok, [:school_profile, :accountability]} =
             ReportSectionRegistry.normalize("accountability,school_profile")

    assert {:error, :unknown_section} = ReportSectionRegistry.normalize("sample_data")
  end

  test "both presets render the complete catalog with honest empty-data states" do
    payload = SchoolReportData.load("00000", @year)

    assert payload.school.name == "00000"
    assert payload.resident_districts == []
    assert payload.board_members == []
    assert payload.contract.term_length == nil

    for key <- [:compact_portrait, :detailed_landscape] do
      assert {:ok, pdf} = CustomSchoolReportPdf.generate_report("00000", @year, key)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end
  end

  test "both presets render selected available and unavailable sections" do
    sections = [:mission_statement, :accountability, :financial_testing_appendix]

    for key <- [:compact_portrait, :detailed_landscape] do
      assert {:ok, pdf} =
               CustomSchoolReportPdf.generate_report("00000", @year, key, sections: sections)

      assert String.starts_with?(pdf, "%PDF")
    end
  end

  test "rejects unknown presets and sections without compiling" do
    assert {:error, :unknown_template} =
             CustomSchoolReportPdf.generate_report("00000", @year, "unknown")

    assert {:error, :unknown_section} =
             CustomSchoolReportPdf.generate_report("00000", @year, :compact_portrait,
               sections: ["unknown"]
             )
  end
end
