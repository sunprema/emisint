defmodule Emisint.Improvement.Seeds.DraytonHigh do
  @moduledoc """
  Drayton High School (Drayton Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Drayton`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (pp.9-10); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.9-10"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Drayton

  def school do
    %{
      name: "Drayton High School",
      short_name: "Drayton High",
      slug: "drayton-high-school",
      state: "ND",
      state_entity_id: "3401919283",
      district_name: "Drayton Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.9-10 (Drayton High School). No workbook goals, seasonal ratings or payment terms: those belong to Drayton Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.9-10)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (pp.9-10)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.2", "0.19"},
        {"2026-2027", "0.25", "0.24"},
        {"2027-2028", "0.3", "0.29"},
        {"2028-2029", "0.34", "0.33"},
        {"2029-2030", "0.39", "0.38"},
        {"2030-2031", "0.44", "0.43"}
      ],
      "North Dakota - ND First Schools.pdf pp.9-10 (Drayton High School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
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
        location: "North Dakota - ND First Schools.pdf p.9",
        excerpt:
          "“The annual targets below use the six values provided in chronological order, beginning with 2025–2026.”"
      },
      annual_note:
        "The plan (pp.9-10) says its annual targets “use the six values provided in chronological order, beginning with 2025–2026”. Each target is compared only with this building's result for the same year (year mapping confirmed by the user); there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Drayton High School (North Dakota - ND First Schools.pdf pp.9-10) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Drayton Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf pp.9-10 lists Drayton High School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
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
        long_term: "Reach a 90% four-year graduation rate by 2030–2031.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.9): “The annual targets below use the six values provided in chronological order, beginning with 2025–2026.”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.10",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["82%", "83%", "85%", "87%", "88%", "90%"])
      },
      %{
        id: "graduation-six-year",
        title: "Measure 2: Graduation — Six-Year Extended Cohort Graduation Rate",
        measure: "Percentage of students in the adjusted cohort who graduate within six years.",
        baseline: nil,
        long_term: "Reach a 93% six-year graduation rate by 2030–2031.",
        status_note:
          "Years confirmed by the user as 2025–2026 through 2030–2031 (recorded November 8, 2026); source wording (North Dakota - ND First Schools.pdf p.9): “The annual targets below use the six values provided in chronological order, beginning with 2025–2026.”",
        results_note:
          "Actual results unavailable: graduation rates are not in the imported ND Insights datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.10",
        status: :confirmed,
        targets:
          Emisint.Improvement.PlanTargets.six_years(["80%", "82%", "85%", "88%", "90%", "93%"])
      },
      %{
        id: "engagement-survey",
        title: "Related Learning Engagement Goal",
        measure: "Student engagement survey.",
        baseline: nil,
        long_term: nil,
        status_note:
          "Definition open: “The strategy map does not specify the survey response category or calculation used for this target.” (p.11)",
        results_note:
          "Not compared: the survey category and calculation are not specified. Engagement Survey results are shown under Official state results.",
        location: "North Dakota - ND First Schools.pdf p.11",
        status: :unresolved,
        targets: [{"Target", "75%"}]
      }
    ]
  end
end
