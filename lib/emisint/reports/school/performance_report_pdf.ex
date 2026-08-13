defmodule Emisint.Reports.School.PerformanceReportPdf do
  @moduledoc """
  Generates the 8-page landscape "School Performance Report" described in
  `PLAN_betterPDF.md`'s target design section.

  Data honesty note: every field below is either pulled from a real MDE
  import (marked REAL) or is a placeholder because no backing resource
  exists yet (marked SAMPLE — see `PLAN_betterPDF.md` data-gap list). SAMPLE
  values are isolated in the `sample_*` functions at the bottom of this
  module so they're easy to find and swap out once the real data sources
  (board members, charter contract terms, compliance/financial ratings,
  mission statement, campus photos, attendance rate, SSS peer roster with
  distances, and multi-year history) are built.

  The current-year REAL snapshot (entity identity, enrollment, resident
  districts, School Index, SGP, weighted proficiency) is loaded via
  `Emisint.Reports.School.SchoolSnapshot`, shared with `BoardSummaryPdf` —
  see that module's moduledoc for why this was extracted.
  """

  @template_path "priv/typst/school/performance_report.typ"

  require Ash.Query

  alias Emisint.Assessments.{MdeEmoContact, MdeSssComparisonGroup}
  alias Emisint.Reports.School.SchoolSnapshot

  @doc """
  Generates the full performance report PDF for the given building code and
  school year (enrollment/SGP/state-assessment format, e.g. "24 - 25 School
  Year").

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

  # --- Data assembly ---------------------------------------------------------

  defp build_data(building_code, year) do
    %{
      entity: entity,
      enrollment: enrollment,
      resident_districts: resident_districts,
      school_index: school_index,
      sgp: sgp,
      proficiency: proficiency,
      performance_overview: real_overview
    } = SchoolSnapshot.load(building_code, year)

    peer_roster = load_peer_roster(building_code)
    emo = load_emo_contact(entity.district_code)

    %{
      report_year_label: report_year_label(year),
      school_year: year,
      generated_on: Date.utc_today() |> Calendar.strftime("%B %d, %Y"),
      # REAL — the school's actual chartering agency/authorizer, per school.
      # (This report used to hardcode "Grand Valley State University" for
      # every school — fixed to read the real authorizer from MDE data.)
      org_name: presence(entity.chartering_agency_name, "Authorizer Not on File"),
      school: %{
        name: entity.name,
        street: entity.street,
        city: entity.city,
        state: entity.state,
        zip: entity.zip,
        grades_served: entity.actual_grades,
        contract_grades: entity.authorized_grades,
        year_opened: entity.year_opened,
        isd_name: entity.isd_name,
        # SAMPLE — no mission-statement field exists on any resource yet.
        mission: sample_mission()
      },
      contract: %{
        # SAMPLE — CharterContract resource doesn't exist yet (see plan notes).
        term_length: sample_contract_term(),
        expiration_year: sample_contract_expiration_year(),
        esp_name: emo.management_organization
      },
      # SAMPLE — no Board Member resource exists yet.
      board_members: sample_board_members(),
      # academic_achievement/academic_growth are REAL (from SchoolSnapshot);
      # compliance/financial ratings are SAMPLE — no backing resource exists.
      performance_overview:
        Map.merge(
          %{
            compliance_reporting: sample_compliance_rating(),
            financial_reporting: sample_financial_rating()
          },
          real_overview
        ),
      enrollment: %{
        total: enrollment.total,
        subgroups: [
          %{label: "Free & Reduced Lunch", pct: enrollment.econ_pct},
          %{label: "Special Education", pct: enrollment.sped_pct},
          %{label: "English Language Learners", pct: enrollment.ell_pct},
          # SAMPLE — attendance rate isn't tracked on any resource yet.
          %{label: "Attendance", pct: sample_attendance_pct()}
        ],
        # SAMPLE — only the current school year exists in mde_enrollment_results;
        # prior 4 years are placeholders, current year is REAL.
        trend: sample_enrollment_trend(enrollment.total, year),
        by_grade: sample_enrollment_by_grade(enrollment, year)
      },
      resident_districts: resident_districts,
      # REAL when this building has an imported SSS comparison group (e.g.
      # GVSU-authorized schools, via the "GVSU SSS - Consolidated.csv" import)
      # — falls back to SAMPLE for schools with no SSS group on file. MDE's
      # SSS source file has no inter-school-distance column at all, so
      # "distance" is always nil/unavailable for REAL peer rows (rendered as
      # "—"), never fabricated.
      peer_roster: peer_roster.rows,
      peer_roster_is_sample: peer_roster.source == :sample,
      school_index: %{
        value: school_index.overall,
        # SAMPLE — mde_index_thresholds has 0 rows in this environment.
        minimum_threshold: sample_index_threshold()
      },
      participation: %{
        value: school_index.subject_participation,
        # 95% is the actual federal ESSA minimum participation requirement —
        # a fixed policy constant, not a per-school data point.
        minimum_required: 95.0,
        support_category: school_index.support_category_name
      },
      # SAMPLE — no multi-year peer-comparison exists; only a single current
      # school year of data exists in this environment at all.
      achievement_trend: sample_achievement_trend(),
      growth_trend: sample_growth_trend(sgp),
      # REAL — current-year mean SGP (1-99 scale), shown alongside the sample
      # growth_trend chart since the two aren't on comparable scales.
      current_sgp: %{ela: sgp.ela, math: sgp.math},
      proficiency_trend: sample_proficiency_trend(proficiency)
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

  # --- REAL data loaders (not part of the shared SchoolSnapshot) --------------

  defp load_emo_contact(nil), do: %{management_organization: ""}

  defp load_emo_contact(district_code) do
    MdeEmoContact
    |> Ash.Query.filter(district_code == ^district_code)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> %{management_organization: ""}
      rec -> %{management_organization: rec.management_organization || ""}
    end
  end

  # SSS comparison_code values in the MDE source file don't always match
  # building_code's zero-padding exactly — same tolerant-matching approach
  # used by the SSS Comparison tab in district_analysis_live.ex.
  defp sss_code_candidates(nil), do: []

  defp sss_code_candidates(code) do
    trimmed = to_string(code) |> String.trim()
    stripped = String.trim_leading(trimmed, "0")

    padded =
      if stripped == "" do
        nil
      else
        String.pad_leading(stripped, 5, "0")
      end

    [trimmed, stripped, padded] |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp pick_sss_group([], _anchor_code), do: nil

  defp pick_sss_group(groups, anchor_code) do
    anchor = to_string(anchor_code || "") |> String.trim()
    Enum.find(groups, &(&1.comparison_code == anchor)) || List.first(groups)
  end

  defp load_peer_roster(building_code) do
    codes = sss_code_candidates(building_code)

    groups =
      MdeSssComparisonGroup
      |> Ash.Query.filter(comparison_code in ^codes)
      |> Ash.Query.load(members: :school)
      |> Ash.read!(authorize?: false)

    case pick_sss_group(groups, building_code) do
      nil ->
        %{source: :sample, rows: sample_peer_roster()}

      group ->
        peers =
          group.members
          |> Enum.map(& &1.school)
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(&1.school_code in codes))
          |> Enum.uniq_by(& &1.lookup_key)
          # MDE's SSS source file has no distance column — always nil/"—",
          # never fabricated, unlike the SAMPLE fallback roster below.
          |> Enum.map(&%{name: &1.school_name, distance: nil})

        if peers == [] do
          %{source: :sample, rows: sample_peer_roster()}
        else
          %{source: :real, rows: peers}
        end
    end
  rescue
    _ -> %{source: :sample, rows: sample_peer_roster()}
  end

  defp presence(nil, fallback), do: fallback
  defp presence("", fallback), do: fallback
  defp presence(value, _fallback), do: value

  # --- SAMPLE data (no backing resource yet — see moduledoc) ------------------

  defp sample_mission do
    "Our mission is to provide a rigorous, joyful, and equitable education that " <>
      "prepares every scholar for success in college, career, and life."
  end

  defp sample_contract_term, do: "7 Years"
  defp sample_contract_expiration_year, do: "2030"

  defp sample_board_members do
    [
      %{name: "Dr. Angela Whitfield", role: "Board Chair", appointed: "2019", term_ends: "2027"},
      %{name: "Marcus Feldman", role: "Vice Chair", appointed: "2021", term_ends: "2026"},
      %{name: "Priya Raghavan", role: "Treasurer", appointed: "2020", term_ends: "2026"},
      %{name: "Dr. Samuel Ortiz", role: "Secretary", appointed: "2022", term_ends: "2028"},
      %{name: "Renee Castillo", role: "Member", appointed: "2023", term_ends: "2027"}
    ]
  end

  defp sample_compliance_rating, do: "exceeds"
  defp sample_financial_rating, do: "meets"
  defp sample_attendance_pct, do: 94.0
  defp sample_index_threshold, do: 35.3

  defp sample_enrollment_trend(current_total, year) do
    years = last_five_year_labels(year)
    base = (current_total || 700) * 1.0

    deltas = [-0.06, -0.03, -0.01, 0.02]

    historical =
      deltas
      |> Enum.map(fn d -> round(base * (1 + d)) end)

    (historical ++ [current_total])
    |> Enum.zip(years)
    |> Enum.map(fn {v, y} -> %{year: y, value: v} end)
  end

  defp sample_enrollment_by_grade(enrollment, year) do
    years = last_five_year_labels(year)
    grades = ["K", "1", "2", "3", "4", "5", "6", "7", "8"]

    rows =
      Enum.map(grades, fn grade ->
        current = Map.get(enrollment.by_grade, grade)

        history =
          Enum.map(0..3, fn i ->
            base = current || 80
            round(base * (1 - 0.02 * (4 - i)))
          end)

        %{grade: grade, values: history ++ [current]}
      end)

    totals =
      Enum.reduce(rows, List.duplicate(0, 5), fn %{values: values}, acc ->
        Enum.zip(acc, values)
        |> Enum.map(fn {a, v} -> a + (v || 0) end)
      end)

    %{years: years, rows: rows, totals: totals}
  end

  defp last_five_year_labels(year) do
    case String.split(year, " - ") do
      [y1, _y2 | _] ->
        start = String.to_integer(String.trim(y1))

        Enum.map((start - 4)..start, fn y ->
          "#{pad2(y)}-#{pad2(y + 1)}"
        end)

      _ ->
        ["20-21", "21-22", "22-23", "23-24", "24-25"]
    end
  rescue
    _ -> ["20-21", "21-22", "22-23", "23-24", "24-25"]
  end

  defp pad2(y), do: y |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

  defp sample_peer_roster do
    [
      %{name: "Global Heritage Academy", distance: 1.2},
      %{name: "Northview Charter School", distance: 1.8},
      %{name: "Riverside Preparatory Academy", distance: 2.1},
      %{name: "Lakeside Community Academy", distance: 2.4},
      %{name: "Countryside Charter School", distance: 3.0},
      %{name: "Heritage Grove Academy", distance: 3.6}
    ]
  end

  defp sample_achievement_trend do
    years = ["20-21", "21-22", "22-23", "23-24", "24-25"]
    values = [8, 8, 6, 9, 11]
    Enum.zip(years, values) |> Enum.map(fn {y, v} -> %{year: y, value: v} end)
  end

  # Fully SAMPLE — this chart plots "SGP delta vs. peer schools," which needs
  # a real peer SGP composite we don't have (SSS peer data is empty). Do not
  # splice the real single-year mean SGP in here — it's a raw 1-99 SGP score,
  # a different scale than this illustrative peer-delta series, and mixing
  # them produces a misleading discontinuity. The real current-year mean SGP
  # is surfaced separately, alongside this chart, via `current_sgp` below.
  defp sample_growth_trend(_sgp) do
    years = ["20-21", "21-22", "22-23", "23-24", "24-25"]
    ela_hist = [6.8, 5.8, 1.3, 5.8, 9.3]
    math_hist = [1.3, 0.6, -7.6, 4.6, 4.7]

    %{
      ela: Enum.zip(years, ela_hist) |> Enum.map(fn {y, v} -> %{year: y, value: v} end),
      math: Enum.zip(years, math_hist) |> Enum.map(fn {y, v} -> %{year: y, value: v} end)
    }
  end

  defp sample_proficiency_trend(proficiency) do
    years = ["20-21", "21-22", "22-23", "23-24", "24-25"]

    ela_school_hist = [74, 76, 71, 77]
    ela_state_hist = [61, 62, 60, 63]
    ela_peer_hist = [42, 44, 41, 45]

    math_school_hist = [55, 58, 52, 60]
    math_state_hist = [48, 49, 47, 50]
    math_peer_hist = [33, 35, 32, 36]

    %{
      ela: %{
        school: series(years, ela_school_hist, proficiency.school_ela),
        state: series(years, ela_state_hist, proficiency.state_ela),
        peer: series(years, ela_peer_hist, nil, fallback: 44)
      },
      math: %{
        school: series(years, math_school_hist, proficiency.school_math),
        state: series(years, math_state_hist, proficiency.state_math),
        peer: series(years, math_peer_hist, nil, fallback: 34)
      }
    }
  end

  defp series(years, hist, current, opts \\ []) do
    fallback = Keyword.get(opts, :fallback, List.last(hist))
    current = current || fallback

    Enum.zip(years, hist ++ [current])
    |> Enum.map(fn {y, v} -> %{year: y, value: v} end)
  end
end
