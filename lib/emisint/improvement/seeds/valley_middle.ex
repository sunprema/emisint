defmodule Emisint.Improvement.Seeds.ValleyMiddle do
  @moduledoc """
  Valley Middle School definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Valley Goals", and the ND First
  schools PDF (pp.25-26). Every value cites its source cell.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Valley Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-28]

  def school do
    %{
      name: "Valley Middle School",
      short_name: "Valley",
      slug: "valley-middle-school",
      state: "ND",
      state_entity_id: "1800189752",
      district_name: "Grand Forks Public School District",
      grade_span: "6-8",
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
        "ND First School MOU Goal Overview.xlsx: 'Valley Goals' and 'Performance-Based Payment'. School Improvement Camp link listed as TBD (Valley Goals!B1)."
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title: "ELA Growth and Achievement",
        description:
          "ELA Growth and Achievement: Valley Middle School will increase ELA achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to essential ND Standards and responsive to student performance. As a result, the percentage of students in grades 6-8 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 13 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 13 scale score points.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Math Growth and Achievement",
        description:
          "Math Growth and Achievement: Valley Middle School will increase Mathematics achievement by strengthening the frequency and quality of data-informed instructional decision-making through the use of ND A+ summative, interim, competency, and practice tests (formative). The district will implement consistent data dialogue protocols focused on ND A+ reports to ensure instruction is aligned to Essential Standards and responsive to student performance. As a result, the percentage of students in grades 6-8 will improve who either maintain Proficiency or demonstrate substantial Growth toward proficiency on the ND A+ Summative Assessment. Growth will be defined as students not yet proficient (Novice or Approaching) who improve by more than 13 scale score points, and Proficiency will be defined as students maintaining their proficiency level or without declining more than 13 scale score points.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B9; steps E9:G9"
      },
      %{
        number: 3,
        title: "PBIS & Behavior System to Decrease Disengagement",
        description:
          "PBIS & Behavior System to Decrease Disengagement: Valley Middle School will decrease student disengagement, as measured by the North Dakota Student Engagement Survey, by strengthening the consistent implementation of schoolwide behavioral expectations through PBIS and improving classroom management and student engagement practices. Based on a 2023-2025 baseline of 24-28% of students reporting as \"Disengaged,\" the school will reduce disengagement to less than 18% or within 4 percentage points of the state average by Spring 2028. Progress will be monitored using engagement survey data (lagging) and leading indicators including behavior data, attendance, and walkthrough evidence of consistent expectations and student engagement practices.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 5},
        source_ref: "#{@sheet}!B16; steps E16:G16"
      },
      %{
        number: 4,
        title: "Strengthen Tier 1 Rigor",
        description:
          "Strengthen Tier 1 Rigor: Valley Middle School will strengthen Tier 1 instructional rigor by improving the consistent use of high-impact instructional strategies aligned to Marzano's Focus Teacher Observation Framework. Based on an estimated 2025 baseline aggregate score below 1.8 across selected elements within the Standard-Based Instruction domain, the school will increase instructional rigor to exceed 2.5 by Spring 2028. Progress will be monitored through classroom walkthrough data (leading indicator) and observation rubric scores aligned to Marzano elements (outcome measure).",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 6},
        source_ref: "#{@sheet}!B24; steps E24:G24"
      },
      %{
        number: 5,
        title: "Increase Student Agency and Engagement",
        description:
          "Increase Student Agency and Engagement: Valley Middle School will increase student engagement by strengthening the consistent use of student engagement strategies aligned to Marzano's Focus Teacher Observation Framework, promoting active participation, academic talk, structured collaboration, and student agency. Based on a 2023-2025 baseline of approximately 30% of students reporting as \"Engaged\" or \"Committed\" on the North Dakota Student Engagement Survey, Valley Middle School will increase student engagement to exceed 35% by Spring 2028. Valley Middle School will strengthen student agency through schoolwide systems and practices that support relationships, persistence, academic skill use, and social awareness. By the 18-month check-in, at least 15% of students will report \"Often\" or higher across the four AVID Student Agency domains. By the 36-month check-in, at least 30% of students will report \"Often\" or higher across those same domains.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 1, "fal_26" => 6},
        source_ref: "#{@sheet}!B28; steps E28:G28"
      },
      %{
        number: 6,
        title: "Tier 2 Flex Time",
        description:
          "Tier 2 Flex Time: Valley Middle School will strengthen its Tier 2 system by implementing a consistent and data-driven Flex Time structure that provides targeted academic support aligned to Essential Standards. By increasing the percentage of students receiving data-based intervention and demonstrating proficiency on targeted standards, the school will reduce the number of students performing below grade-level expectations. Progress will be monitored through RTI Scheduler data and walkthrough observations (leading indicators) and student performance on standards-aligned assessments (lagging outcome).",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 3, "fal_26" => 5},
        source_ref: "#{@sheet}!B36; steps E36:G36"
      },
      %{
        number: 7,
        title: "Teacher Efficacy",
        description:
          "Teacher Efficacy: Valley Middle School will strengthen leadership coherence, clarify instructional priorities, and enhance collaborative systems through the Guiding Coalition (e.g., PLC, AVID, PBIS, Flex) to improve staff perceptions of individual and collective teacher efficacy. Through consistent implementation of these systems and ongoing feedback cycles, staff will experience greater alignment, collaboration, and organizational clarity. As a result, teacher efficacy will increase over time, as measured by a consistent Teacher Efficacy Survey administered annually, contributing to stronger instructional coherence and improved staff retention.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 7},
        source_ref: "#{@sheet}!B44; steps E44:G44"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description:
          "Percentage of students who maintained proficiency or who showed growth greater than 13 scale score points",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.41"),
        target_18m: Decimal.new("0.45"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D4", "raw" => "0.41"},
          "target_18m" => %{"cell" => "Valley Goals!H4", "raw" => "0.45"},
          "target_36m" => %{"cell" => "Valley Goals!P4", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description: "Percentage of ELA teachers trained in NAVVY utilization",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D5", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H5", "raw" => "> 50%"},
          "target_36m" => %{"cell" => "Valley Goals!P5", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 2
      },
      %{
        goal_number: 1,
        code: "G1-M3",
        description:
          "Percentage of ELA teachers using Competency-Based Assessment in NAVVY for data cycles",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D6", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H6", "raw" => "> 50%"},
          "target_36m" => %{"cell" => "Valley Goals!P6", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 3
      },
      %{
        goal_number: 1,
        code: "G1-M4",
        description:
          "Percentage of ELA teachers using data dialogues within their PLCs use Student artifacts, such as assessment data",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.125"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D7", "raw" => "0.125"},
          "target_18m" => %{"cell" => "Valley Goals!H7", "raw" => " > 25%"},
          "target_36m" => %{"cell" => "Valley Goals!P7", "raw" => "> 37%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 4
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description:
          "Percentage of students who maintained proficiency or who showed growth greater than 13 scale score points",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.29"),
        target_18m: Decimal.new("0.32"),
        target_36m: Decimal.new("0.38"),
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D11", "raw" => "0.29"},
          "target_18m" => %{"cell" => "Valley Goals!H11", "raw" => "0.32"},
          "target_36m" => %{"cell" => "Valley Goals!P11", "raw" => "0.38"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 5
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description:
          "Percentage of Math teachers trained in data cycles using student assessment results in NAVVY",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D12", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H12", "raw" => "> 50%"},
          "target_36m" => %{"cell" => "Valley Goals!P12", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 6
      },
      %{
        goal_number: 2,
        code: "G2-M3",
        description:
          "Percentage of Math teachers in data cycles using standard level reports in NAVVY",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D13", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H13", "raw" => "> 50%"},
          "target_36m" => %{"cell" => "Valley Goals!P13", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 7
      },
      %{
        goal_number: 2,
        code: "G2-M4",
        description:
          "Percentage of Math teachers using data dialogues within their PLCs use Student artifacts, such as assessment data",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.1"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D14", "raw" => "0.1"},
          "target_18m" => %{"cell" => "Valley Goals!H14", "raw" => " > 20%"},
          "target_36m" => %{"cell" => "Valley Goals!P14", "raw" => "> 30%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 8
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description:
          "Percentage of students reported as \"Disengaged\" on the ND Student Engagement Survey",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.28"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D18", "raw" => "0.28"},
          "target_18m" => %{"cell" => "Valley Goals!H18", "raw" => "n/a"},
          "target_36m" => %{"cell" => "Valley Goals!P18", "raw" => "< 22% or within 7% State Avg"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I17", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 9
      },
      %{
        goal_number: 3,
        code: "G3-M2",
        description: "Number of behavioral incidents per month",
        category: :student_outcome,
        unit: :count,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("137"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D19", "raw" => "137"},
          "target_18m" => %{"cell" => "Valley Goals!H19", "raw" => "< 120"},
          "target_36m" => %{"cell" => "Valley Goals!P19", "raw" => nil},
          "review_18m_heading" => %{"cell" => "Valley Goals!I17", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 10
      },
      %{
        goal_number: 3,
        code: "G3-M3",
        description: "Percentage of classrooms that have clear, schoolwide expectations posted",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.15"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D20", "raw" => "0.15"},
          "target_18m" => %{"cell" => "Valley Goals!H20", "raw" => "> 30%"},
          "target_36m" => %{"cell" => "Valley Goals!P20", "raw" => "> 45%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I17", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 11
      },
      %{
        goal_number: 3,
        code: "G3-M4",
        description: "Percentage of teachers explicitly teaching expectations in common areas",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D21", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H21", "raw" => "> 30%"},
          "target_36m" => %{"cell" => "Valley Goals!P21", "raw" => "> 50%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I17", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 12
      },
      %{
        goal_number: 3,
        code: "G3-M5",
        description: "Percentage of teachers who have logged a positive behavioral referral",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D22", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H22", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Valley Goals!P22", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I17", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 13
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description:
          "Aggregate score on selected elements (Help Students Process and Elaborate) of  Marzano's Focus Teacher Observation Framework",
        category: :systems,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D26", "raw" => "< 1.8"},
          "target_18m" => %{"cell" => "Valley Goals!H26", "raw" => "> 2"},
          "target_36m" => %{"cell" => "Valley Goals!P26", "raw" => "> 2.5"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I25", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 14
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description: "Aggregate score on Marzano's Rubric for selected engagement strategies",
        category: :student_outcome,
        unit: :score,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D30", "raw" => "< 1.5"},
          "target_18m" => %{"cell" => "Valley Goals!H30", "raw" => "> 2"},
          "target_36m" => %{"cell" => "Valley Goals!P30", "raw" => nil},
          "review_18m_heading" => %{"cell" => "Valley Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 15
      },
      %{
        goal_number: 5,
        code: "G5-M2",
        description: "% of students reporting “Engaged” or “Committed” on ND Engagement Survey",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.3"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D31", "raw" => "0.3"},
          "target_18m" => %{"cell" => "Valley Goals!H31", "raw" => nil},
          "target_36m" => %{"cell" => "Valley Goals!P31", "raw" => "> 35%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 16
      },
      %{
        goal_number: 5,
        code: "G5-M3",
        description:
          "Percentage of students reporting \"Often\" across the four areas of student agency on the AVID student agency survey",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.15"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D32", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H32", "raw" => "0.15"},
          "target_36m" => %{"cell" => "Valley Goals!P32", "raw" => "0.3"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 17
      },
      %{
        goal_number: 5,
        code: "G5-M4",
        description: "Percentage of chronic absenteeism",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.44"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D33", "raw" => "0.44"},
          "target_18m" => %{"cell" => "Valley Goals!H33", "raw" => "< 40%"},
          "target_36m" => %{"cell" => "Valley Goals!P33", "raw" => "< 35%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 18
      },
      %{
        goal_number: 5,
        code: "G5-M5",
        description: "Percentage of chronic absenteeism for low-income students",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.53"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D34", "raw" => "0.53"},
          "target_18m" => %{"cell" => "Valley Goals!H34", "raw" => "< 49%"},
          "target_36m" => %{"cell" => "Valley Goals!P34", "raw" => "< 45%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 19
      },
      %{
        goal_number: 6,
        code: "G6-M1",
        description:
          "% of students placed into Flex sessions based on academic/behavioral data (RTI Scheduler)",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D38", "raw" => "< 50%"},
          "target_18m" => %{"cell" => "Valley Goals!H38", "raw" => "> 70%"},
          "target_36m" => %{"cell" => "Valley Goals!P38", "raw" => nil},
          "review_18m_heading" => %{"cell" => "Valley Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 20
      },
      %{
        goal_number: 6,
        code: "G6-M2",
        description: "% of teachers consistently using RTI Scheduler",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D39", "raw" => "< 50%"},
          "target_18m" => %{"cell" => "Valley Goals!H39", "raw" => "> 70%"},
          "target_36m" => %{"cell" => "Valley Goals!P39", "raw" => nil},
          "review_18m_heading" => %{"cell" => "Valley Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 21
      },
      %{
        goal_number: 6,
        code: "G6-M3",
        description:
          "Flex sessions focused on Essential Standards for Intervention or Guided Practice",
        category: :systems,
        unit: :text,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D40", "raw" => "< 33%"},
          "target_18m" => %{"cell" => "Valley Goals!H40", "raw" => nil},
          "target_36m" => %{"cell" => "Valley Goals!P40", "raw" => "> 50%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 22
      },
      %{
        goal_number: 6,
        code: "G6-M4",
        description:
          "% of Math and ELA Flex sessions systematically utilizing NAVVY aligned to Essential Standards",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D41", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H41", "raw" => nil},
          "target_36m" => %{"cell" => "Valley Goals!P41", "raw" => "> 80%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 23
      },
      %{
        goal_number: 6,
        code: "G6-M5",
        description: "% of students demonstrating proficiency on essential standards",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D42", "raw" => "< 50%"},
          "target_18m" => %{"cell" => "Valley Goals!H42", "raw" => nil},
          "target_36m" => %{"cell" => "Valley Goals!P42", "raw" => "> 60%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 24
      },
      %{
        goal_number: 7,
        code: "G7-M1",
        description:
          "% of teachers reporting \"Sometimes\" across the four areas of collective educator agency",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D46", "raw" => "0"},
          "target_18m" => %{"cell" => "Valley Goals!H46", "raw" => "> 15%"},
          "target_36m" => %{"cell" => "Valley Goals!P46", "raw" => "> 30%"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I45", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 25
      },
      %{
        goal_number: 7,
        code: "G7-M2",
        description:
          "Create and share a school-wide Decision-Making Matrix and Loose-Tight Expectations Framework",
        category: :systems,
        unit: :text,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Valley Goals!D47", "raw" => "Not Created"},
          "target_18m" => %{"cell" => "Valley Goals!H47", "raw" => "Created"},
          "target_36m" => %{"cell" => "Valley Goals!P47", "raw" => "Utilized"},
          "review_18m_heading" => %{"cell" => "Valley Goals!I45", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 26
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 1, "Valley Goals!E4"},
      {"G1-M1", "sum_26", 2, "Valley Goals!F4"},
      {"G1-M2", "spr_26", 0, "Valley Goals!E5"},
      {"G1-M2", "sum_26", 3, "Valley Goals!F5"},
      {"G1-M3", "spr_26", :not_applicable, "Valley Goals!E6"},
      {"G1-M3", "sum_26", 2, "Valley Goals!F6"},
      {"G1-M4", "spr_26", 2, "Valley Goals!E7"},
      {"G1-M4", "sum_26", 2, "Valley Goals!F7"},
      {"G2-M1", "spr_26", 1, "Valley Goals!E11"},
      {"G2-M1", "sum_26", 2, "Valley Goals!F11"},
      {"G2-M2", "spr_26", 0, "Valley Goals!E12"},
      {"G2-M2", "sum_26", 3, "Valley Goals!F12"},
      {"G2-M3", "spr_26", :not_applicable, "Valley Goals!E13"},
      {"G2-M3", "sum_26", 2, "Valley Goals!F13"},
      {"G2-M4", "spr_26", 2, "Valley Goals!E14"},
      {"G2-M4", "sum_26", 2, "Valley Goals!F14"},
      {"G3-M1", "spr_26", 2, "Valley Goals!E18"},
      {"G3-M1", "sum_26", 2, "Valley Goals!F18"},
      {"G3-M2", "spr_26", 2, "Valley Goals!E19"},
      {"G3-M2", "sum_26", 2, "Valley Goals!F19"},
      {"G3-M3", "spr_26", 2, "Valley Goals!E20"},
      {"G3-M3", "sum_26", 2, "Valley Goals!F20"},
      {"G3-M4", "spr_26", 2, "Valley Goals!E21"},
      {"G3-M4", "sum_26", 2, "Valley Goals!F21"},
      {"G3-M5", "spr_26", 2, "Valley Goals!E22"},
      {"G3-M5", "sum_26", 2, "Valley Goals!F22"},
      {"G4-M1", "spr_26", 1, "Valley Goals!E26"},
      {"G4-M1", "sum_26", 2, "Valley Goals!F26"},
      {"G5-M1", "spr_26", 1, "Valley Goals!E30"},
      {"G5-M1", "sum_26", 2, "Valley Goals!F30"},
      {"G5-M2", "spr_26", 2, "Valley Goals!E31"},
      {"G5-M2", "sum_26", 2, "Valley Goals!F31"},
      {"G5-M3", "spr_26", 2, "Valley Goals!E32"},
      {"G5-M3", "sum_26", 2, "Valley Goals!F32"},
      {"G5-M4", "spr_26", 1, "Valley Goals!E33"},
      {"G5-M4", "sum_26", 1, "Valley Goals!F33"},
      {"G5-M5", "spr_26", 1, "Valley Goals!E34"},
      {"G5-M5", "sum_26", 1, "Valley Goals!F34"},
      {"G6-M1", "spr_26", 2, "Valley Goals!E38"},
      {"G6-M1", "sum_26", 2, "Valley Goals!F38"},
      {"G6-M2", "spr_26", 2, "Valley Goals!E39"},
      {"G6-M2", "sum_26", 2, "Valley Goals!F39"},
      {"G6-M3", "spr_26", 1, "Valley Goals!E40"},
      {"G6-M3", "sum_26", 2, "Valley Goals!F40"},
      {"G6-M4", "spr_26", :not_applicable, "Valley Goals!E41"},
      {"G6-M4", "sum_26", 2, "Valley Goals!F41"},
      {"G6-M5", "spr_26", 1, "Valley Goals!E42"},
      {"G6-M5", "sum_26", 2, "Valley Goals!F42"},
      {"G7-M1", "spr_26", 1, "Valley Goals!E46"},
      {"G7-M1", "sum_26", 1, "Valley Goals!F46"},
      {"G7-M2", "spr_26", 2, "Valley Goals!E47"},
      {"G7-M2", "sum_26", 3, "Valley Goals!F47"}
    ]
  end

  @doc "Annual Proficient-or-Advanced targets from the PDF (pp.25-26)."
  def annual_assessment_goals do
    [
      {"2025-2026", "0.37", "0.31"},
      {"2026-2027", "0.41", "0.35"},
      {"2027-2028", "0.44", "0.39"},
      {"2028-2029", "0.48", "0.43"},
      {"2029-2030", "0.52", "0.47"},
      {"2030-2031", "0.55", "0.51"}
    ]
    |> Enum.flat_map(fn {year, ela, math} -> [{year, :ela, ela}, {year, :math, math}] end)
    |> Enum.map(fn {year, subject, target} ->
      %{
        school_year: year,
        subject: subject,
        target_value: Decimal.new(target),
        measure: :proficient_or_advanced,
        includes_alternate: true,
        source_ref:
          "North Dakota - ND First Schools.pdf pp.25-26 (Measure 2 Report Card Annual Proficiency Targets, assumed 2025-2026 through 2030-2031 sequence)"
      }
    end)
  end
end
