defmodule Emisint.Improvement.Seeds.DunseithElementary do
  @moduledoc """
  Dunseith Elementary School (Dunseith Public School District): a building of the ND First participant
  `Emisint.Improvement.Seeds.Dunseith`. It holds only the building's
  annual Proficient-or-Advanced targets from `North Dakota - ND First
  Schools.pdf` (p.12); the workbook goals, seasonal ratings and payment
  belong to the participant record. See `Emisint.Improvement.Seeds.Participant`.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.Participant

  @pdf_ref "North Dakota - ND First Schools.pdf pp.12-13"

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant (district) this building belongs to."
  def participant, do: Seeds.Dunseith

  def school do
    %{
      name: "Dunseith Elementary School",
      short_name: "Dunseith Elementary",
      slug: "dunseith-elementary",
      state: "ND",
      state_entity_id: "4000119681",
      district_name: "Dunseith Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "Annual targets from North Dakota - ND First Schools.pdf pp.12-13 (Dunseith Elementary School). No workbook goals, seasonal ratings or payment terms: those belong to Dunseith Public School District."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The plan's long-term academic goals run 2025-2026 through 2030-2031 (pp.12-13)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.12)."
  def annual_assessment_goals do
    Participant.annual_goals(
      [
        {"2025-2026", "0.26", "0.24"},
        {"2026-2027", "0.3", "0.28"},
        {"2027-2028", "0.35", "0.33"},
        {"2028-2029", "0.39", "0.37"},
        {"2029-2030", "0.43", "0.42"},
        {"2030-2031", "0.48", "0.46"}
      ],
      "North Dakota - ND First Schools.pdf p.12 (Dunseith Elementary School, Annual Proficiency Targets, 2025-2026 through 2030-2031)"
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
        location: "North Dakota - ND First Schools.pdf p.12",
        excerpt:
          "“The annual targets below assume the same six-year sequence as the previous schools.”"
      },
      annual_note:
        "The plan (p.12) says its annual targets “assume the same six-year sequence as the previous schools” (2025-2026 through 2030-2031). Each target is compared only with this building's result for the same year (year mapping confirmed by the user); there are no matching results in the imported data for those years yet.",
      report_notes: [
        "Scope. This building record holds only the continuous improvement plan's annual targets for Dunseith Elementary School (North Dakota - ND First Schools.pdf pp.12-13) and this building's own published results. The ND First workbook goals, seasonal ratings and payment belong to the participant record (Dunseith Public School District) and are not copied here.",
        "Annual targets. North Dakota - ND First Schools.pdf p.12 lists Dunseith Elementary School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and math, including the alternate assessment).",
        "Other plan targets. Measure 2 (writing improvement, “20% improvement”, p.12) is shown as written under “Other plan targets”, marked unresolved: the plan says its baseline, rubric scale and meaning of 20% are unspecified."
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
        id: "writing",
        title: "Measure 2: Writing Improvement",
        measure:
          "Student writing performance measured using the adopted rubric. Overall goal: “Improve students’ writing skills by 20% using the school’s adopted writing rubric during the 2025–2026 improvement-plan period.”",
        baseline: nil,
        long_term: nil,
        status_note:
          "Definition open: “The strategy map does not specify the baseline, rubric scoring scale, or whether “20%” means relative improvement or a percentage-point increase.” (p.12)",
        results_note:
          "Actual results unavailable: writing-rubric results are not in the imported datasets. No comparison is made.",
        location: "North Dakota - ND First Schools.pdf p.12",
        status: :unresolved,
        targets: [{"Target", "20% improvement"}]
      }
    ]
  end
end
