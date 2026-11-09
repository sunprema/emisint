defmodule Emisint.Improvement.Seeds.Mandaree do
  @moduledoc """
  Mandaree Public School District definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Mandaree Goals". Every value
  cites its source cell.

  The sheet is written for the district (its goals name "Mandaree Public
  School(s)" and the district), so this is the participant record: workbook
  goals, metrics, seasonal ratings and the payment row ("Performance-Based
  Payment" row 8). The continuous improvement plan's annual
  targets are per building (Mandaree Elementary School pp.19-20, Mandaree High School pp.20-21) and are seeded on the
  building records (`buildings/0`); see `Emisint.Improvement.Seeds.Participant`.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Mandaree Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-20]

  alias Emisint.Improvement.Seeds

  def school do
    %{
      name: "Mandaree Public School District",
      short_name: "Mandaree",
      slug: "mandaree-public-school-district",
      state: "ND",
      state_entity_id: "27036",
      district_name: "Mandaree Public School District",
      grade_span: nil,
      active: true
    }
  end

  def goal_plan do
    %{
      program: "nd_first_mou",
      name: "ND First MOU Goals",
      definition_version: 1,
      progress_doc_url: nil,
      payment_cap: Decimal.new("70000"),
      systems_weight: Decimal.new("0.70"),
      outcomes_weight: Decimal.new("0.30"),
      max_rating: 3,
      source_note:
        "ND First School MOU Goal Overview.xlsx: 'Mandaree Goals' and 'Performance-Based Payment' (row 8). Progress-monitoring link listed as \"Mandaree Progess Monitoring\" (Mandaree Goals!B1), with no URL."
    }
  end

  @doc "The building records whose annual targets the continuous improvement plan lists, in PDF order."
  def buildings, do: [Seeds.MandareeElementary, Seeds.MandareeHigh]

  @doc "Source support for recording the workbook goals on the district record."
  def workbook_scope do
    %{
      status: :source_supported,
      excerpt:
        "“ELA Growth and Achievement: Mandaree Public Schools will improve ELA achievement for students in grades 3–10 …”; “The district will use ND A+ summative, interim, competency, and practice (formative) assessments …” (Mandaree Goals!B2). Grades 3–10 span Mandaree Elementary and Mandaree High School.",
      note: nil,
      evidence: []
    }
  end

  @doc """
  The first school year whose results fall inside the plan: the reporting
  periods start with Spr '26 (Mandaree Goals!E3).
  """
  def plan_start_year, do: "2025-2026"

  @doc """
  How the district's workbook goals are compared with the district's own
  published ND Insights results (`Emisint.Improvement.ResultGoals`). No
  workbook metric is matched; see `matching` for each reason.
  """
  def comparison do
    %{
      plan_start_year: plan_start_year(),
      workbook: [],
      assumptions: %{},
      grade_reference: nil,
      matching:
        "No workbook metric is matched to a published ND Insights measure. G1-M1 and G2-M1 count students in grades 3-10 meeting growth-or-proficiency criteria, which Insights doesn't publish. The other metrics are local measures (staff survey on a 0-5 Likert scale, pacing-guide quality, eleot walkthrough scores, leadership rubric). The state results on this page are the district's own published rows (InstitutionID 27036); building results are on each building's dashboard and are never averaged or combined here.",
      assumptions_text: "No assumptions are applied for Mandaree Public School District.",
      assumptions_short:
        "No assumptions for Mandaree: no workbook metric is compared, and annual targets are compared on each building's dashboard.",
      section_notes: %{
        achievement:
          "District results (InstitutionID 27036). No workbook goal is matched to them, and the plan sets annual targets per building, not for the district.",
        growth:
          "Mandaree's growth goals (G1-M1, G2-M1) count individual growth-or-proficiency criteria, which Insights doesn't publish, so growth results have no school goal.",
        engagement: "Mandaree's workbook has no Engagement Survey metric."
      },
      annual_note:
        "The continuous improvement plan lists annual Proficient-or-Advanced targets per building (Mandaree Elementary School pp.19-20, Mandaree High School pp.20-21), not for the district. They are compared on each building's dashboard with that building's own results.",
      report_notes: [
        "Workbook provenance [W]. Baselines, targets and Spring/Summer '26 ratings were imported from “ND First School MOU Goal Overview.xlsx” (sheet “Mandaree Goals”); the cell is shown with each value. The workbook does not record who entered each value. Values marked “as written” are shown exactly as in the workbook.",
        "Scope. The workbook goals are written for the district, so they appear only on this participant dashboard; they are not copied to the buildings. Building annual targets (Mandaree Elementary School pp.19-20, Mandaree High School pp.20-21) appear only on each building's dashboard.",
        "Still to confirm. G3-M1's baseline \"< 2.4\" and G4-M1's targets \" > 50%\" / \"> 80%\" are text; Goal 1 and Goal 2 name grades 3-10, which span both buildings."
      ]
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title: "ELA Growth and Achievement",
        description:
          "ELA Growth and Achievement: Mandaree Public Schools will improve ELA achievement for students in grades 3–10 by using an established process to make data-informed instructional decisions with consistency. The district will use ND A+ summative, interim, competency, and practice (formative) assessments (Navvy) to guide instruction, supported by consistent data dialogue protocols focused on ND A+ reports. Progress will be measured by the percentage of students who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth applies to students who are not yet proficient (Novice or Approaching) and who either improve by more than 15 scale score points or move from Novice to Approaching. Proficiency applies to students who maintain their proficiency level or do not decline by more than 15 scale score points.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Math Growth and Achievement",
        description:
          "Math Growth and Achievement: Mandaree Public Schools will improve Mathematics achievement for students in grades 3–10 by making data-informed instructional decisions more frequent and more effective. The district will use ND A+ summative, interim, competency, and practice (formative) assessments (Navvy) to guide instruction, supported by consistent data dialogue protocols focused on ND A+ reports. Progress will be measured by the percentage of students who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth applies to students who are not yet proficient (Novice or Approaching) and who either improve by more than 15 scale score points or move from Novice to Approaching. Proficiency applies to students who maintain their proficiency level or decline by no more than 15 scale score points.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B6; steps E6:G6"
      },
      %{
        number: 3,
        title: "Teacher Efficacy",
        description:
          "Teacher Efficacy: Mandaree Public Schools will strengthen positive leadership practices by establishing clear instructional and operational priorities, fostering cohesion and collaboration across focus areas, and implementing systems that support a positive learning environment.  Mandaree school will demonstrate stronger alignment around shared priorities, a positive culture of learning, improved staff morale, and increased retention of effective educators measured by  a vetted survey to measure staff morale, intentions around retention, individual efficacy, and collective teacher efficacy.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 1, "fal_26" => 4},
        source_ref: "#{@sheet}!B10; steps E10:G10"
      },
      %{
        number: 4,
        title: "Pacing Guides",
        description:
          "Pacing Guides: Mandaree Public Schools will strengthen Tier 1 instruction by implementing standards-aligned, high-quality quarterly pacing guides across all core content areas. Through the use of a district pacing guide quality rubric, consistent data dialogue protocols, and ongoing monitoring and feedback cycles, the district will ensure alignment to ND A+ priority standards, assessment expectations, and common formative assessment cycles. As a result, instructional coherence and rigor will increase across classrooms, supporting improved student growth and proficiency on ND A+ assessments.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 4},
        source_ref: "#{@sheet}!B14; steps E14:G14"
      },
      %{
        number: 5,
        title: "Strengthen Tier 1 Instruction",
        description:
          "Strengthen Tier 1 Instruction: Mandaree Public School will increase the percentage of teachers effectively implementing high-impact instructional strategies in Tier 1 instruction, measured through eleot walkthrough data and guided by Marzano's Focused Teacher Evaluation Framework, to be established as the district's formal observation tool, using a crosswalk to connect evidence between both frameworks.",
        implementation_steps: %{"spr_26" => 3, "sum_26" => 3, "fal_26" => 5},
        source_ref: "#{@sheet}!B18; steps E18:G18"
      },
      %{
        number: 6,
        title: "Leadership Development and Evaluation",
        description:
          "Leadership Development and Evaluation: By establishing a focused and aligned leadership development and evaluation system, Mandaree Public Schools will strengthen leadership effectiveness at both the district and school levels. The Board of Education will hold the Superintendent accountable for the development, communication, and monitoring of measurable district goals within this Collaborative Partnership Agreement (or MoU), as well as support and develop the school leadership team supported by a consistent evaluation process aligned to the Marzano District Leader Framework. At the school level, the superintendent/principal will implement aligned leadership practices from the Marzano Focused School Leader Evaluation Model, with a targeted emphasis on developing and communicating data-driven school improvement goals and improving instructional practices through the use of observational and feedback systems.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B22; steps E22:G22"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description: "Percentage of students meeting growth or proficiency criteria",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.27"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.35"),
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D4", "raw" => "0.27"},
          "target_18m" => %{"cell" => "Mandaree Goals!H4", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Mandaree Goals!P4", "raw" => "0.35"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 1
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description: "Percentage of students meeting growth or proficiency criteria",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.18"),
        target_18m: Decimal.new("0.25"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D8", "raw" => "0.18"},
          "target_18m" => %{"cell" => "Mandaree Goals!H8", "raw" => "0.25"},
          "target_36m" => %{"cell" => "Mandaree Goals!P8", "raw" => "0.3"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I7", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 2
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description: "Increase rating on 0-5 Likert scale",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("3"),
        target_36m: Decimal.new("3.5"),
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D12", "raw" => "< 2.4"},
          "target_18m" => %{"cell" => "Mandaree Goals!H12", "raw" => "3"},
          "target_36m" => %{"cell" => "Mandaree Goals!P12", "raw" => "3.5"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I11", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 3
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description: "Percentage of core content pacing guides that meet Proficient or higher",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.4"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D16", "raw" => "0.4"},
          "target_18m" => %{"cell" => "Mandaree Goals!H16", "raw" => " > 50%"},
          "target_36m" => %{"cell" => "Mandaree Goals!P16", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I15", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 4
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description:
          "Increase average score of teachers effectively implementing strategies that support high expectations, and elaboration of content for Active Learning",
        category: :student_outcome,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("1.67"),
        target_18m: Decimal.new("2.2"),
        target_36m: Decimal.new("2.75"),
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D20", "raw" => "1.67"},
          "target_18m" => %{"cell" => "Mandaree Goals!H20", "raw" => "2.2"},
          "target_36m" => %{"cell" => "Mandaree Goals!P20", "raw" => "2.75"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 5
      },
      %{
        goal_number: 6,
        code: "G6-M1",
        description: "Increase average Leadership Performance score on Marzano's 4-point rubric",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.7"),
        target_18m: Decimal.new("1.5"),
        target_36m: Decimal.new("2.5"),
        source_values: %{
          "baseline" => %{"cell" => "Mandaree Goals!D24", "raw" => "0.7"},
          "target_18m" => %{"cell" => "Mandaree Goals!H24", "raw" => "1.5"},
          "target_36m" => %{"cell" => "Mandaree Goals!P24", "raw" => "2.5"},
          "review_18m_heading" => %{"cell" => "Mandaree Goals!I23", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 6
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 3, "Mandaree Goals!E4"},
      {"G1-M1", "sum_26", 3, "Mandaree Goals!F4"},
      {"G2-M1", "spr_26", 3, "Mandaree Goals!E8"},
      {"G2-M1", "sum_26", 3, "Mandaree Goals!F8"},
      {"G3-M1", "spr_26", 1, "Mandaree Goals!E12"},
      {"G3-M1", "sum_26", 2, "Mandaree Goals!F12"},
      {"G4-M1", "spr_26", 1, "Mandaree Goals!E16"},
      {"G4-M1", "sum_26", 2, "Mandaree Goals!F16"},
      {"G5-M1", "spr_26", 3, "Mandaree Goals!E20"},
      {"G5-M1", "sum_26", 3, "Mandaree Goals!F20"},
      {"G6-M1", "spr_26", 1, "Mandaree Goals!E24"},
      {"G6-M1", "sum_26", 2, "Mandaree Goals!F24"}
    ]
  end

  @doc "The plan sets no district-level annual targets (they are per building)."
  def annual_assessment_goals, do: []
end
