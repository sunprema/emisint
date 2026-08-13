defmodule Emisint.Reports.School.SssComparisonPdfTest do
  use Emisint.DataCase, async: false

  alias Emisint.Assessments.{
    MdeEntityMaster,
    MdeSchoolVsLeaSnapshot,
    MdeSssComparisonGroup,
    MdeSssComparisonGroupMember,
    MdeSssSchool
  }

  alias Emisint.Reports.School.SssComparisonPdf

  @anchor_code "12345"
  @peer_code "54321"
  @year "24 - 25 School Year"

  defp subject_row(subject, pct), do: %{"subject" => subject, "school_pct" => pct}

  defp seed_entity do
    Ash.create!(
      MdeEntityMaster,
      %{
        entity_code: @anchor_code,
        entity_official_name: "Achieve Charter Academy",
        entity_status: "Open-Active"
      },
      authorize?: false
    )
  end

  defp seed_snapshot(building_code, name) do
    Ash.create!(
      MdeSchoolVsLeaSnapshot,
      %{
        building_code: building_code,
        school_year: @year,
        school_name: name,
        subject_comparison: [
          subject_row("ELA", 60.0),
          subject_row("Mathematics", 55.0),
          subject_row("Science", 50.0),
          subject_row("Social Studies", 52.0)
        ]
      },
      authorize?: false
    )
  end

  defp seed_group do
    anchor =
      Ash.create!(
        MdeSssSchool,
        %{
          lookup_key: "anchor-#{@anchor_code}",
          school_code: @anchor_code,
          school_name: "Achieve Charter Academy"
        },
        authorize?: false
      )

    peer =
      Ash.create!(
        MdeSssSchool,
        %{lookup_key: "peer-#{@peer_code}", school_code: @peer_code, school_name: "Peer Academy"},
        authorize?: false
      )

    group =
      Ash.create!(
        MdeSssComparisonGroup,
        %{comparison_code: @anchor_code, anchor_school_id: anchor.id},
        authorize?: false
      )

    Ash.create!(
      MdeSssComparisonGroupMember,
      %{comparison_group_id: group.id, school_id: peer.id},
      authorize?: false
    )
  end

  describe "generate_report/2" do
    test "generates a PDF when real data is present" do
      seed_entity()
      seed_snapshot(@anchor_code, "Achieve Charter Academy")
      seed_snapshot(@peer_code, "Peer Academy")
      seed_group()

      assert {:ok, pdf} = SssComparisonPdf.generate_report(@anchor_code, @year)
      assert is_binary(pdf)
      assert String.starts_with?(pdf, "%PDF")
    end

    test "raises when no SSS comparison group exists for the school code" do
      seed_entity()
      seed_snapshot(@anchor_code, "Achieve Charter Academy")

      assert_raise RuntimeError, ~r/No SSS comparison group found/, fn ->
        SssComparisonPdf.generate_report(@anchor_code, @year)
      end
    end
  end
end
