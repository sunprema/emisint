defmodule Emisint.Improvement.Seeds.Drayton do
  @moduledoc """
  Drayton Public School District definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Drayton Goals". Every value
  cites its source cell.

  The sheet is written for the district (its goals name "Drayton Public
  School(s)" and the district), so this is the participant record: workbook
  goals, metrics, seasonal ratings and the payment row ("Performance-Based
  Payment" row 10). The continuous improvement plan's annual
  targets are per building (Drayton Elementary School pp.7-9, Drayton High School pp.9-10) and are seeded on the
  building records (`buildings/0`); see `Emisint.Improvement.Seeds.Participant`.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Drayton Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-31]

  alias Emisint.Improvement.Seeds

  def school do
    %{
      name: "Drayton Public School District",
      short_name: "Drayton",
      slug: "drayton-public-school-district",
      state: "ND",
      state_entity_id: "34019",
      district_name: "Drayton Public School District",
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
        "ND First School MOU Goal Overview.xlsx: 'Drayton Goals' and 'Performance-Based Payment' (row 10). Progress-monitoring link listed as \"Drayton Tracking Progress\" (Drayton Goals!B1), with no URL."
    }
  end

  @doc "The building records whose annual targets the continuous improvement plan lists, in PDF order."
  def buildings, do: [Seeds.DraytonElementary, Seeds.DraytonHigh]

  @doc "Source support for recording the workbook goals on the district record."
  def workbook_scope do
    %{
      status: :source_supported,
      excerpt:
        "“Drayton Public School will increase overall literacy achievement …”; “The district will implement consistent data dialogue protocols …”; “the percentage of students in grades 3-10 …” (Drayton Goals!B2). Grades 3-10 span Drayton Elementary and Drayton High School.",
      note: nil,
      evidence: []
    }
  end

  @doc """
  The first school year whose results fall inside the plan: the reporting
  periods start with Spr '26 (Drayton Goals!E3).
  """
  def plan_start_year, do: "2025-2026"

  @doc """
  How the district's workbook goals are compared with the district's own
  published ND Insights results (`Emisint.Improvement.ResultGoals`). G4-M1
  ("Disengaged") is a candidate mapping to the district's Overall
  Disengaged (`candidates`): its baseline match is evidence to investigate,
  not a confirmation, so it is shown gray without a verdict. See `matching`
  for the other metrics.
  """
  def comparison do
    %{
      plan_start_year: plan_start_year(),
      workbook: [
        {"G4-M1", "% of students reporting as \"Disengaged\"", :engagement, :engagement_overall,
         "Disengaged", "Overall Disengaged"}
      ],
      candidates: %{
        "G4-M1" =>
          "G4-M1 doesn't name the survey category (Overall, Behavioral, Cognitive or Emotional). Its baseline (25%, Drayton Goals!D21) lies in the district's published Overall Disengaged range in both 2023-24 and 2024-25 (25%–29%), and in those years no other area's published range includes it (Emotional Disengaged was 25%–29% in 2022-23). Whether the baseline is a district or building figure is also unconfirmed. Confirming the category would enable a verdict. District rows only (InstitutionID 34019)."
      },
      assumptions: %{},
      grade_reference: nil,
      matching:
        "G4-M1 (\"Disengaged\") is a candidate mapping to the district's Engagement Survey Overall Disengaged (lower is better), shown gray without a verdict until the survey category is confirmed: the workbook doesn't name it, and the baseline match (25% lies in the published Overall Disengaged range in 2023-24 and 2024-25) is evidence to investigate, not a confirmation. Its 18-month target is empty; its 36-month target “< 18%” would be compared as an inequality (below 18% meets). G1-M1 and G2-M1 count students in grades 3-10 meeting growth-or-proficiency criteria (interim at 18 months, summative ND A+ at 36 months), which Insights doesn't publish; G2-M3 uses interim assessments. G4-M2 counts \"Engaged\", which isn't an Insights level, so it isn't compared. The other metrics are local measures (NAVVY training, PBIS recognition records, Marzano rubric scores, low-income monitoring, staff efficacy). The state results on this page are the district's own published rows (InstitutionID 34019); building results are on each building's dashboard and are never averaged or combined here.",
      assumptions_text:
        "No assumptions are applied for Drayton Public School District. G4-M1's survey category is unconfirmed: Overall is a candidate because its baseline lies in the district's published Overall Disengaged range, so the comparison is shown gray, without a verdict. G4-M2 (\"Engaged\") stays uncompared: its baseline (29%) lies in the published Overall Committed range (25%–29% in 2024-25), but whether “Engaged” means Insights' Committed level needs confirmation.",
      assumptions_short:
        "No assumptions for Drayton: G4-M1 → the district's Overall Disengaged is a candidate mapping awaiting confirmation (gray, no verdict); G4-M2 awaits confirmation that “Engaged” means Committed. Annual targets are compared on each building's dashboard.",
      section_notes: %{
        achievement:
          "District results (InstitutionID 34019). No workbook goal is matched to them, and the plan sets annual targets per building, not for the district.",
        growth:
          "Drayton's growth goals (G1-M1, G2-M1) count individual growth-or-proficiency criteria, which Insights doesn't publish, so growth results have no school goal.",
        engagement:
          "District Overall Disengaged is shown with G4-M1 as a candidate mapping, gray without a verdict until the survey category is confirmed (no 18-month target; 36-month target “< 18%”). Not compared: G4-M2 counts “Engaged”, which isn't an Insights level; its baseline (29%) lies in the Overall Committed range, but that reading needs confirmation."
      },
      annual_note:
        "The continuous improvement plan lists annual Proficient-or-Advanced targets per building (Drayton Elementary School pp.7-9, Drayton High School pp.9-10), not for the district. They are compared on each building's dashboard with that building's own results.",
      report_notes: [
        "Workbook provenance [W]. Baselines, targets and Spring/Summer '26 ratings were imported from “ND First School MOU Goal Overview.xlsx” (sheet “Drayton Goals”); the cell is shown with each value. The workbook does not record who entered each value. Values marked “as written” are shown exactly as in the workbook.",
        "Scope. The workbook goals are written for the district, so they appear only on this participant dashboard; they are not copied to the buildings. Building annual targets (Drayton Elementary School pp.7-9, Drayton High School pp.9-10) appear only on each building's dashboard.",
        "Still to confirm. G4-M1's survey category (Overall is a candidate because its baseline lies in the district's published Overall Disengaged range; no verdict until confirmed) and whether its baseline (25%) is a district or building figure; G4-M2's \"Engaged\" definition; G2-M3's baseline \"< 10%\" and targets for the elementary low-income group; G4-M4's text targets (\"Monitored\"); the goal titles (the sheet gives none, so each goal's full text is its title)."
      ]
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title:
          "Drayton Public School will increase overall literacy achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to ND Power Standards and responsive to student performance. As a result, the percentage of students in grades 3-10 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 17 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 17 scale score points.",
        description: nil,
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title:
          "Drayton Public School wil increase overall mathematics achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to ND Power Standards and responsive to student performance. As a result, the percentage of students in grades 3-10 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 17 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 17 scale score points.",
        description: nil,
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B8; steps E8:G8"
      },
      %{
        number: 3,
        title:
          "Drayton Public School will improve the quality and effectiveness of instruction by increasing the consistent use of evidence-based teaching strategies- including explicit instruction, active engagement techniques, and other high-impact practices-across all classrooms throughout the school year. By the end of the 36 months, classrooms will demonstrate stronger alignment to evidence-based instructional practices, resulting in more engaged learners and improved academic outcomes. Classroom walk throughs will track \"active\" student engagement using Marzano's \"Using Student Engagement Strategies\" such that the aggregate teacher score will be greater than or equal to 2 (\"developing\") by January 2027 and greater than or equal to 2.5 which is approaching \"applying\" by Spring 2028.",
        description: nil,
        implementation_steps: %{"spr_26" => 2, "sum_26" => 1, "fal_26" => 4},
        source_ref: "#{@sheet}!B14; steps E14:G14"
      },
      %{
        number: 4,
        title:
          "Drayton Public Schools will strengthen the consistent implementation of Positive Behavioral Interventions and Supports (PBIS) and effective classroom management practices by establishing clear schoolwide expectations, increasing staff consistency in \"Adherence to Rules and Procedures,\" and improving positive student-to-student and student-to-teacher interactions. As a result, the percentage of students identified as \"Disengaged\" on the North Dakota Student Engagement Survey will decrease, and classroom environments will demonstrate improved consistency and structure as measured through Marzano's Focus Teacher Evaluation Framework.",
        description: nil,
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B19; steps E19:G19"
      },
      %{
        number: 5,
        title:
          "Drayton Public Schools will strengthen leadership coherence, staff collaboration, and systems supporting educator effectiveness and retention to increase collective efficacy and school culture. The aggregate staff efficacy score, measured through a consistent staff survey on a 0–5 scale, will increase from an estimated baseline below 1.5 to at least 3.0 by January 2027 and at least 3.8 by Spring 2028.",
        description: nil,
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 3},
        source_ref: "#{@sheet}!B26; steps E26:G26"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description:
          "% of students in grades 3 - 10 meeting growth or proficiency criteria on the interim at 18 months and summative ND A+ at 36 months",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.27"),
        target_18m: Decimal.new("0.32"),
        target_36m: Decimal.new("0.37"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D4", "raw" => "0.27"},
          "target_18m" => %{"cell" => "Drayton Goals!H4", "raw" => "0.32"},
          "target_36m" => %{"cell" => "Drayton Goals!P4", "raw" => "0.37"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description:
          "% of teachers trained in the use of NAVVY as an assessment tool by 18 months and utilizing by 36 months",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D5", "raw" => "0"},
          "target_18m" => %{"cell" => "Drayton Goals!H5", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Drayton Goals!P5", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 2
      },
      %{
        goal_number: 1,
        code: "G1-M3",
        description:
          "% of students being recognized through PBIS for growth, achievement, and positive behavior as measured by PBIS recognition records",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.3"),
        target_18m: Decimal.new("0.36"),
        target_36m: Decimal.new("0.42"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D6", "raw" => "0.3"},
          "target_18m" => %{"cell" => "Drayton Goals!H6", "raw" => "0.36"},
          "target_36m" => %{"cell" => "Drayton Goals!P6", "raw" => "0.42"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 3
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description:
          "% of students in grades 3 - 10 meeting growth or proficiency criteria on the interim at 18 months and summative ND A+ at 36 months",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.38"),
        target_18m: Decimal.new("0.41"),
        target_36m: Decimal.new("0.45"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D10", "raw" => "0.38"},
          "target_18m" => %{"cell" => "Drayton Goals!H10", "raw" => "0.41"},
          "target_36m" => %{"cell" => "Drayton Goals!P10", "raw" => "0.45"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I9", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 4
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description:
          "% of teachers trained in the use of NAVVY as an assessment tool by 18 months and 36 months",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("1"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D11", "raw" => "0"},
          "target_18m" => %{"cell" => "Drayton Goals!H11", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Drayton Goals!P11", "raw" => "1"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I9", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 5
      },
      %{
        goal_number: 2,
        code: "G2-M3",
        description:
          "% of low income students in the elementary school who show proficiency on the interim assessments",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.16"),
        target_36m: Decimal.new("0.24"),
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D12", "raw" => "< 10%"},
          "target_18m" => %{"cell" => "Drayton Goals!H12", "raw" => "0.16"},
          "target_36m" => %{"cell" => "Drayton Goals!P12", "raw" => "0.24"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I9", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 6
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description:
          "Aggregate score of Teacher observations regarding \"using engagement strategies\" on Marzano's Rubric",
        category: :student_outcome,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("1.4"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D16", "raw" => "1.4"},
          "target_18m" => %{"cell" => "Drayton Goals!H16", "raw" => "> 2"},
          "target_36m" => %{"cell" => "Drayton Goals!P16", "raw" => "> 2.5"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I15", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 7
      },
      %{
        goal_number: 3,
        code: "G3-M2",
        description:
          "Aggregate score of Teacher observations regarding \"Helping Students process content\" on Marzano's Rubric",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("1.4"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D17", "raw" => "1.4"},
          "target_18m" => %{"cell" => "Drayton Goals!H17", "raw" => "> 2"},
          "target_36m" => %{"cell" => "Drayton Goals!P17", "raw" => "> 2.5"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I15", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 8
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description: "% of students reporting as \"Disengaged\"",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.25"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D21", "raw" => "0.25"},
          "target_18m" => %{"cell" => "Drayton Goals!H21", "raw" => nil},
          "target_36m" => %{"cell" => "Drayton Goals!P21", "raw" => "< 18%"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 9
      },
      %{
        goal_number: 4,
        code: "G4-M2",
        description: "% of students reporting as \"Engaged\"",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.29"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D22", "raw" => "0.29"},
          "target_18m" => %{"cell" => "Drayton Goals!H22", "raw" => nil},
          "target_36m" => %{"cell" => "Drayton Goals!P22", "raw" => "> 39%"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 10
      },
      %{
        goal_number: 4,
        code: "G4-M3",
        description: "Teacher's score on Marzano's \"Adherence to Rules and Procedures\"",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("1.7"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D23", "raw" => "1.7"},
          "target_18m" => %{"cell" => "Drayton Goals!H23", "raw" => "> 2"},
          "target_36m" => %{"cell" => "Drayton Goals!P23", "raw" => "> 2.5"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 11
      },
      %{
        goal_number: 4,
        code: "G4-M4",
        description: "Low income subgroup will be monitored for attendance and achievement",
        category: :systems,
        unit: :text,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D24", "raw" => "Not monitored"},
          "target_18m" => %{"cell" => "Drayton Goals!H24", "raw" => "Monitored"},
          "target_36m" => %{"cell" => "Drayton Goals!P24", "raw" => "Monitored"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 12
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description: "Aggregate staff efficacy score on a 0-5 Likert scale",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Drayton Goals!D28", "raw" => "< 1.5"},
          "target_18m" => %{"cell" => "Drayton Goals!H28", "raw" => "> 3"},
          "target_36m" => %{"cell" => "Drayton Goals!P28", "raw" => "> 3.8"},
          "review_18m_heading" => %{"cell" => "Drayton Goals!I27", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 13
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 3, "Drayton Goals!E4"},
      {"G1-M1", "sum_26", 3, "Drayton Goals!F4"},
      {"G1-M2", "spr_26", 0, "Drayton Goals!E5"},
      {"G1-M2", "sum_26", 1, "Drayton Goals!F5"},
      {"G1-M3", "spr_26", 2, "Drayton Goals!E6"},
      {"G1-M3", "sum_26", 2, "Drayton Goals!F6"},
      {"G2-M1", "spr_26", 3, "Drayton Goals!E10"},
      {"G2-M1", "sum_26", 3, "Drayton Goals!F10"},
      {"G2-M2", "spr_26", 0, "Drayton Goals!E11"},
      {"G2-M2", "sum_26", 1, "Drayton Goals!F11"},
      {"G2-M3", "spr_26", 1, "Drayton Goals!E12"},
      {"G2-M3", "sum_26", 1, "Drayton Goals!F12"},
      {"G3-M1", "spr_26", 2, "Drayton Goals!E16"},
      {"G3-M1", "sum_26", 2, "Drayton Goals!F16"},
      {"G3-M2", "spr_26", 2, "Drayton Goals!E17"},
      {"G3-M2", "sum_26", 2, "Drayton Goals!F17"},
      {"G4-M1", "spr_26", 2, "Drayton Goals!E21"},
      {"G4-M1", "sum_26", 2, "Drayton Goals!F21"},
      {"G4-M2", "spr_26", 2, "Drayton Goals!E22"},
      {"G4-M2", "sum_26", 2, "Drayton Goals!F22"},
      {"G4-M3", "spr_26", 2, "Drayton Goals!E23"},
      {"G4-M3", "sum_26", 2, "Drayton Goals!F23"},
      {"G4-M4", "spr_26", 1, "Drayton Goals!E24"},
      {"G4-M4", "sum_26", 1, "Drayton Goals!F24"},
      {"G5-M1", "spr_26", 3, "Drayton Goals!E28"},
      {"G5-M1", "sum_26", 3, "Drayton Goals!F28"}
    ]
  end

  @doc "The plan sets no district-level annual targets (they are per building)."
  def annual_assessment_goals, do: []
end
