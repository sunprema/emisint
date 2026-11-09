defmodule Emisint.Improvement.Seeds.MandareeElementary do
  @moduledoc """
  Mandaree Elementary School (Mandaree Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Mandaree`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (p.19); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.19-20"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Mandaree

  def school do
    %{
      name: "Mandaree Elementary School",
      short_name: "Mandaree Elementary",
      slug: "mandaree-elementary",
      state: "ND",
      state_entity_id: "2703654591",
      district_name: "Mandaree Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.19-20 (Mandaree Elementary School). No workbook goals, seasonal ratings or payment terms: those belong to Mandaree Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.19-20)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.19)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.2", "0.11"},
        {"2026-2027", "0.25", "0.16"},
        {"2027-2028", "0.3", "0.22"},
        {"2028-2029", "0.34", "0.27"},
        {"2029-2030", "0.39", "0.32"},
        {"2030-2031", "0.44", "0.37"}
      ],
      "North Dakota - ND First Schools.pdf p.19 (Mandaree Elementary School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
    )
  end

  def comparison do
    Participant.building_comparison(%{
      participant: participant(),
      pdf_ref: @pdf_ref,
      annual_years: %{
        status: :stated,
        location: "North Dakota - ND First Schools.pdf p.19",
        excerpt:
          "“Annual Proficiency Targets”, listed by year: “2025–2026: ELA 20%; mathematics 11%.” through “2030–2031: ELA 44%; mathematics 37%.”"
      },
      annual_note:
        "The plan (p.19) lists annual targets for 2025-2026 through 2030-2031. Each target is compared only with this building's result for the same year; there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Mandaree Elementary School (North Dakota - ND First Schools.pdf pp.19-20) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Mandaree Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf p.19 lists Mandaree Elementary School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
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
        id: "kindergarten-readiness",
        title: "Kindergarten Readiness",
        measure:
          "Goal: “Foster readiness and support students’ transition into kindergarten.” Measures: Kindergarten Readiness Test (KRT) and placement/transition data.",
        baseline: nil,
        long_term: nil,
        status_note: "The plan lists measures but no numeric target (pp.19-20).",
        results_note:
          "Actual results unavailable: kindergarten readiness results are not in the imported datasets.",
        location: "North Dakota - ND First Schools.pdf pp.19-20",
        status: :no_numeric_target,
        targets: []
      }
    ]
  end
end
