defmodule Emisint.Improvement.Seeds.MandareeHigh do
  @moduledoc """
  Mandaree High School (Mandaree Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Mandaree`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (pp.20-21); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.20-21"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Mandaree

  def school do
    %{
      name: "Mandaree High School",
      short_name: "Mandaree High",
      slug: "mandaree-high-school",
      state: "ND",
      state_entity_id: "2703654593",
      district_name: "Mandaree Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.20-21 (Mandaree High School). No workbook goals, seasonal ratings or payment terms: those belong to Mandaree Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.20-21)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (pp.20-21)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.35", "0.16"},
        {"2026-2027", "0.39", "0.21"},
        {"2027-2028", "0.43", "0.25"},
        {"2028-2029", "0.47", "0.3"},
        {"2029-2030", "0.51", "0.35"},
        {"2030-2031", "0.54", "0.4"}
      ],
      "North Dakota - ND First Schools.pdf pp.20-21 (Mandaree High School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
    )
  end

  def comparison do
    Participant.building_comparison(%{
      participant: participant(),
      pdf_ref: @pdf_ref,
      annual_years: %{
        status: :stated,
        location: "North Dakota - ND First Schools.pdf pp.20-21",
        excerpt:
          "“Annual Proficiency Targets”, listed by year: “2025–2026: ELA 35%; mathematics 16%.” through “2030–2031: ELA 54%; mathematics 40%.”"
      },
      annual_note:
        "The plan (pp.20-21) lists annual targets for 2025-2026 through 2030-2031. Each target is compared only with this building's result for the same year; there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Mandaree High School (North Dakota - ND First Schools.pdf pp.20-21) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Mandaree Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf pp.20-21 lists Mandaree High School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
        "Other plan targets. The graduation targets in the same section are shown as written under “Other plan targets”, with no comparison: graduation rates are not in the imported ND Insights datasets.",
        "District name: the plan's Mandaree sections don't name the district; “Mandaree Public School District” is the name ND Insights publishes for this building's district (Engagement Survey files)."
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
          "Years as listed in the source (“2025–2026: Four-year 71%; five-year 73%; six-year 66%.” through “2030–2031: Four-year 90%; five-year 92%; six-year 93%.”, p.21).",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.21",
        status: :stated,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["71%", "75%", "78%", "82%", "86%", "90%"])
      },
      %{
        id: "graduation-five-year",
        title: "Measure 2: Graduation — Five-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within five years.",
        baseline: nil,
        long_term: "Reach 92% by 2030–2031.",
        status_note: "Years as listed in the source (p.21).",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.21",
        status: :stated,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["73%", "77%", "81%", "84%", "88%", "92%"])
      },
      %{
        id: "graduation-six-year",
        title: "Measure 2: Graduation — Six-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within six years.",
        baseline: nil,
        long_term: "Reach 93% by 2030–2031.",
        status_note: "Years as listed in the source (p.21).",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.21",
        status: :stated,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["66%", "72%", "77%", "82%", "88%", "93%"])
      }
    ]
  end
end
