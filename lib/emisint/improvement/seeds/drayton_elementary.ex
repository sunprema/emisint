defmodule Emisint.Improvement.Seeds.DraytonElementary do
  @moduledoc """
  Drayton Elementary School (Drayton Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Drayton`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (p.7); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.7-9"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Drayton

  def school do
    %{
      name: "Drayton Elementary School",
      short_name: "Drayton Elementary",
      slug: "drayton-elementary",
      state: "ND",
      state_entity_id: "3401919281",
      district_name: "Drayton Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.7-9 (Drayton Elementary School). No workbook goals, seasonal ratings or payment terms: those belong to Drayton Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.7-9)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.7)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.21", "0.31"},
        {"2026-2027", "0.26", "0.36"},
        {"2027-2028", "0.31", "0.4"},
        {"2028-2029", "0.35", "0.44"},
        {"2029-2030", "0.4", "0.48"},
        {"2030-2031", "0.45", "0.52"}
      ],
      "North Dakota - ND First Schools.pdf p.7 (Drayton Elementary School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
    )
  end

  def comparison do
    Participant.building_comparison(%{
      participant: participant(),
      pdf_ref: @pdf_ref,
      annual_years: %{
        status: :stated,
        location: "North Dakota - ND First Schools.pdf p.7",
        excerpt:
          "“Annual Proficiency Targets – All Students”, listed by year: “2025–2026: ELA 21%; Mathematics 31%.” through “2030–2031: ELA 45%; Mathematics 52%.”"
      },
      annual_note:
        "The plan (p.7) lists “Annual Proficiency Targets – All Students” for 2025-2026 through 2030-2031 on the ND A+ Summative or the North Dakota Alternate Assessment (NDAA) for eligible students. Each target is compared only with this building's result for the same year; there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Drayton Elementary School (North Dakota - ND First Schools.pdf pp.7-9) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Drayton Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf p.7 lists Drayton Elementary School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
        "Other plan targets. The plan's “Related Learning Engagement Target” (75%, p.8) is shown as written under “Other plan targets”, marked unresolved: the plan says the survey category and calculation are not specified."
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
        id: "engagement-survey",
        title: "Related Learning Engagement Target",
        measure: "Student engagement survey goal.",
        baseline: nil,
        long_term: nil,
        status_note:
          "Definition open: “The strategy map lists a student engagement survey goal of 75%, without specifying the survey category or calculation.” (p.8)",
        results_note:
          "Not compared: the survey category and calculation are not specified. Engagement Survey results are shown under Official state results.",
        location: "North Dakota - ND First Schools.pdf p.8",
        status: :unresolved,
        targets: [{"Target", "75%"}]
      }
    ]
  end
end
