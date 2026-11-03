defmodule Emisint.Improvement.Seeds.Oberon do
  @moduledoc """
  Oberon Elementary School definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Oberon Goals", and the ND First
  schools PDF (pp.23-24). Every value cites its source cell.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Oberon Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-18]

  def school do
    %{
      name: "Oberon Elementary School",
      short_name: "Oberon",
      slug: "oberon-elementary",
      state: "ND",
      state_entity_id: "0301662261",
      district_name: "Oberon Public School District",
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
        "ND First School MOU Goal Overview.xlsx: 'Oberon Goals' and 'Performance-Based Payment'. Progress-monitoring link listed as TBD (Oberon Goals!B1)."
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title: "Literacy Growth",
        description:
          "Literacy Growth: Oberon Elementary School will increase literacy proficiency while strengthening vertically aligned literacy implementation across grade levels and reducing the percentage of students performing at the novice level",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 5, "fal_26" => 7},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Mathematics Growth",
        description:
          "Mathematics Growth: Oberon Elementary School will increase mathematics proficiency while strengthening vertically aligned instructional systems, reducing the percentage of students performing at the novice level, and increasing instructional continuity necessary for sustained mathematics growth.",
        implementation_steps: %{"spr_26" => 4, "sum_26" => 8, "fal_26" => 7},
        source_ref: "#{@sheet}!B11; steps E11:G11"
      },
      %{
        number: 3,
        title: "Student Attendance",
        description:
          "Student Attendance: Oberon Elementary School will reduce chronic absenteeism and strengthen instructional continuity through relationship-based, rural-responsive attendance systems that increase consistent student participation in instruction.",
        implementation_steps: %{"spr_26" => 3, "sum_26" => 5, "fal_26" => 6},
        source_ref: "#{@sheet}!B18; steps E18:G18"
      },
      %{
        number: 4,
        title: "Student Engagement",
        description:
          "Student Engagement: Oberon Elementary School will strengthen student engagement and school connectedness by increasing meaningful participation in learning, improving student voice systems, and expanding culturally responsive and relationship-based instructional practices.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 12, "fal_26" => 7},
        source_ref: "#{@sheet}!B25; steps E25:G25"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description: "Increase Proficient & Advanced ELA Data",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.16"),
        target_18m: Decimal.new("0.23"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D4", "raw" => "0.16"},
          "target_18m" => %{"cell" => "Oberon Goals!H4", "raw" => "0.23"},
          "target_36m" => %{"cell" => "Oberon Goals!P4", "raw" => "0.3"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description: "Reduce Novice ELA Data",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.36"),
        target_18m: Decimal.new("0.29"),
        target_36m: Decimal.new("0.22"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D5", "raw" => "0.36"},
          "target_18m" => %{"cell" => "Oberon Goals!H5", "raw" => "0.29"},
          "target_36m" => %{"cell" => "Oberon Goals!P5", "raw" => "0.22"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 2
      },
      %{
        goal_number: 1,
        code: "G1-M3",
        description: "Percentage of teacher participation in literacy data cycles",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("1"),
        target_36m: Decimal.new("1"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D6", "raw" => nil},
          "target_18m" => %{"cell" => "Oberon Goals!H6", "raw" => "1"},
          "target_36m" => %{"cell" => "Oberon Goals!P6", "raw" => "1"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [],
        position: 3
      },
      %{
        goal_number: 1,
        code: "G1-M4",
        description:
          "Percentage of grade-level participation in literacy vertical alignment meetings",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("1"),
        target_36m: Decimal.new("1"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D7", "raw" => nil},
          "target_18m" => %{"cell" => "Oberon Goals!H7", "raw" => "1"},
          "target_36m" => %{"cell" => "Oberon Goals!P7", "raw" => "1"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [],
        position: 4
      },
      %{
        goal_number: 1,
        code: "G1-M5",
        description: "Percentage of teachers completing MTSS cycles",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.1"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D8", "raw" => "0.1"},
          "target_18m" => %{"cell" => "Oberon Goals!H8", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Oberon Goals!P8", "raw" => "0.5"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 5
      },
      %{
        goal_number: 1,
        code: "G1-M6",
        description:
          "Percentage of teachers using student exemplars aligned to priority literacy standards",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.12"),
        target_18m: Decimal.new("0.24"),
        target_36m: Decimal.new("0.36"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D9", "raw" => "0.12"},
          "target_18m" => %{"cell" => "Oberon Goals!H9", "raw" => "0.24"},
          "target_36m" => %{"cell" => "Oberon Goals!P9", "raw" => "0.36"},
          "review_18m_heading" => %{
            "cell" => "Oberon Goals!I3",
            "raw" => "18-Month Review Rating"
          },
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 6
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description: "% of students with Proficient & Advanced Math Data",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.04"),
        target_18m: Decimal.new("0.11"),
        target_36m: Decimal.new("0.18"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D13", "raw" => "0.04"},
          "target_18m" => %{"cell" => "Oberon Goals!H13", "raw" => "0.11"},
          "target_36m" => %{"cell" => "Oberon Goals!P13", "raw" => "0.18"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 7
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description: "% of students Novice Math Data",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.65"),
        target_18m: Decimal.new("0.58"),
        target_36m: Decimal.new("0.51"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D14", "raw" => "0.65"},
          "target_18m" => %{"cell" => "Oberon Goals!H14", "raw" => "0.58"},
          "target_36m" => %{"cell" => "Oberon Goals!P14", "raw" => "0.51"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 8
      },
      %{
        goal_number: 2,
        code: "G2-M3",
        description: "Percentage of teachers completing MTSS cycles",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.1"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D15", "raw" => "0.1"},
          "target_18m" => %{"cell" => "Oberon Goals!H15", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Oberon Goals!P15", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 9
      },
      %{
        goal_number: 2,
        code: "G2-M4",
        description:
          "Percentage of teachers using student exemplars aligned to priority mathematics standards",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.12"),
        target_18m: Decimal.new("0.24"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D16", "raw" => "0.12"},
          "target_18m" => %{"cell" => "Oberon Goals!H16", "raw" => "0.24"},
          "target_36m" => %{"cell" => "Oberon Goals!P16", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 10
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description: "Average attendance percentage",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.8"),
        target_18m: Decimal.new("0.87"),
        target_36m: Decimal.new("0.9"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D20", "raw" => "0.8"},
          "target_18m" => %{"cell" => "Oberon Goals!H20", "raw" => "0.87"},
          "target_36m" => %{"cell" => "Oberon Goals!P20", "raw" => "0.9"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 11
      },
      %{
        goal_number: 3,
        code: "G3-M2",
        description: "Chronic absenteeism percentage",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D21", "raw" => "60-64%"},
          "target_18m" => %{"cell" => "Oberon Goals!H21", "raw" => "50-54%"},
          "target_36m" => %{"cell" => "Oberon Goals!P21", "raw" => "40-44%"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 12
      },
      %{
        goal_number: 3,
        code: "G3-M3",
        description: "% of students attending 90% or more of instructional days",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.75"),
        target_36m: Decimal.new("0.9"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D22", "raw" => "60-64%"},
          "target_18m" => %{"cell" => "Oberon Goals!H22", "raw" => "0.75"},
          "target_36m" => %{"cell" => "Oberon Goals!P22", "raw" => "0.9"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 13
      },
      %{
        goal_number: 3,
        code: "G3-M4",
        description: "Percentage of attendance gaps between identified student groups",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.3"),
        target_18m: Decimal.new("0.25"),
        target_36m: Decimal.new("0.2"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D23", "raw" => "0.3"},
          "target_18m" => %{"cell" => "Oberon Goals!H23", "raw" => "0.25"},
          "target_36m" => %{"cell" => "Oberon Goals!P23", "raw" => "0.2"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I19", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 14
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description: "% of students reporting as Emotionally Committed",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D27", "raw" => "45-49%"},
          "target_18m" => %{"cell" => "Oberon Goals!H27", "raw" => "55-60%"},
          "target_36m" => %{"cell" => "Oberon Goals!P27", "raw" => "60-65%"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 15
      },
      %{
        goal_number: 4,
        code: "G4-M2",
        description: "% of students reporting as Emotionally Compliant",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D28", "raw" => "40-44%"},
          "target_18m" => %{"cell" => "Oberon Goals!H28", "raw" => "50-55%"},
          "target_36m" => %{"cell" => "Oberon Goals!P28", "raw" => "55-60%"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 16
      },
      %{
        goal_number: 4,
        code: "G4-M3",
        description: "% of students reporting as Emotionally Disengaged",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D29", "raw" => "6-10%"},
          "target_18m" => %{"cell" => "Oberon Goals!H29", "raw" => "4-8%"},
          "target_36m" => %{"cell" => "Oberon Goals!P29", "raw" => "3-8%"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 17
      },
      %{
        goal_number: 4,
        code: "G4-M4",
        description: "# of behavioral referrals",
        category: :student_outcome,
        unit: :count,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("50"),
        target_18m: Decimal.new("45"),
        target_36m: Decimal.new("40"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D30", "raw" => "50"},
          "target_18m" => %{"cell" => "Oberon Goals!H30", "raw" => "45"},
          "target_36m" => %{"cell" => "Oberon Goals!P30", "raw" => "40"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 18
      },
      %{
        goal_number: 4,
        code: "G4-M5",
        description: "% of classrooms indicating student engagement and instructional relevance",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.3"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("0.9"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D31", "raw" => "0.3"},
          "target_18m" => %{"cell" => "Oberon Goals!H31", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Oberon Goals!P31", "raw" => "0.9"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 19
      },
      %{
        goal_number: 4,
        code: "G4-M6",
        description: "% of PLCs focused on student voice and engagement practices",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("1"),
        target_36m: Decimal.new("1"),
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D32", "raw" => "0"},
          "target_18m" => %{"cell" => "Oberon Goals!H32", "raw" => "1"},
          "target_36m" => %{"cell" => "Oberon Goals!P32", "raw" => "1"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 20
      },
      %{
        goal_number: 4,
        code: "G4-M7",
        description:
          "Number of teachers who implement culturally responsive, experiential learning practices in their classrooms",
        category: :systems,
        unit: :count,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Oberon Goals!D33", "raw" => "0"},
          "target_18m" => %{"cell" => "Oberon Goals!H33", "raw" => "2026-02-03"},
          "target_36m" => %{"cell" => "Oberon Goals!P33", "raw" => "2026-02-03"},
          "review_18m_heading" => %{"cell" => "Oberon Goals!I26", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :source_value_is_date],
        position: 21
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 2, "Oberon Goals!E4"},
      {"G1-M1", "sum_26", 2, "Oberon Goals!F4"},
      {"G1-M2", "spr_26", 2, "Oberon Goals!E5"},
      {"G1-M2", "sum_26", 2, "Oberon Goals!F5"},
      {"G1-M3", "spr_26", 1, "Oberon Goals!E6"},
      {"G1-M3", "sum_26", 2, "Oberon Goals!F6"},
      {"G1-M4", "spr_26", 1, "Oberon Goals!E7"},
      {"G1-M4", "sum_26", 2, "Oberon Goals!F7"},
      {"G1-M5", "spr_26", 1, "Oberon Goals!E8"},
      {"G1-M5", "sum_26", 1, "Oberon Goals!F8"},
      {"G1-M6", "spr_26", 1, "Oberon Goals!E9"},
      {"G1-M6", "sum_26", 2, "Oberon Goals!F9"},
      {"G2-M1", "spr_26", 2, "Oberon Goals!E13"},
      {"G2-M1", "sum_26", 2, "Oberon Goals!F13"},
      {"G2-M2", "spr_26", 2, "Oberon Goals!E14"},
      {"G2-M2", "sum_26", 2, "Oberon Goals!F14"},
      {"G2-M3", "spr_26", 1, "Oberon Goals!E15"},
      {"G2-M3", "sum_26", 1, "Oberon Goals!F15"},
      {"G2-M4", "spr_26", 1, "Oberon Goals!E16"},
      {"G2-M4", "sum_26", 2, "Oberon Goals!F16"},
      {"G3-M1", "spr_26", 1, "Oberon Goals!E20"},
      {"G3-M1", "sum_26", 2, "Oberon Goals!F20"},
      {"G3-M2", "spr_26", 1, "Oberon Goals!E21"},
      {"G3-M2", "sum_26", 2, "Oberon Goals!F21"},
      {"G3-M3", "spr_26", 1, "Oberon Goals!E22"},
      {"G3-M3", "sum_26", 2, "Oberon Goals!F22"},
      {"G3-M4", "spr_26", 1, "Oberon Goals!E23"},
      {"G3-M4", "sum_26", 1, "Oberon Goals!F23"},
      {"G4-M1", "spr_26", 2, "Oberon Goals!E27"},
      {"G4-M1", "sum_26", 2, "Oberon Goals!F27"},
      {"G4-M2", "spr_26", 2, "Oberon Goals!E28"},
      {"G4-M2", "sum_26", 2, "Oberon Goals!F28"},
      {"G4-M3", "spr_26", 2, "Oberon Goals!E29"},
      {"G4-M3", "sum_26", 2, "Oberon Goals!F29"},
      {"G4-M4", "spr_26", 1, "Oberon Goals!E30"},
      {"G4-M4", "sum_26", 2, "Oberon Goals!F30"},
      {"G4-M5", "spr_26", 1, "Oberon Goals!E31"},
      {"G4-M5", "sum_26", 2, "Oberon Goals!F31"},
      {"G4-M6", "spr_26", 1, "Oberon Goals!E32"},
      {"G4-M6", "sum_26", 2, "Oberon Goals!F32"},
      {"G4-M7", "spr_26", 1, "Oberon Goals!E33"},
      {"G4-M7", "sum_26", 1, "Oberon Goals!F33"}
    ]
  end

  @doc "Annual Proficient-or-Advanced targets from the PDF (pp.23-24)."
  def annual_assessment_goals do
    [
      {"2018-2019", "0.06", "0.06"},
      {"2019-2020", "0.11", "0.11"},
      {"2020-2021", "0.17", "0.17"},
      {"2021-2022", "0.11", "0.11"},
      {"2022-2023", "0.17", "0.17"},
      {"2023-2024", "0.22", "0.22"}
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
          "North Dakota - ND First Schools.pdf p.23 (Annual Proficiency Targets; displayed historical goal period 2018-2019 through 2023-2024)"
      }
    end)
  end
end
