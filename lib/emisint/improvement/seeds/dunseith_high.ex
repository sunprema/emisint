defmodule Emisint.Improvement.Seeds.DunseithHigh do
  @moduledoc """
  Dunseith High School (Dunseith Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Dunseith`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (p.14); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.13-14"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Dunseith

  def school do
    %{
      name: "Dunseith High School",
      short_name: "Dunseith High",
      slug: "dunseith-high-school",
      state: "ND",
      state_entity_id: "4000119663",
      district_name: "Dunseith Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.13-14 (Dunseith High School). No workbook goals, seasonal ratings or payment terms: those belong to Dunseith Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.13-14)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.14)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.17", "0.25"},
        {"2026-2027", "0.22", "0.3"},
        {"2027-2028", "0.27", "0.34"},
        {"2028-2029", "0.32", "0.38"},
        {"2029-2030", "0.37", "0.43"},
        {"2030-2031", "0.41", "0.47"}
      ],
      "North Dakota - ND First Schools.pdf p.14 (Dunseith High School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
    )
  end

  def comparison do
    Participant.building_comparison(%{
      participant: participant(),
      pdf_ref: @pdf_ref,
      annual_years: %{
        status: :confirmed,
        confirmation:
          "Confirmed by the user (recorded in PLAN_nd_first.md, November 8, 2026): the six targets map to 2025–2026 through 2030–2031, in order.",
        location: "North Dakota - ND First Schools.pdf p.13",
        excerpt:
          "“The annual targets below assume the same six-year sequence as the previous schools.”"
      },
      annual_note:
        "The plan (p.13) says its annual targets “assume the same six-year sequence as the previous schools” (2025-2026 through 2030-2031). Each target is compared only with this building's result for the same year (year mapping confirmed by the user); there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Dunseith High School (North Dakota - ND First Schools.pdf pp.13-14) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Dunseith Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf p.14 lists Dunseith High School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
        "Other plan targets. The graduation targets in the same section are shown as written under “Other plan targets”, with no comparison: graduation rates are not in the imported ND Insights datasets."
      ]
    })
  end

  @doc """
  Other continuous-improvement-plan targets, shown as written and never
  compared (`Emisint.Improvement.PlanTargets`).
  """
  def plan_targets do
    [
      %{
        id: "graduation-four-year",
        title: "Measure 2: Graduation — Four-Year Adjusted Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within four years.",
        baseline: nil,
        long_term: "Reach 90% by 2030–2031.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.13): “The annual targets below assume the same six-year sequence as the previous schools.”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.14",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["80%", "82%", "84%", "86%", "88%", "90%"])
      },
      %{
        id: "graduation-five-year",
        title: "Measure 2: Graduation — Five-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within five years.",
        baseline: nil,
        long_term: "Reach 92% by 2030–2031.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.13): “The annual targets below assume the same six-year sequence as the previous schools.”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.14",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["77%", "80%", "83%", "86%", "89%", "92%"])
      },
      %{
        id: "graduation-six-year",
        title: "Measure 2: Graduation — Six-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within six years.",
        baseline: nil,
        long_term: "Reach 93% by 2030–2031.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.13): “The annual targets below assume the same six-year sequence as the previous schools.”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.14",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["87%", "88%", "89%", "91%", "92%", "93%"])
      },
      %{
        id: "english-learner",
        title: "Measure 3: English Learner Language Proficiency",
        measure:
          "English Learner Proficiency Growth, as described in the report card explanation.",
        baseline: nil,
        long_term: "Reach the displayed target of 72% by 2030–2031.",
        status_note:
          "Definition open: “The supplied explanation describes growth toward language proficiency but does not define the exact calculation. Before configuring this measure in the APM, confirm whether the graph measures students meeting their growth targets or students attaining proficiency.” (p.15) Its years follow the sequence confirmed by the user (2025–2026 through 2030–2031).",
        results_note:
          "Actual results unavailable: English Learner results are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.15",
        status: :unresolved,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["12%", "24%", "36%", "48%", "60%", "72%"])
      },
      %{
        id: "ccmr",
        title: "Measure 4: College, Career, and Military Readiness",
        measure: "Progress measures: Choice Ready Report; post-graduation pathways.",
        baseline: nil,
        long_term: nil,
        status_note:
          "“The strategy map identifies these measures but does not specify a numerical readiness target.” (p.15)",
        results_note:
          "Actual results unavailable: readiness results are not in the imported datasets.",
        location: "North Dakota - ND First Schools.pdf p.15",
        status: :no_numeric_target,
        targets: []
      }
    ]
  end
end
