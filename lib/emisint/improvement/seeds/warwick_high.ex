defmodule Emisint.Improvement.Seeds.WarwickHigh do
  @moduledoc """
  Warwick High School (Warwick Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Warwick`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (p.30); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.29-31"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Warwick

  def school do
    %{
      name: "Warwick High School",
      short_name: "Warwick High",
      slug: "warwick-high-school",
      state: "ND",
      state_entity_id: "0302992193",
      district_name: "Warwick Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.29-31 (Warwick High School). No workbook goals, seasonal ratings or payment terms: those belong to Warwick Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.29-31)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.30)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.15", "0.31"},
        {"2026-2027", "0.2", "0.35"},
        {"2027-2028", "0.25", "0.39"},
        {"2028-2029", "0.3", "0.43"},
        {"2029-2030", "0.35", "0.48"},
        {"2030-2031", "0.4", "0.52"}
      ],
      "North Dakota - ND First Schools.pdf p.30 (Warwick High School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
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
        location: "North Dakota - ND First Schools.pdf p.30",
        excerpt: "“Using the assumed 2025–2026 through 2030–2031 sequence:”"
      },
      annual_note:
        "The plan (p.30) lists annual targets “using the assumed 2025–2026 through 2030–2031 sequence”. Each target is compared only with this building's result for the same year (year mapping confirmed by the user); there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Warwick High School (North Dakota - ND First Schools.pdf pp.29-31) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Warwick Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf p.30 lists Warwick High School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
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
        long_term: "Final Displayed Target: 90%.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.30): “Using the same assumed year sequence:”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf pp.30-31",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["71%", "75%", "78%", "82%", "86%", "90%"])
      },
      %{
        id: "graduation-five-year",
        title: "Measure 2: Graduation — Five-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within five years.",
        baseline: nil,
        long_term: "Final Displayed Target: 92%.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.30): “Using the same assumed year sequence:”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf pp.30-31",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["76%", "80%", "83%", "86%", "89%", "92%"])
      },
      %{
        id: "graduation-six-year",
        title: "Measure 2: Graduation — Six-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within six years.",
        baseline: nil,
        long_term: "Final Displayed Target: 93%.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.30): “Using the same assumed year sequence:”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf pp.30-31",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["92%", "92%", "92%", "93%", "93%", "93%"])
      }
    ]
  end
end
