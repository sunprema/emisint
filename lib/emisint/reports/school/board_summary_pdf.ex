defmodule Emisint.Reports.School.BoardSummaryPdf do
  @moduledoc """
  Generates the one-page "Board Summary" report — Phase 1.1's second
  distinct visual preset in `PLAN_betterPDF.md` (compact single-page,
  US-Letter portrait, vs. the Performance Report's 8-page landscape style),
  composed from the shared `priv/typst/shared/design_system.typ` components.

  Deliberately REAL-data-only: School Index, Assessment Participation,
  current-year mean SGP, current-year weighted state-assessment proficiency,
  enrollment, resident districts, and the academic-achievement/growth halves
  of the performance overview. No board roster, contract term, or mission
  text — those remain SAMPLE placeholders with no backing resource (see
  `PerformanceReportPdf`'s moduledoc) and are intentionally left off this
  report so it can be shown to a client as complete, not partly
  illustrative.

  Shares its data loaders with `PerformanceReportPdf` via
  `Emisint.Reports.School.SchoolSnapshot`.
  """

  @template_path "priv/typst/school/board_summary.typ"

  alias Emisint.Reports.School.SchoolSnapshot

  @doc """
  Generates the Board Summary PDF for the given building code and school
  year (e.g. "24 - 25 School Year").

  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  def generate_report(building_code, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(building_code, year)

    config =
      Imprintor.Config.new(template, data,
        root_directory: Application.app_dir(:emisint, "priv/typst")
      )

    Imprintor.compile_to_pdf(config)
  end

  defp build_data(building_code, year) do
    %{
      entity: entity,
      enrollment: enrollment,
      resident_districts: resident_districts,
      school_index: school_index,
      sgp: sgp,
      proficiency: proficiency,
      performance_overview: performance_overview
    } = SchoolSnapshot.load(building_code, year)

    %{
      report_year_label: report_year_label(year),
      school_year: year,
      generated_on: Date.utc_today() |> Calendar.strftime("%B %d, %Y"),
      org_name: presence(entity.chartering_agency_name, "Authorizer Not on File"),
      school: %{name: entity.name},
      school_index: %{value: school_index.overall},
      participation: %{
        value: school_index.subject_participation,
        # 95% is the actual federal ESSA minimum participation requirement —
        # a fixed policy constant, not a per-school data point.
        minimum_required: 95.0,
        support_category: school_index.support_category_name
      },
      enrollment: %{total: enrollment.total},
      resident_districts: resident_districts,
      proficiency: proficiency,
      sgp: sgp,
      performance_overview: performance_overview
    }
  end

  defp report_year_label(year) do
    case String.split(year, " - ") do
      [y1, _y2 | _] ->
        y1 = String.trim(y1)
        y2_full = String.pad_leading(to_string(String.to_integer(y1) + 1), 2, "0")
        "20#{y1}-#{y2_full}"

      _ ->
        year
    end
  rescue
    _ -> year
  end

  defp presence(nil, fallback), do: fallback
  defp presence("", fallback), do: fallback
  defp presence(value, _fallback), do: value
end
