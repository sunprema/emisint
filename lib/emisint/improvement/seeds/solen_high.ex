defmodule Emisint.Improvement.Seeds.SolenHigh do
  @moduledoc """
  Solen High School (Solen Public School District): the building subtab of
  the ND First participant `Emisint.Improvement.Seeds.CannonBall` (user
  decision of November 12, 2026). It is not a ninth participant: it has no
  workbook sheet, seasonal ratings, payment or portfolio row.

  **InstitutionID 4300380363**, verified against the imported ND Insights
  files: "Solen High School" in the 2021-22, 2022-23 and 2023-24 Assessment
  Performance files, which publish **Grade 10** and All Grades only (the
  2024-25 file and the Growth Rate files publish no Solen High School rows).

  The "Solen Goals" grade-10 metrics (G1-M3, G1-M6, G2-M3, G2-M6) stay on
  Cannon Ball's plan, so ratings and payment aren't duplicated; this
  building's dashboard compares them with its own Grade 10 rows
  (`comparison/0` `workbook_from`, `Dashboard.comparison_metrics/3`). The
  continuous improvement plan (pp.4-6) sets no annual targets for Solen High
  School, so none are recorded.
  """

  alias Emisint.Improvement.Seeds
  alias Emisint.Improvement.Seeds.{CannonBall, Participant}

  @doc "No workbook sheet: the workbook goals belong to the participant."
  def sheet, do: nil

  def workbook_last_updated, do: nil

  @doc "The ND First participant this building belongs to."
  def participant, do: CannonBall

  def school do
    %{
      name: "Solen High School",
      short_name: "Solen High",
      slug: "solen-high-school",
      state: "ND",
      state_entity_id: "4300380363",
      district_name: "Solen Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    Participant.building_plan(
      "No annual targets: the continuous improvement plan (North Dakota - ND First Schools.pdf pp.4-6) sets none for Solen High School. Its grade-10 workbook goals (“Solen Goals” G1-M3, G1-M6, G2-M3, G2-M6) are recorded on Cannon Ball Elementary School, the participant record, and compared here with this building's Grade 10 results."
    )
  end

  defdelegate reporting_periods, to: Seeds.FortYates

  @doc "The participant's plan runs 2025-2026 through 2030-2031 (p.4)."
  def plan_start_year, do: "2025-2026"

  def goals, do: []
  def metrics, do: []
  def workbook_ratings, do: []
  def annual_assessment_goals, do: []

  @grades %{grades: ["10"], group: "grade 10"}

  def comparison do
    m = CannonBall.grade_10_metrics()

    %{
      plan_start_year: plan_start_year(),
      workbook_from: CannonBall,
      workbook: [
        {"G1-M3", m["G1-M3"], :achievement, "Reading", :proficient_or_advanced,
         "Grade 10 Reading Proficient or Advanced", @grades},
        {"G1-M6", m["G1-M6"], :achievement, "Reading", "Novice", "Grade 10 Reading Novice",
         @grades},
        {"G2-M6", m["G2-M6"], :achievement, "Math", "Novice", "Grade 10 Math Novice", @grades},
        {"G2-M3", m["G2-M3"], :growth, "Math", :meets_or_exceeds,
         "Grade 10 Math Meets or Exceeds growth expectations", @grades}
      ],
      confirmed: %{assessment_type: "Comp"},
      confirmations: Map.new(~w(G1-M3 G1-M6 G2-M6), &{&1, CannonBall.achievement_confirmation()}),
      provisional: %{"G2-M3" => CannonBall.growth_provisional()},
      assumptions: %{},
      grade_reference: nil,
      matching:
        "This building's Grade 10 rows (all students, Combined assessment) are compared with the “Solen Goals” grade-10 goals recorded on Cannon Ball Elementary School: G1-M3 (Reading, “demonstrate proficiency” = Proficient or Advanced), G1-M6 (Reading Novice) and G2-M6 (Goal 2, “Mathematics Growth”: Math Novice), confirmed by the user (November 12, 2026). Grade 10 is a single grade, so its published row is the goal's own result. G2-M3 (grade 10 math “expected annual growth”, provisionally Meets or Exceeds) has no published counterpart: Insights publishes no growth rows for Solen High School. The All Grades row (the same students: only grade 10 is published) isn't compared, so each comparison is labeled Grade 10. Cannon Ball Elementary's and the Solen district's results are never used here.",
      assumptions_text:
        "No assumptions are applied for Solen High School. Confirmed by the user (November 12, 2026): “demonstrate proficiency” means Proficient or Advanced, and the achievement goals count the Combined assessment.",
      assumptions_short:
        "Solen High: grade-10 goals compared with this building's Grade 10 results (Combined assessment and Proficient or Advanced confirmed).",
      section_notes: %{
        achievement:
          "Solen High School's own results (InstitutionID 4300380363); only Grade 10 is published. The Grade 10 row is compared with the grade-10 goals recorded on Cannon Ball Elementary School (G1-M3 Proficient or Advanced, G1-M6 Reading Novice, G2-M6 Math Novice). The plan sets no annual targets for this building.",
        growth:
          "Insights publishes no growth rows for Solen High School, so G2-M3 (grade 10 math growth) can't be compared.",
        engagement: "The “Solen Goals” sheet has no Engagement Survey metric."
      },
      annual_note:
        "The continuous improvement plan (pp.4-6) sets no annual targets for Solen High School.",
      annual_years: nil,
      report_notes: [
        "Scope. Solen High School is the building of the Cannon Ball participant (user decision, November 12, 2026). This report shows its own published results (InstitutionID 4300380363; Grade 10). The ND First workbook goals, seasonal ratings and payment are written for the participant (Cannon Ball Elementary School); its grade-10 goals (G1-M3, G1-M6, G2-M3, G2-M6) are compared here with this building's Grade 10 results.",
        "Not compared. G2-M3 (grade 10 math growth): no growth rows are published for this building. No annual targets are set for it in the plan."
      ]
    }
  end
end
