defmodule Emisint.Improvement.Seeds.Dunseith do
  @moduledoc """
  Dunseith Public School District definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Dunseith Goals". Every value
  cites its source cell.

  The sheet is written for the district (its goals name "Dunseith Public
  School(s)" and the district), so this is the participant record: workbook
  goals, metrics, seasonal ratings and the payment row ("Performance-Based
  Payment" row 9). The continuous improvement plan's annual
  targets are per building (Dunseith Elementary School pp.12-13, Dunseith High School pp.13-15) and are seeded on the
  building records (`buildings/0`); see `Emisint.Improvement.Seeds.Participant`.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Dunseith Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-21]

  alias Emisint.Improvement.Seeds

  def school do
    %{
      name: "Dunseith Public School District",
      short_name: "Dunseith",
      slug: "dunseith-public-school-district",
      state: "ND",
      state_entity_id: "40001",
      district_name: "Dunseith Public School District",
      grade_span: nil,
      active: true
    }
  end

  @doc "Payment terms: the workbook's, shared by every participant (`Seeds.Participant.workbook_payment_terms/0`)."
  defdelegate payment_terms,
    to: Emisint.Improvement.Seeds.Participant,
    as: :workbook_payment_terms

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
        "ND First School MOU Goal Overview.xlsx: 'Dunseith Goals' and 'Performance-Based Payment' (row 9). Progress-monitoring link listed as \"Dunseith Tracking Progress\" (Dunseith Goals!B1), with no URL."
    }
  end

  @doc "The building records whose annual targets the continuous improvement plan lists, in PDF order."
  def buildings, do: [Seeds.DunseithElementary, Seeds.DunseithHigh]

  @doc "Source support for recording the workbook goals on the district record."
  def workbook_scope do
    %{
      status: :source_supported,
      excerpt:
        "“ELA Growth and Achievement: Dunseith Public Schools will increase ELA achievement …”; “The district will implement consistent data dialogue protocols …”; “students in grades 3-10 …” (Dunseith Goals!B2). Grades 3-10 span Dunseith Elementary and Dunseith High School.",
      note: nil,
      evidence: []
    }
  end

  @doc """
  The first school year whose results fall inside the plan: the reporting
  periods start with Spr '26 (Dunseith Goals!E3).
  """
  def plan_start_year, do: "2025-2026"

  @doc """
  How the district's workbook goals are compared with the district's own
  published ND Insights results (`Emisint.Improvement.ResultGoals`).
  Confirmed by the user (November 12, 2026): G6-M2 ("Disengaged") counts the
  district's Overall Disengaged. See `matching` for the other metrics.
  """
  def comparison do
    %{
      plan_start_year: plan_start_year(),
      workbook: [
        {"G6-M2", "% of students reporting as \"Disengaged\" on the ND Student Engagement Survey",
         :engagement, :engagement_overall, "Disengaged", "Overall Disengaged"}
      ],
      # Confirmed by the user (November 12, 2026).
      confirmed: %{engagement_population: :schoolwide},
      confirmations: %{
        "G6-M2" =>
          "Confirmed by the user (November 12, 2026): “Disengaged” means the Engagement Survey's Overall Disengaged, the district's own published rows (InstitutionID 40001), all students. Its baseline (20%) doesn't equal a published Overall value (18% in 2022-23 through 2024-25); recorded as written."
      },
      assumptions: %{},
      grade_reference: nil,
      matching:
        "G6-M2 (\"Disengaged\") is matched to the district's Engagement Survey Overall Disengaged (lower is better), all students (confirmed by the user, November 12, 2026). Its 18-month target is “n/a” (gray, no target); its 36-month target “< 15%” is compared as an inequality. G1-M1 and G2-M1 count students in grades 3-10 who maintain proficiency or grow more than 17 scale-score points, which Insights doesn't publish. G3-M3 (\"Graduation Rate\", 73% to 80%) isn't in the imported datasets. The other metrics are local measures (NAVVY training, course failure, Marzano rubric scores, IEP progress, trusted adults, chronic absenteeism). The state results on this page are the district's own published rows (InstitutionID 40001); building results are on each building's dashboard and are never averaged or combined here.",
      assumptions_text:
        "No assumptions are applied for Dunseith Public School District. Confirmed by the user (November 12, 2026): G6-M2 counts the district's Overall Disengaged.",
      assumptions_short:
        "Dunseith: G6-M2 → the district's Overall Disengaged (confirmed, November 12, 2026). Annual targets are compared on each building's dashboard.",
      section_notes: %{
        achievement:
          "District results (InstitutionID 40001). No workbook goal is matched to them, and the plan sets annual targets per building, not for the district.",
        growth:
          "Dunseith's growth goals (G1-M1, G2-M1) count individual scale-score growth, which Insights doesn't publish, so growth results have no school goal.",
        engagement:
          "District Overall Disengaged is compared with G6-M2 (18-month target “n/a”; 36-month target “< 15%”), confirmed by the user (November 12, 2026)."
      },
      annual_note:
        "The continuous improvement plan lists annual Proficient-or-Advanced targets per building (Dunseith Elementary School pp.12-13, Dunseith High School pp.13-15), not for the district. They are compared on each building's dashboard with that building's own results.",
      report_notes: [
        "Workbook provenance [W]. Baselines, targets and Spring/Summer '26 ratings were imported from “ND First School MOU Goal Overview.xlsx” (sheet “Dunseith Goals”); the cell is shown with each value. The workbook does not record who entered each value. Values marked “as written” are shown exactly as in the workbook.",
        "Scope. The workbook goals are written for the district, so they appear only on this participant dashboard; they are not copied to the buildings. Building annual targets (Dunseith Elementary School pp.12-13, Dunseith High School pp.13-15) appear only on each building's dashboard.",
        "Still to confirm. G1-M2 and G2-M2's 18-month target \"50% K-6; 100% 7-12\" (a campus split) and G4-M1's \"70% @ Level 2+\" / \"70% @ Level 3+\" are text; G4-M2 has no baseline; which graduation rate (4-, 5- or 6-year) G3-M3 counts."
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
          "ELA Growth and Achievement: Dunseith Public Schools will increase ELA achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to ND Power Standards and responsive to student performance. As a result, the percentage of students in grades 3-10 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 17 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 17 scale score points. To support student achievement and growth, teachers will be trained to utilize NAVVY Practice Tests and Competency Tests that follow scope and sequence of standards and match the rigor of the state summative assessment.",
        implementation_steps: %{"spr_26" => 3, "sum_26" => 3, "fal_26" => 6},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Math Growth and Achievement",
        description:
          "Math Growth and Achievement: Dunseith Public Schools will increase Mathematics achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to ND Power Standards and responsive to student performance. As a result, the percentage of students in grades 3-10 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 17 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 17 scale score points. To support student achievement and growth, teachers will be trained to utilize NAVVY Practice Tests and Competency Tests that follow scope and sequence of standards and match the rigor of the state summative assessment.",
        implementation_steps: %{"spr_26" => 3, "sum_26" => 4, "fal_26" => 6},
        source_ref: "#{@sheet}!B7; steps E7:G7"
      },
      %{
        number: 3,
        title: "BARR \"Adopt a Student\"",
        description:
          "BARR \"Adopt a Student\": Dunseith Public School will strengthen its BARR (Building Assets, Reducing Risks) system by implementing an \"Adopt-a-Student\" strategy to ensure that students at risk of academic failure are supported through consistent adult relationships and monitoring. By increasing staff ownership of at-risk students and providing targeted support, the district will reduce course failure rates and improve student completion outcomes. High rates of course failure among students in grades 7-12, often influenced by chronic absenteeism, behavior challenges, and limited consistent adult support. While absenteeism is common due to community circumstances, the primary concern is the number of students whose attendance patterns negatively impact academic success and result is failing grades.",
        implementation_steps: %{"spr_26" => 4, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B12; steps E12:G12"
      },
      %{
        number: 4,
        title: "Strengthen Tier 1 Instruction",
        description:
          "Strengthen Tier 1 Instruction: By strengthening the consistent implementation of high-impact instructional strategies aligned to Marzano's Focus Teacher Evaluation Framework, Dunseith Public School will increase the percentage of teachers effectively implementing strategies that support student processing and elaboration of content. Based on an estimated baseline of 20% of teachers demonstrating Level 2 or higher in 2025, the district will increase to at least 70% of teachers demonstrating Level 2 or higher on Helping Students Process New Content by January 2027, and to at least 70% of teachers demonstrating Level 3 (\"Applying\") on Helping Students Process New Content and Level 2 or higher on Using Questions to Help Students Elaborate on Content by Spring 2028, as measured through classroom walkthrough observations and observation rubric data.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 4},
        source_ref: "#{@sheet}!B18; steps E18:G18"
      },
      %{
        number: 5,
        title: "Leadership Development and Evaluation",
        description:
          "Leadership Development and Evaluation: By establishing a focused and aligned leadership development and evaluation system, Dunseith Public Schools will strengthen leadership effectiveness at both the district and school levels. The Board of Education will hold the Superintendent accountable for the development, communication, and monitoring of measurable district goals within this Collaborative Partnership Agreement (or MoU) (Domain 1, Element 1 or 1.1), as well as support and develop the school leadership team (Domain 2.3) and supported by a consistent evaluation process aligned to the Marzano District Leader Framework.\nAt the school level, principals will implement aligned leadership practices from the Marzano Focused School Leader Evaluation Model, with a targeted emphasis on developing and communicating data-driven school improvement goals (Domain 1.1) and improving instructional practices through the use of observational and feedback systems (Domain 2.2).\nAt the District (3.3) and School level (2.5), the element for \"ensuring each student has equal opportunity to learn the critical content\" was added to address identified compliance issues from the July 2025 focused monitoring process for special education requirements and some false positive and false negative identification of both Students with Disabilities and English Learners. Specifically related to Special Education, 18 of 38 (or 47%) of files reviewed did not contain \"evaluation records that appeared comprehensive and the student clearly met the eligibility criteria.\" Therefore, as part of the Focus Monitoring plan, 18 of the 18 files will be corrected for Evaluation Procedures and Eligibility Determination and staff will be trained on evaluations, progress monitoring, FAPE, and Least Restrictive Environment.",
        implementation_steps: %{"spr_26" => 4, "sum_26" => 5, "fal_26" => 7},
        source_ref: "#{@sheet}!B23; steps E23:G23"
      },
      %{
        number: 6,
        title: "Increase Student Engagement and Decrease Disengagement",
        description:
          "Increase Student Engagement and Decrease Disengagement: By strengthening the consistent implementation of engagement strategies aligned to Marzano's Focus Teacher Evaluation Framework, Dunseith Public Schools will increase classroom-level student engagement and reduce student disengagement. Based on a baseline of approximately 1.7 on the Marzano engagement element and 20% of students reporting disengagement in 2025, the school wil improve to at least 2.2 by January 2027 and at least 2.6 by Spring 2028 on the Marzano rubric, while reducing student disengagement to less than 15% by Spring 2028, as measured by the ND Student Engagement Survey",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B29; steps E29:G29"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description:
          "% of students in grades 3-10 who maintain proficiency or demonstrate growth greater than 17 scale score points on the ND A+ ELA assessment",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.33"),
        target_18m: Decimal.new("0.38"),
        target_36m: Decimal.new("0.43"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D4", "raw" => "0.33"},
          "target_18m" => %{"cell" => "Dunseith Goals!H4", "raw" => "0.38"},
          "target_36m" => %{"cell" => "Dunseith Goals!P4", "raw" => "0.43"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description:
          "% of ELA teachers trained to use NAVVY and who will administer multiple practice tests and multiple competency tests",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D5", "raw" => "0"},
          "target_18m" => %{"cell" => "Dunseith Goals!H5", "raw" => "50% K-6; 100% 7-12"},
          "target_36m" => %{"cell" => "Dunseith Goals!P5", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 2
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description:
          "% of students in grades 3-10 who maintain proficiency or demonstrate growth greater than 17 scale score points on the ND A+ Math assessment",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.33"),
        target_18m: Decimal.new("0.37"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D9", "raw" => "0.33"},
          "target_18m" => %{"cell" => "Dunseith Goals!H9", "raw" => "0.37"},
          "target_36m" => %{"cell" => "Dunseith Goals!P9", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I8", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 3
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description:
          "% of math teachers trained to use NAVVY and who will administer multiple practice tests and multiple competency tests",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D10", "raw" => "0"},
          "target_18m" => %{"cell" => "Dunseith Goals!H10", "raw" => "50% K-6; 100% 7-12"},
          "target_36m" => %{"cell" => "Dunseith Goals!P10", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I8", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 4
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description: "% of staff participating in the \"Adopt-a-Student\" strategy",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.4"),
        target_18m: Decimal.new("0.6"),
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D14", "raw" => "0.4"},
          "target_18m" => %{"cell" => "Dunseith Goals!H14", "raw" => "0.6"},
          "target_36m" => %{"cell" => "Dunseith Goals!P14", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I13", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 5
      },
      %{
        goal_number: 3,
        code: "G3-M2",
        description: "% of students failing one or more courses per semester",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.39"),
        target_18m: Decimal.new("0.33"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D15", "raw" => "0.39"},
          "target_18m" => %{"cell" => "Dunseith Goals!H15", "raw" => "0.33"},
          "target_36m" => %{"cell" => "Dunseith Goals!P15", "raw" => "0.3"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I13", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 6
      },
      %{
        goal_number: 3,
        code: "G3-M3",
        description: "\"Graduation Rate\"",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.73"),
        target_18m: nil,
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D16", "raw" => "0.73"},
          "target_18m" => %{"cell" => "Dunseith Goals!H16", "raw" => nil},
          "target_36m" => %{"cell" => "Dunseith Goals!P16", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I13", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 7
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description:
          "% of teachers demonstrating a Level 2 (\"Beginning\") or higher score on Marzano instructional elements related to helping student process and elaborate on content",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.2"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D20", "raw" => "0.2"},
          "target_18m" => %{"cell" => "Dunseith Goals!H20", "raw" => "70% @ Level 2+"},
          "target_36m" => %{"cell" => "Dunseith Goals!P20", "raw" => "70% @ Level 3+"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 8
      },
      %{
        goal_number: 4,
        code: "G4-M2",
        description:
          "% of teachers demonstrating a Level 3 (\"Applying\") or higher score on Marzano instructional elements related to helping student process new content",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: Decimal.new("0.7"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D21", "raw" => nil},
          "target_18m" => %{"cell" => "Dunseith Goals!H21", "raw" => "n/a"},
          "target_36m" => %{"cell" => "Dunseith Goals!P21", "raw" => "0.7"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 9
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description:
          "Leadership performance across selected elements on Marzano's 4-point Rubric",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.7"),
        target_18m: Decimal.new("1.5"),
        target_36m: Decimal.new("2.5"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D25", "raw" => "0.7"},
          "target_18m" => %{"cell" => "Dunseith Goals!H25", "raw" => "1.5"},
          "target_36m" => %{"cell" => "Dunseith Goals!P25", "raw" => "2.5"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I24", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 10
      },
      %{
        goal_number: 5,
        code: "G5-M2",
        description: "% of students making adequate progress on IEP Goals",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.28"),
        target_18m: Decimal.new("0.33"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D26", "raw" => "0.28"},
          "target_18m" => %{"cell" => "Dunseith Goals!H26", "raw" => "0.33"},
          "target_36m" => %{"cell" => "Dunseith Goals!P26", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I24", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 11
      },
      %{
        goal_number: 5,
        code: "G5-M3",
        description:
          "% of relevant staff trained around Infinite Campus and SOP for compliance issues",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("0.8"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D27", "raw" => "0"},
          "target_18m" => %{"cell" => "Dunseith Goals!H27", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Dunseith Goals!P27", "raw" => "0.8"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I24", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 12
      },
      %{
        goal_number: 6,
        code: "G6-M1",
        description: "Score on Marzano's Rubric for selected engagement elements",
        category: :student_outcome,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("2.2"),
        target_36m: Decimal.new("2.6"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D31", "raw" => "< 1.7"},
          "target_18m" => %{"cell" => "Dunseith Goals!H31", "raw" => "2.2"},
          "target_36m" => %{"cell" => "Dunseith Goals!P31", "raw" => "2.6"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I30", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 13
      },
      %{
        goal_number: 6,
        code: "G6-M2",
        description:
          "% of students reporting as \"Disengaged\" on the ND Student Engagement Survey",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.2"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D32", "raw" => "0.2"},
          "target_18m" => %{"cell" => "Dunseith Goals!H32", "raw" => "n/a"},
          "target_36m" => %{"cell" => "Dunseith Goals!P32", "raw" => "< 15%"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I30", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 14
      },
      %{
        goal_number: 6,
        code: "G6-M3",
        description:
          "# of students who report that they have at least one trusted adult in the building",
        category: :student_outcome,
        unit: :count,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("17"),
        target_18m: Decimal.new("20"),
        target_36m: Decimal.new("27"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D33", "raw" => "17"},
          "target_18m" => %{"cell" => "Dunseith Goals!H33", "raw" => "20"},
          "target_36m" => %{"cell" => "Dunseith Goals!P33", "raw" => "27"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I30", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 15
      },
      %{
        goal_number: 6,
        code: "G6-M4",
        description:
          "% of students who have missed 10 or more days during the school year (chronic absenteeism)",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.68"),
        target_18m: Decimal.new("0.63"),
        target_36m: Decimal.new("0.58"),
        source_values: %{
          "baseline" => %{"cell" => "Dunseith Goals!D34", "raw" => "0.68"},
          "target_18m" => %{"cell" => "Dunseith Goals!H34", "raw" => "0.63"},
          "target_36m" => %{"cell" => "Dunseith Goals!P34", "raw" => "0.58"},
          "review_18m_heading" => %{"cell" => "Dunseith Goals!I30", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 16
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 2, "Dunseith Goals!E4"},
      {"G1-M1", "sum_26", 2, "Dunseith Goals!F4"},
      {"G1-M2", "spr_26", 3, "Dunseith Goals!E5"},
      {"G1-M2", "sum_26", 3, "Dunseith Goals!F5"},
      {"G2-M1", "spr_26", 2, "Dunseith Goals!E9"},
      {"G2-M1", "sum_26", 2, "Dunseith Goals!F9"},
      {"G2-M2", "spr_26", 3, "Dunseith Goals!E10"},
      {"G2-M2", "sum_26", 3, "Dunseith Goals!F10"},
      {"G3-M1", "spr_26", 2, "Dunseith Goals!E14"},
      {"G3-M1", "sum_26", 2, "Dunseith Goals!F14"},
      {"G3-M2", "spr_26", 2, "Dunseith Goals!E15"},
      {"G3-M2", "sum_26", 2, "Dunseith Goals!F15"},
      {"G3-M3", "spr_26", 1, "Dunseith Goals!E16"},
      {"G3-M3", "sum_26", 1, "Dunseith Goals!F16"},
      {"G4-M1", "spr_26", 1, "Dunseith Goals!E20"},
      {"G4-M1", "sum_26", 2, "Dunseith Goals!F20"},
      {"G4-M2", "spr_26", 1, "Dunseith Goals!E21"},
      {"G4-M2", "sum_26", 2, "Dunseith Goals!F21"},
      {"G5-M1", "spr_26", 1, "Dunseith Goals!E25"},
      {"G5-M1", "sum_26", 1, "Dunseith Goals!F25"},
      {"G5-M2", "spr_26", 2, "Dunseith Goals!E26"},
      {"G5-M2", "sum_26", 2, "Dunseith Goals!F26"},
      {"G5-M3", "spr_26", :not_applicable, "Dunseith Goals!E27"},
      {"G5-M3", "sum_26", :not_applicable, "Dunseith Goals!F27"},
      {"G6-M1", "spr_26", 2, "Dunseith Goals!E31"},
      {"G6-M1", "sum_26", 2, "Dunseith Goals!F31"},
      {"G6-M2", "spr_26", 2, "Dunseith Goals!E32"},
      {"G6-M2", "sum_26", 2, "Dunseith Goals!F32"},
      {"G6-M3", "spr_26", 2, "Dunseith Goals!E33"},
      {"G6-M3", "sum_26", 2, "Dunseith Goals!F33"},
      {"G6-M4", "spr_26", 2, "Dunseith Goals!E34"},
      {"G6-M4", "sum_26", 2, "Dunseith Goals!F34"}
    ]
  end

  @doc "The plan sets no district-level annual targets (they are per building)."
  def annual_assessment_goals, do: []
end
