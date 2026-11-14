defmodule Emisint.Improvement.Seeds.CannonBall do
  @moduledoc """
  Cannon Ball Elementary School definitions for the ND First MOU, generated
  from `ND First School MOU Goal Overview.xlsx`, sheet "Solen Goals", and the
  ND First schools PDF (pp.4-6). Every value cites its source cell.

  Confirmed by the user (recorded in PLAN_nd_first.md, November 9, 2026): the workbook's “Solen” sheet (“Solen Goals”) represents the Cannon Ball ND FIRST participant. The sheet's goals are written for Solen Public School
  District and its schools; this participant's record is Cannon Ball
  Elementary School (InstitutionID 4300312781, Solen Public School District
  43003, as published in every imported ND Insights file). Solen district
  results are never used for it. Solen High School (InstitutionID
  4300380363) is its building (`Seeds.SolenHigh`, user decision of November
  12, 2026), with its own results; the grade-10 goals are compared there.

  Values that are not a plain number in the metric's unit (for example
  "< 10%" or an Excel date) are kept verbatim in `source_values`, flagged,
  and left unset in the numeric fields.
  """

  # "Solen Goals" metric wording (Solen Goals!B4:B18), used to match only
  # the expected metric.
  @g1_m1 "% of students in Grades 3-5 that demonstrate proficiency on North Dakota Reading State Assessment"
  @g1_m2 "% of students in Grades 6-8 that demonstrate proficiency on North Dakota Reading State Assessment"
  @g1_m4 "% of students in Grades 3-5 performing at the Novice level in reading"
  @g1_m5 "% of students in Grades 6-8 performing at the Novice level in reading"
  @g2_m1 "% of students in Grades 3-5 demonstrating expected annual growth"
  @g2_m2 "% of students in Grades 6-8 demonstrating expected annual growth"
  @g2_m4 "% of students in Grades 3-5 performing at a Novice level"
  @g2_m5 "% of students in Grades 6-8 performing at a Novice level"

  @achievement_confirmation "Confirmed by the user (November 12, 2026): “demonstrate proficiency” means Proficient or Advanced, and the “Solen Goals” achievement goals count the Combined assessment (ND A+ Summative or NDAA, as the plan's annual targets do, p.4)."
  @growth_provisional "Provisional, for dashboard reference (user decision, November 12, 2026): math “expected annual growth” is read as Meets or Exceeds growth expectations (derived from the published Meets and Exceeds ranges). It isn't a confirmed definition, and it doesn't record a review result."

  @doc "Metric wording used by Solen High School's grade-10 comparisons."
  def grade_10_metrics,
    do: %{
      "G1-M3" =>
        "% of students in Grade 10 that demonstrate proficiency on North Dakota Reading State Assessment",
      "G1-M6" => "% of students in Grades 10 performing at the Novice level in reading",
      "G2-M3" => "% of students in Grade 10 demonstrating expected annual growth",
      "G2-M6" => "% of students in Grade 10 performing at a Novice level"
    }

  def achievement_confirmation, do: @achievement_confirmation
  def growth_provisional, do: @growth_provisional

  @doc "Cannon Ball's main record is a school; Solen High School is its building."
  def record_kind, do: :school

  @doc "Solen High School: the building whose dashboard carries the grade-10 goals."
  def buildings, do: [Emisint.Improvement.Seeds.SolenHigh]

  @sheet "Solen Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-18]

  def school do
    %{
      name: "Cannon Ball Elementary School",
      short_name: "Cannon Ball",
      slug: "cannon-ball-elementary",
      state: "ND",
      state_entity_id: "4300312781",
      district_name: "Solen Public School District",
      grade_span: nil,
      active: true
    }
  end

  @doc "The workbook-to-participant mapping, as confirmed by the user."
  def participant_mapping,
    do: %{
      workbook_sheet: @sheet,
      workbook_row_name: "Solen",
      participant: "Cannon Ball",
      confirmation:
        "Confirmed by the user (recorded in PLAN_nd_first.md, November 9, 2026): the workbook's “Solen” sheet (“Solen Goals”) represents the Cannon Ball ND FIRST participant."
    }

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
        "ND First School MOU Goal Overview.xlsx: 'Solen Goals' (the Cannon Ball participant, confirmed by the user) and 'Performance-Based Payment' row 5. School plan link listed as TBD (Solen Goals!B1)."
    }
  end

  @doc """
  The first school year whose results fall inside the plan: the reporting
  periods start with Spr '26 (Solen Goals!E3), and the PDF's long-term
  academic goals run 2025–2026 through 2030–2031 (p.4).
  """
  def plan_start_year, do: "2025-2026"

  @doc """
  How Cannon Ball's goals are compared with published ND Insights results
  (`Emisint.Improvement.ResultGoals`); see `Seeds.FortYates.comparison/0`
  for the shape. The grade 3–5 and 6–8 goals are compared with Cannon Ball
  Elementary's own grade rows as grade-group references (user decisions of
  November 12, 2026: Proficient or Advanced, Combined assessment; math growth
  as Meets or Exceeds, provisionally); the grade-10 goals are compared on
  Solen High School's dashboard (`Seeds.SolenHigh`). The PDF's annual
  Proficient-or-Advanced targets (pp.4-5) are compared, each with the same
  school year's All Grades result.
  """
  def comparison do
    %{
      plan_start_year: plan_start_year(),
      workbook: [
        {"G1-M1", @g1_m1, :achievement, "Reading", :proficient_or_advanced,
         "Reading Proficient or Advanced, grades 3–5", %{grades: ~w(3 4 5), group: "grades 3–5"}},
        {"G1-M2", @g1_m2, :achievement, "Reading", :proficient_or_advanced,
         "Reading Proficient or Advanced, grades 6–8", %{grades: ~w(6 7 8), group: "grades 6–8"}},
        {"G1-M4", @g1_m4, :achievement, "Reading", "Novice", "Reading Novice, grades 3–5",
         %{grades: ~w(3 4 5), group: "grades 3–5"}},
        {"G1-M5", @g1_m5, :achievement, "Reading", "Novice", "Reading Novice, grades 6–8",
         %{grades: ~w(6 7 8), group: "grades 6–8"}},
        {"G2-M4", @g2_m4, :achievement, "Math", "Novice", "Math Novice, grades 3–5",
         %{grades: ~w(3 4 5), group: "grades 3–5"}},
        {"G2-M5", @g2_m5, :achievement, "Math", "Novice", "Math Novice, grades 6–8",
         %{grades: ~w(6 7 8), group: "grades 6–8"}},
        {"G2-M1", @g2_m1, :growth, "Math", :meets_or_exceeds,
         "Math Meets or Exceeds growth expectations, grades 3–5",
         %{grades: ~w(3 4 5), group: "grades 3–5"}},
        {"G2-M2", @g2_m2, :growth, "Math", :meets_or_exceeds,
         "Math Meets or Exceeds growth expectations, grades 6–8",
         %{grades: ~w(6 7 8), group: "grades 6–8"}}
      ],
      # Confirmed by the user (November 12, 2026).
      confirmed: %{assessment_type: "Comp"},
      confirmations:
        Map.new(~w(G1-M1 G1-M2 G1-M4 G1-M5 G2-M4 G2-M5), &{&1, @achievement_confirmation}),
      provisional: Map.new(~w(G2-M1 G2-M2), &{&1, @growth_provisional}),
      assumptions: %{},
      grade_reference: nil,
      matching:
        "Cannon Ball Elementary publishes grades 3–8 (checked in every imported Assessment Performance file, 2021-22 through 2024-25; some grades are unpublished in some years), so the “Solen Goals” grade 3–5 and grade 6–8 goals are compared on this dashboard. Insights publishes each grade and All Grades, never these grade bands, so each published grade is compared with its band's target for reference only (“grade-group reference”): one grade is not the band's result, and grades are never averaged into one. “Demonstrate proficiency” (G1-M1, G1-M2) is Proficient or Advanced (derived) and the Novice goals (G1-M4, G1-M5 reading; G2-M4, G2-M5 under Goal 2, “Mathematics Growth”) are Novice, Combined assessment (confirmed by the user, November 12, 2026). Math “expected annual growth” (G2-M1, G2-M2) is Meets or Exceeds growth expectations (derived), provisionally for dashboard reference (growth is published from grade 4). The grade-10 goals (G1-M3, G1-M6, G2-M3, G2-M6) are compared on Solen High School's dashboard with its own Grade 10 results; Cannon Ball Elementary has no grade 10. The All Grades row is compared only with the plan's annual Proficient-or-Advanced targets for the same school year. G7-M1 and the Systems metrics are local measures. Student groups are not matched.",
      assumptions_text:
        "No assumptions are applied for Cannon Ball Elementary School. Confirmed by the user (November 12, 2026): “demonstrate proficiency” means Proficient or Advanced, and the achievement goals count the Combined assessment. Provisional for dashboard reference: math “expected annual growth” is read as Meets or Exceeds growth expectations. Grade-group references compare single grades with their band's target and are labeled as references, not band results.",
      assumptions_short:
        "Cannon Ball: Combined assessment and Proficient or Advanced confirmed; math growth as Meets or Exceeds is provisional. Single grades are compared with their grade band's target for reference only.",
      section_notes: %{
        achievement:
          "Cannon Ball Elementary's own results (InstitutionID 4300312781). Grades 3–5 and 6–8 carry grade-group reference colors against the “Solen Goals” band targets (G1-M1/G1-M2 Proficient or Advanced, G1-M4/G1-M5 reading Novice, G2-M4/G2-M5 math Novice). The All Grades Proficient or Advanced cell shows the annual target for the same school year, where one exists. Grade-10 goals are on Solen High School's dashboard.",
        growth:
          "Math Meets or Exceeds (derived) carries grade-group reference colors against G2-M1 (grades 3–5) and G2-M2 (grades 6–8): a provisional reading of “expected annual growth”, for dashboard reference. Growth is published from grade 4, so grade 3 has none. ELA growth has no school goal.",
        engagement: "The “Solen Goals” sheet has no Engagement Survey metric."
      },
      annual_years: %{
        status: :stated,
        location: "North Dakota - ND First Schools.pdf p.4",
        excerpt:
          "“Long-Term Academic Goals: 2025–2026 through 2030–2031”; “Annual Proficiency Targets – All Students”, listed by year: “2025–2026: ELA 13%; Mathematics 7%.” through “2030–2031: ELA 38%; Mathematics 34%.”"
      },
      annual_note:
        "The continuous improvement plan (pp.4-5) lists annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031, each stated with its year. Each target is compared only with Cannon Ball Elementary's result for the same year.",
      report_notes: [
        "Workbook provenance [W]. Baselines, targets and Spring/Summer '26 ratings were imported from “ND First School MOU Goal Overview.xlsx” (sheet “Solen Goals”, the Cannon Ball participant as confirmed by the user); the cell is shown with each value. The workbook does not record who entered each value. Values marked “as written” are shown exactly as in the workbook.",
        "Scope. The sheet's goals are written for Solen Public School District and its schools (Cannon Ball Elementary, Solen Jr. High and Solen High School). State results on this page are Cannon Ball Elementary School's own (InstitutionID 4300312781; grades 3–8 published). Solen High School (4300380363; grade 10 published) is this participant's building: its own results and the grade-10 goals are on its dashboard and report. Solen district (43003) results are never used.",
        "Still to confirm. The grade-band (3–5, 6–8) results themselves: Insights doesn't publish them, so grade rows carry reference colors only; G2-M1–G2-M3's Meets-or-Exceeds reading of “expected annual growth” is provisional; G2-M3 (grade 10 growth) has no published counterpart. G5-M1's baseline and targets (Solen Goals!D30, H30, P30) are stored as dates and are flagged; G7-M2's baseline is “< 10%”; G2-M1–G2-M3 have no baseline; Goals 2–7's 18-month column (I12, I21, I25, I29, I33, I37) is headed “Target Check” rather than “18-Month Review Rating”.",
        "Annual targets. North Dakota - ND First Schools.pdf pp.4-5 lists Cannon Ball Elementary School's annual Proficient-or-Advanced targets for 2025-2026 through 2030-2031 (ELA and mathematics, ND A+ Summative or NDAA for eligible students)."
      ]
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title: "Literacy Growth",
        description:
          "Literacy Growth: Solen Public School District will increase the percentage of students demonstrating measurable annual growth in literacy and increase the percentage of students performing at or above grade-level expectations.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Mathematics Growth",
        description:
          "Mathematics Growth: Solen Public School District will increase the percentage of students demonstrating measurable annual growth in mathematics and reduce the percentage of students performing below grade-level expectations.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B11; steps E11:G11"
      },
      %{
        number: 3,
        title:
          "Instructional Continuity, MTSS Cycle Integrity, and Instructional System Stability",
        description:
          "Instructional Continuity, MTSS Cycle Integrity, and Instructional System Stability: Cannon Ball Elementary School, Solen Jr. High and Solen High School will strengthen MTSS implementation by protecting intervention cycles, ensuring consistent progress monitoring, and using multiple data points to guide instructional adjustments and tier movements. Students will receive adequate time and instructional support for interventions to demonstrate measurable impact.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B20; steps E20:G20"
      },
      %{
        number: 4,
        title: "Strengthen Shared Leadership and Instructional Decision-Making",
        description:
          "Strengthen Shared Leadership and Instructional Decision-Making: Solen School District will strengthen shared instructional leadership by expanding structured opportunities for teacher participation in data analysis, intervention planning, and instructional decision-making within MTSS processes.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 1},
        source_ref: "#{@sheet}!B24; steps E24:G24"
      },
      %{
        number: 5,
        title: "Consistent Implementation of Schoolwide Expectations",
        description:
          "Consistent Implementation of Schoolwide Expectations: Cannon Ball Elementary, Solen Junior High and Senior High School will strengthen consistent implementation of schoolwide expectations by reinforcing shared instructional practices and establishing structures that support staff alignment across classrooms.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B28; steps E28:G28"
      },
      %{
        number: 6,
        title: "Instructional Coherence and Protection of Academic Learning",
        description:
          "Instructional Coherence and Protection of Academic Learning: Schools in Solen Public School District will strengthen instructional coherence by establishing consistent classroom routines and shared instructional structures that protect academic learning time across all classrooms.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B32; steps E32:G32"
      },
      %{
        number: 7,
        title: "Strengthen Academic Identity and Student Ownership of Learning",
        description:
          "Strengthen Academic Identity and Student Ownership of Learning: Solen Public School District will strengthen students’ academic identity by defining and reinforcing a shared vision of what it means to be a successful learner and by supporting students in developing ownership of their learning.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 1, "fal_26" => 2},
        source_ref: "#{@sheet}!B36; steps E36:G36"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description:
          "% of students in Grades 3-5 that demonstrate proficiency on North Dakota Reading State Assessment",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.11"),
        target_18m: Decimal.new("0.18"),
        target_36m: Decimal.new("0.33"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D4", "raw" => "0.11"},
          "target_18m" => %{"cell" => "Solen Goals!H4", "raw" => "0.18"},
          "target_36m" => %{"cell" => "Solen Goals!P4", "raw" => "0.33"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description:
          "% of students in Grades 6-8 that demonstrate proficiency on North Dakota Reading State Assessment",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.03"),
        target_18m: Decimal.new("0.09"),
        target_36m: Decimal.new("0.27"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D5", "raw" => "0.03"},
          "target_18m" => %{"cell" => "Solen Goals!H5", "raw" => "0.09"},
          "target_36m" => %{"cell" => "Solen Goals!P5", "raw" => "0.27"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 2
      },
      %{
        goal_number: 1,
        code: "G1-M3",
        description:
          "% of students in Grade 10 that demonstrate proficiency on North Dakota Reading State Assessment",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.2"),
        target_36m: Decimal.new("0.33"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D6", "raw" => "0"},
          "target_18m" => %{"cell" => "Solen Goals!H6", "raw" => "0.2"},
          "target_36m" => %{"cell" => "Solen Goals!P6", "raw" => "0.33"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 3
      },
      %{
        goal_number: 1,
        code: "G1-M4",
        description: "% of students in Grades 3-5 performing at the Novice level in reading",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.59"),
        target_18m: Decimal.new("0.39"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D7", "raw" => "0.59"},
          "target_18m" => %{"cell" => "Solen Goals!H7", "raw" => "0.39"},
          "target_36m" => %{"cell" => "Solen Goals!P7", "raw" => "0.3"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 4
      },
      %{
        goal_number: 1,
        code: "G1-M5",
        description: "% of students in Grades 6-8 performing at the Novice level in reading",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.89"),
        target_18m: Decimal.new("0.41"),
        target_36m: Decimal.new("0.29"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D8", "raw" => "0.89"},
          "target_18m" => %{"cell" => "Solen Goals!H8", "raw" => "0.41"},
          "target_36m" => %{"cell" => "Solen Goals!P8", "raw" => "0.29"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 5
      },
      %{
        goal_number: 1,
        code: "G1-M6",
        description: "% of students in Grades 10 performing at the Novice level in reading",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.22"),
        target_18m: Decimal.new("0.15"),
        target_36m: Decimal.new("0.07"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D9", "raw" => "0.22"},
          "target_18m" => %{"cell" => "Solen Goals!H9", "raw" => "0.15"},
          "target_36m" => %{"cell" => "Solen Goals!P9", "raw" => "0.07"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I3", "raw" => "18-Month Review Rating"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [],
        position: 6
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description: "% of students in Grades 3-5 demonstrating expected annual growth",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.25"),
        target_36m: Decimal.new("0.36"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D13", "raw" => nil},
          "target_18m" => %{"cell" => "Solen Goals!H13", "raw" => "0.25"},
          "target_36m" => %{"cell" => "Solen Goals!P13", "raw" => "0.36"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 7
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description: "% of students in Grades 6-8 demonstrating expected annual growth",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.18"),
        target_36m: Decimal.new("0.35"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D14", "raw" => nil},
          "target_18m" => %{"cell" => "Solen Goals!H14", "raw" => "0.18"},
          "target_36m" => %{"cell" => "Solen Goals!P14", "raw" => "0.35"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 8
      },
      %{
        goal_number: 2,
        code: "G2-M3",
        description: "% of students in Grade 10 demonstrating expected annual growth",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.22"),
        target_36m: Decimal.new("0.45"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D15", "raw" => nil},
          "target_18m" => %{"cell" => "Solen Goals!H15", "raw" => "0.22"},
          "target_36m" => %{"cell" => "Solen Goals!P15", "raw" => "0.45"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 9
      },
      %{
        goal_number: 2,
        code: "G2-M4",
        description: "% of students in Grades 3-5 performing at a Novice level",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.78"),
        target_18m: Decimal.new("0.55"),
        target_36m: Decimal.new("0.42"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D16", "raw" => "0.78"},
          "target_18m" => %{"cell" => "Solen Goals!H16", "raw" => "0.55"},
          "target_36m" => %{"cell" => "Solen Goals!P16", "raw" => "0.42"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 10
      },
      %{
        goal_number: 2,
        code: "G2-M5",
        description: "% of students in Grades 6-8 performing at a Novice level",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.75"),
        target_18m: Decimal.new("0.32"),
        target_36m: Decimal.new("0.25"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D17", "raw" => "0.75"},
          "target_18m" => %{"cell" => "Solen Goals!H17", "raw" => "0.32"},
          "target_36m" => %{"cell" => "Solen Goals!P17", "raw" => "0.25"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 11
      },
      %{
        goal_number: 2,
        code: "G2-M6",
        description: "% of students in Grade 10 performing at a Novice level",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.75"),
        target_18m: Decimal.new("0.68"),
        target_36m: Decimal.new("0.44"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D18", "raw" => "0.75"},
          "target_18m" => %{"cell" => "Solen Goals!H18", "raw" => "0.68"},
          "target_36m" => %{"cell" => "Solen Goals!P18", "raw" => "0.44"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I12", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 12
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description: "% of intervention cycles that are implemented with full fidelity",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.1"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("0.85"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D22", "raw" => "0.1"},
          "target_18m" => %{"cell" => "Solen Goals!H22", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Solen Goals!P22", "raw" => "0.85"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I21", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 13
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description:
          "Number of leadership and/or intervention staff regularly participating in MTSS meetings",
        category: :systems,
        unit: :count,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("5"),
        target_18m: Decimal.new("7"),
        target_36m: Decimal.new("11"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D26", "raw" => "5"},
          "target_18m" => %{"cell" => "Solen Goals!H26", "raw" => "7"},
          "target_36m" => %{"cell" => "Solen Goals!P26", "raw" => "11"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I25", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 14
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description:
          "Number of teachers implementing expectations with consistent follow-through across classrooms",
        category: :systems,
        unit: :count,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D30", "raw" => "2026-03-04"},
          "target_18m" => %{"cell" => "Solen Goals!H30", "raw" => "2026-08-10"},
          "target_36m" => %{"cell" => "Solen Goals!P30", "raw" => "2026-11-15"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I29", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :source_value_is_date],
        position: 15
      },
      %{
        goal_number: 6,
        code: "G6-M1",
        description:
          "Number of teachers who have established shared instructional routines that protect learning time such as pacing, transitions, and expectations for technology use during instruction",
        category: :systems,
        unit: :count,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("1"),
        target_18m: Decimal.new("4"),
        target_36m: Decimal.new("8"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D34", "raw" => "1"},
          "target_18m" => %{"cell" => "Solen Goals!H34", "raw" => "4"},
          "target_36m" => %{"cell" => "Solen Goals!P34", "raw" => "8"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I33", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 16
      },
      %{
        goal_number: 7,
        code: "G7-M1",
        description:
          "% of students at Solen Public School who consistently demonstrate understanding of academic success",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.15"),
        target_18m: Decimal.new("0.5"),
        target_36m: Decimal.new("0.75"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D38", "raw" => "0.15"},
          "target_18m" => %{"cell" => "Solen Goals!H38", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Solen Goals!P38", "raw" => "0.75"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 17
      },
      %{
        goal_number: 7,
        code: "G7-M2",
        description: "% of classrooms where goal setting practices are reinforced consistently",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Solen Goals!D39", "raw" => "< 10%"},
          "target_18m" => %{"cell" => "Solen Goals!H39", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Solen Goals!P39", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Solen Goals!I37", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 18
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 2, "Solen Goals!E4"},
      {"G1-M1", "sum_26", 2, "Solen Goals!F4"},
      {"G1-M2", "spr_26", 2, "Solen Goals!E5"},
      {"G1-M2", "sum_26", 2, "Solen Goals!F5"},
      {"G1-M3", "spr_26", 2, "Solen Goals!E6"},
      {"G1-M3", "sum_26", 2, "Solen Goals!F6"},
      {"G1-M4", "spr_26", 2, "Solen Goals!E7"},
      {"G1-M4", "sum_26", 2, "Solen Goals!F7"},
      {"G1-M5", "spr_26", 2, "Solen Goals!E8"},
      {"G1-M5", "sum_26", 2, "Solen Goals!F8"},
      {"G1-M6", "spr_26", 2, "Solen Goals!E9"},
      {"G1-M6", "sum_26", 2, "Solen Goals!F9"},
      {"G2-M1", "spr_26", 2, "Solen Goals!E13"},
      {"G2-M1", "sum_26", 2, "Solen Goals!F13"},
      {"G2-M2", "spr_26", 2, "Solen Goals!E14"},
      {"G2-M2", "sum_26", 2, "Solen Goals!F14"},
      {"G2-M3", "spr_26", 2, "Solen Goals!E15"},
      {"G2-M3", "sum_26", 2, "Solen Goals!F15"},
      {"G2-M4", "spr_26", 2, "Solen Goals!E16"},
      {"G2-M4", "sum_26", 2, "Solen Goals!F16"},
      {"G2-M5", "spr_26", 2, "Solen Goals!E17"},
      {"G2-M5", "sum_26", 2, "Solen Goals!F17"},
      {"G2-M6", "spr_26", 2, "Solen Goals!E18"},
      {"G2-M6", "sum_26", 2, "Solen Goals!F18"},
      {"G3-M1", "spr_26", 2, "Solen Goals!E22"},
      {"G3-M1", "sum_26", 2, "Solen Goals!F22"},
      {"G4-M1", "spr_26", 1, "Solen Goals!E26"},
      {"G4-M1", "sum_26", 2, "Solen Goals!F26"},
      {"G5-M1", "spr_26", 1, "Solen Goals!E30"},
      {"G5-M1", "sum_26", 1, "Solen Goals!F30"},
      {"G6-M1", "spr_26", 1, "Solen Goals!E34"},
      {"G6-M1", "sum_26", 1, "Solen Goals!F34"},
      {"G7-M1", "spr_26", 1, "Solen Goals!E38"},
      {"G7-M1", "sum_26", 1, "Solen Goals!F38"},
      {"G7-M2", "spr_26", 1, "Solen Goals!E39"},
      {"G7-M2", "sum_26", 1, "Solen Goals!F39"}
    ]
  end

  @doc "Annual Proficient-or-Advanced targets from the PDF (p.4)."
  def annual_assessment_goals do
    [
      {"2025-2026", "0.13", "0.07"},
      {"2026-2027", "0.18", "0.12"},
      {"2027-2028", "0.23", "0.18"},
      {"2028-2029", "0.28", "0.23"},
      {"2029-2030", "0.33", "0.29"},
      {"2030-2031", "0.38", "0.34"}
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
          "North Dakota - ND First Schools.pdf p.4 (Annual Proficiency Targets – All Students)"
      }
    end)
  end

  @doc "The plan's Measure 1 targets are the annual targets above; no other plan targets."
  def plan_targets, do: []
end
