defmodule Emisint.Reports.School.SchoolReportData do
  @moduledoc """
  Builds the normalized, real-data-only payload shared by every selectable
  school-report presentation preset.

  Missing imported values remain `nil` or empty collections so templates can
  render honest unavailable states. This module never manufactures sample data.
  """

  alias Emisint.Reports.School.SchoolSnapshot

  def load(building_code, year) do
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
      school: %{
        name: presence(entity.name, "School Not on File"),
        street: entity.street,
        city: entity.city,
        state: entity.state,
        zip: entity.zip,
        grades_served: entity.actual_grades,
        contract_grades: entity.authorized_grades,
        year_opened: entity.year_opened,
        isd_name: entity.isd_name,
        mission: nil
      },
      contract: %{term_length: nil, expiration_year: nil, esp_name: nil},
      board_members: [],
      school_index: %{value: school_index.overall},
      participation: %{
        value: school_index.subject_participation,
        minimum_required: 95.0,
        support_category: school_index.support_category_name
      },
      enrollment: %{
        total: enrollment.total,
        subgroups: [
          %{label: "Economically Disadvantaged", pct: enrollment.econ_pct},
          %{label: "Special Education", pct: enrollment.sped_pct},
          %{label: "English Language Learners", pct: enrollment.ell_pct}
        ],
        trend: [],
        by_grade: nil
      },
      resident_districts: resident_districts,
      peer_roster: [],
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
