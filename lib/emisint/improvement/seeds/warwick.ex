defmodule Emisint.Improvement.Seeds.Warwick do
  @moduledoc """
  Warwick Public School District definitions for the ND First MOU, generated from
  `ND First School MOU Goal Overview.xlsx`, sheet "Warwick Goals". Every value
  cites its source cell.

  **Scope provisional** (`workbook_scope/0`): the sheet's goals say "Warwick
  School will …" and name neither the district nor one of its three
  buildings. The workbook goals, seasonal ratings and payment row
  ("Performance-Based Payment" row 7) are recorded on this district record
  provisionally, pending confirmation; nothing scope-dependent (comparisons,
  payments) is calculated from that assignment. The continuous improvement plan's annual
  targets are per building (Warwick Elementary School pp.27-28, Warwick Middle School pp.28-29, Warwick High School pp.29-31) and are seeded on the
  building records (`buildings/0`); see `Emisint.Improvement.Seeds.Participant`.

  Values that are not a plain number in the metric's unit (for example
  "> 50%", "60-64%", "Created" or an Excel date) are kept verbatim in
  `source_values`, flagged, and left unset in the numeric fields.
  """

  @sheet "Warwick Goals"

  def sheet, do: @sheet

  def workbook_last_updated, do: ~D[2026-08-18]

  alias Emisint.Improvement.Seeds

  def school do
    %{
      name: "Warwick Public School District",
      short_name: "Warwick",
      slug: "warwick-public-school-district",
      state: "ND",
      state_entity_id: "03029",
      district_name: "Warwick Public School District",
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
        "ND First School MOU Goal Overview.xlsx: 'Warwick Goals' and 'Performance-Based Payment' (row 7). Progress-monitoring link listed as \"LINK to School Plan-Progress Monitoring TBD\" (Warwick Goals!B1), with no URL."
    }
  end

  @doc "The building records whose annual targets the continuous improvement plan lists, in PDF order."
  def buildings, do: [Seeds.WarwickElementary, Seeds.WarwickMiddle, Seeds.WarwickHigh]

  @doc """
  Whether the workbook sheet's scope (district or one building) is supported
  by the sources. For Warwick it is not: the goals are recorded on the
  district record provisionally.
  """
  def workbook_scope do
    %{
      status: :provisional,
      excerpt:
        "“Warwick School will establish and implement a vertically aligned instructional framework …” (Warwick Goals!B2); Goals 2–5 also begin “Warwick School will …” (B9, B19, B27, B35).",
      note:
        "Workbook scope provisional: the Warwick sheet says “Warwick School” and names neither Warwick Public School District nor one of its three buildings (Elementary 0302992191, Middle 0302992192, High 0302992193). The School Directory (row 5: “Warwick”, tab “Warwick Goals”, no folder), Overview, Evidence Tracker (rows 2–10: “Warwick”) and cell comments don't say either. The goals are recorded on the district record pending confirmation. Dashboard reference comparisons use the district's own published rows provisionally (user decision, November 12, 2026); no review rating or payment depends on that assignment.",
      evidence: [
        "Workbook baselines checked against 2024-25 ND Insights rows (All Grades, all students, Combined) fit no single scope: ELA Novice 59% falls in the district's 55%–59% but not any building's; Math Novice 75% falls in the elementary (70%–79%) and middle (75%–79%) ranges but not the district's 70%–74%; Emotional Disengaged 25.74% falls in the elementary (20%–29%) and middle (25%–29%) ranges but not the district's 20%–24%; Behavioral Committed 46.98% falls in none (district 40%–44%, elementary 50%–59%, middle 40%–44%, high 35%–39%). The baseline years are not stated, so this is context only, not a determination.",
        "Evidence Tracker rows 4 and 9 (school “Warwick”) link files named “Mandaree826.key” and “Mandaree1012.key”; recorded as written."
      ]
    }
  end

  @provisional "Provisional dashboard reference assumption (user decision, November 12, 2026): the district's own results (InstitutionID 03029), Combined assessment, Proficient or Advanced for “proficiency”, and the relative target read as a percentage-point change from the workbook baseline. Not a confirmed definition; it doesn't record a review result."

  @doc """
  The first school year whose results fall inside the plan: the reporting
  periods start with Spr '26 (Warwick Goals!E3).
  """
  def plan_start_year, do: "2025-2026"

  @doc """
  How the district's workbook goals are compared with the district's own
  published ND Insights results (`Emisint.Improvement.ResultGoals`), as
  provisional dashboard reference assumptions (user decision, November 12,
  2026): the district's own rows (InstitutionID 03029), the Combined
  assessment, Proficient or Advanced for "proficiency", and relative targets
  ("Inc 2-3%", "Dec 3-4%") read as percentage-point changes from the
  workbook baseline. G2-M7 (a "Dec" target for behaviorally committed
  students) stays unresolved pending Ram's confirmation of its direction.
  """
  def comparison do
    %{
      plan_start_year: plan_start_year(),
      workbook: [
        {"G2-M6", "Percentage of emotionally disengaged students", :engagement,
         :engagement_emotional, "Disengaged", "Emotional Disengaged"},
        {"G3-M1", "Percentage of ELA proficiency rate", :achievement, "Reading",
         :proficient_or_advanced, "ELA Proficient or Advanced"},
        {"G3-M2", "Percentage of ELA novice rate", :achievement, "Reading", "Novice",
         "ELA Novice"},
        {"G4-M1", "Percentage of NDSA Math proficiency", :achievement, "Math",
         :proficient_or_advanced, "Math Proficient or Advanced"},
        {"G4-M2", "Percentage of NDSA Math novice", :achievement, "Math", "Novice", "Math Novice"}
      ],
      # Provisional dashboard reference assumptions (user decision, November 12, 2026).
      assumptions: %{assessment_type: "Comp", engagement_population: :schoolwide},
      assumption_kind: "provisional assumption",
      relative_targets: :percentage_points,
      provisional: Map.new(~w(G2-M6 G3-M1 G3-M2 G4-M1 G4-M2), &{&1, @provisional}),
      grade_reference: nil,
      matching:
        "Provisional dashboard reference assumptions (user decision, November 12, 2026): the Warwick goals are compared with the district's own published rows (InstitutionID 03029), Combined assessment, all students, All Grades; “proficiency rate” (G3-M1 ELA, G4-M1 Math) is Proficient or Advanced (derived); novice (G3-M2, G4-M2) is Novice; G2-M6 is the Emotional Engagement Survey's Disengaged. Relative targets are percentage-point changes from the workbook baseline (e.g. ELA Novice baseline 59% and “Dec 2-3%” → 56%–57%), and the resulting range is colored by the dashboard comparison convention for range targets. Not compared: G2-M7 (“Percentage of behaviorally committed students”, “Dec 2-3%” / “Dec 3-4%”), unresolved until Ram confirms whether a decrease is intended; G5-M3 and G5-M4 (special-education Novice: the baselines are ranges, 80-89% and 90-100%, and student groups aren't matched). The other metrics are local measures. Building results are on each building's dashboard and are never averaged or combined here; the district goals aren't treated as building goals.",
      assumptions_text:
        "Provisional dashboard reference assumptions for Warwick (user decision, November 12, 2026; not confirmed definitions): the workbook goals are compared with the district's own results (the sheet's “Warwick School” scope is still unconfirmed), the Combined assessment, Proficient or Advanced for “proficiency rate”, the district's Emotional survey population for G2-M6, and relative targets as percentage-point changes from the workbook baseline. These comparisons never record a review result, set a rating or affect the payment estimate.",
      assumptions_short:
        "Warwick (provisional): district results, Combined assessment, Proficient or Advanced, percentage-point targets from the workbook baseline. G2-M7 unresolved pending Ram.",
      section_notes: %{
        achievement:
          "District results (InstitutionID 03029), compared provisionally with G3-M1 / G4-M1 (Proficient or Advanced) and G3-M2 / G4-M2 (Novice); relative targets are read as percentage-point changes from the workbook baseline. The plan sets annual targets per building, not for the district.",
        growth:
          "Warwick's workbook has no growth-percentile metric, so growth results have no school goal.",
        engagement:
          "District Emotional Disengaged is compared provisionally with G2-M6 (baseline 25.74%; “Dec 2-3%” → 22.74%–23.74%, “Dec 3-4%” → 21.74%–22.74%). Not compared: G2-M7 (behaviorally committed, “Dec” targets), unresolved until Ram confirms its direction."
      },
      annual_note:
        "The continuous improvement plan lists annual Proficient-or-Advanced targets per building (Warwick Elementary School pp.27-28, Warwick Middle School pp.28-29, Warwick High School pp.29-31), not for the district. They are compared on each building's dashboard with that building's own results.",
      report_notes: [
        "Workbook provenance [W]. Baselines, targets and Spring/Summer '26 ratings were imported from “ND First School MOU Goal Overview.xlsx” (sheet “Warwick Goals”); the cell is shown with each value. The workbook does not record who entered each value. Values marked “as written” are shown exactly as in the workbook.",
        "Scope (provisional). The Warwick sheet says “Warwick School” and doesn't say whether the district or one of its buildings is meant, so its goals are recorded on this district record provisionally, pending confirmation. They are not copied to the buildings, and no comparison or payment depends on the assignment. Building annual targets (Warwick Elementary School pp.27-28, Warwick Middle School pp.28-29, Warwick High School pp.29-31) appear only on each building's dashboard.",
        "Still to confirm. The scope of \"Warwick School\" (district or a building), the Combined assessment and Proficient or Advanced for \"proficiency rate\" (all used provisionally for dashboard reference, with relative targets as percentage-point changes from the workbook baseline; user decision, November 12, 2026); G2-M7's direction (\"Dec\" for behaviorally committed students), pending Ram; G5-M3 and G5-M4 (special-education Novice, range baselines); G2-M1, G2-M4 and G5-M1's range targets; G2-M5's text targets (\"Another core\")."
      ]
    }
  end

  defdelegate reporting_periods, to: Emisint.Improvement.Seeds.FortYates

  def goals do
    [
      %{
        number: 1,
        title: "Instructional Coherence and Vertical Alignment",
        description:
          "Instructional Coherence and Vertical Alignment: Warwick School will establish and implement a vertically aligned instructional framework that ensures consistent expectations, coherent progression of essential skills, and shared understanding of rigor across grade levels and content areas.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Instructional Continuity, MTSS Cycle Integrity, and System Coherence",
        description:
          "Instructional Continuity, MTSS Cycle Integrity, and System Coherence: Warwick School will strengthen instructional continuity by ensuring consistent learning opportunities, aligned supports, and sustained student engagement.",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 3},
        source_ref: "#{@sheet}!B9; steps E9:G9"
      },
      %{
        number: 3,
        title: "Literacy Growth",
        description:
          "Literacy Growth: Warwick School will increase student literacy proficiency and expand students' ability to engage in complex reading, writing, and communication tasks",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B19; steps E19:G19"
      },
      %{
        number: 4,
        title: "Mathematics Growth",
        description:
          "Mathematics Growth: Warwick School will increase student mathematics proficiency and expand students' ability to engage in problem solving, reasoning, and application of mathematical concepts",
        implementation_steps: %{"spr_26" => 2, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B27; steps E27:G27"
      },
      %{
        number: 5,
        title: "Special Education Needs",
        description:
          "Special Education Needs: Warwick School will increase in-person instruction for students receiving special education services to ensure students have access to grade-level, standards-based learning to meet their IEP goals.",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 2, "fal_26" => 2},
        source_ref: "#{@sheet}!B35; steps E35:G35"
      }
    ]
  end

  def metrics do
    [
      %{
        goal_number: 1,
        code: "G1-M1",
        description:
          "Percentage of grade levels with documented vertically aligned priority standards in ELA and Mathematics",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D4", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H4", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P4", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 1
      },
      %{
        goal_number: 1,
        code: "G1-M2",
        description:
          "Percentage of PLC meetings focused on instructional alignment and student work analysis",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D5", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H5", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P5", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 2
      },
      %{
        goal_number: 1,
        code: "G1-M3",
        description: "Percentage of grade bands implementing aligned progression of standards",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.3"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D6", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H6", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P6", "raw" => "0.3"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 3
      },
      %{
        goal_number: 1,
        code: "G1-M4",
        description:
          "Percentage of classrooms show consistent instructional practices based on walkthrough data",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D7", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H7", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P7", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I3", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 4
      },
      %{
        goal_number: 2,
        code: "G2-M1",
        description: "Percentage of MTSS intervention cycles completed with progress monitoring",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D11", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H11", "raw" => "60-70%"},
          "target_36m" => %{"cell" => "Warwick Goals!P11", "raw" => "80-85%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 5
      },
      %{
        goal_number: 2,
        code: "G2-M2",
        description: "Percentage of PLC cycles reflect a single prioritized instructional focus",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.6"),
        target_36m: Decimal.new("0.75"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D12", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H12", "raw" => "0.6"},
          "target_36m" => %{"cell" => "Warwick Goals!P12", "raw" => "0.75"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 6
      },
      %{
        goal_number: 2,
        code: "G2-M3",
        description: "Student attendance rate trends",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.87"),
        target_18m: Decimal.new("0.88"),
        target_36m: Decimal.new("0.89"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D13", "raw" => "0.87"},
          "target_18m" => %{"cell" => "Warwick Goals!H13", "raw" => "0.88"},
          "target_36m" => %{"cell" => "Warwick Goals!P13", "raw" => "0.89"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 7
      },
      %{
        goal_number: 2,
        code: "G2-M4",
        description:
          "Percentage of classrooms showing student engagement based on walkthrough data",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.5"),
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D14", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H14", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Warwick Goals!P14", "raw" => "65-70%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 8
      },
      %{
        goal_number: 2,
        code: "G2-M5",
        description: "Core subjects integrate Dakota language and culture",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D15", "raw" => "1 core"},
          "target_18m" => %{"cell" => "Warwick Goals!H15", "raw" => "Another core"},
          "target_36m" => %{"cell" => "Warwick Goals!P15", "raw" => "Another core"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 9
      },
      %{
        goal_number: 2,
        code: "G2-M6",
        description: "Percentage of emotionally disengaged students",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.2574"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D16", "raw" => "0.2574"},
          "target_18m" => %{"cell" => "Warwick Goals!H16", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P16", "raw" => "Dec 3-4%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 10
      },
      %{
        goal_number: 2,
        code: "G2-M7",
        description: "Percentage of behaviorally committed students",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.4698"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D17", "raw" => "0.4698"},
          "target_18m" => %{"cell" => "Warwick Goals!H17", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P17", "raw" => "Dec 3-4%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I10", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 11
      },
      %{
        goal_number: 3,
        code: "G3-M1",
        description: "Percentage of ELA proficiency rate",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.05"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D21", "raw" => "0.05"},
          "target_18m" => %{"cell" => "Warwick Goals!H21", "raw" => "Inc 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P21", "raw" => "Inc 4-6%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 12
      },
      %{
        goal_number: 3,
        code: "G3-M2",
        description: "Percentage of ELA novice rate",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.59"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D22", "raw" => "0.59"},
          "target_18m" => %{"cell" => "Warwick Goals!H22", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P22", "raw" => "Dec 4-6%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 13
      },
      %{
        goal_number: 3,
        code: "G3-M3",
        description: "Percentage of PLC cycles that include literacy student work analysis",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D23", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H23", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P23", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 14
      },
      %{
        goal_number: 3,
        code: "G3-M4",
        description: "Percentage of grade bands complete literacy progression alignment",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D24", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H24", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P24", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 15
      },
      %{
        goal_number: 3,
        code: "G3-M5",
        description: "Percentage of classrooms demonstrate consistent literacy practices",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D25", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H25", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P25", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I20", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 16
      },
      %{
        goal_number: 4,
        code: "G4-M1",
        description: "Percentage of NDSA Math proficiency",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.04"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D29", "raw" => "0.04"},
          "target_18m" => %{"cell" => "Warwick Goals!H29", "raw" => "Inc 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P29", "raw" => "Inc 4-6%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I28", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 17
      },
      %{
        goal_number: 4,
        code: "G4-M2",
        description: "Percentage of NDSA Math novice",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0.75"),
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D30", "raw" => "0.75"},
          "target_18m" => %{"cell" => "Warwick Goals!H30", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P30", "raw" => "Dec 4-6%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I28", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 18
      },
      %{
        goal_number: 4,
        code: "G4-M3",
        description: "Percentage of PLC cycles include math student work analysis",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D31", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H31", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P31", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I28", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 19
      },
      %{
        goal_number: 4,
        code: "G4-M4",
        description: "Percentage of grade bands complete math progression alignment",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.4"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D32", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H32", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P32", "raw" => "0.4"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I28", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 20
      },
      %{
        goal_number: 4,
        code: "G4-M5",
        description: "Percentage of classrooms demonstrate consistent math practices",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.3"),
        target_36m: Decimal.new("0.5"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D33", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H33", "raw" => "0.3"},
          "target_36m" => %{"cell" => "Warwick Goals!P33", "raw" => "0.5"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I28", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed],
        position: 21
      },
      %{
        goal_number: 5,
        code: "G5-M1",
        description: "2025 Special Education In-Person Instructional Minutes",
        category: :systems,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: Decimal.new("0"),
        target_18m: Decimal.new("0.5"),
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D37", "raw" => "0"},
          "target_18m" => %{"cell" => "Warwick Goals!H37", "raw" => "0.5"},
          "target_36m" => %{"cell" => "Warwick Goals!P37", "raw" => "65-70%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I36", "raw" => "Target Check"},
          "direction_basis" => "targets compared with baseline"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 22
      },
      %{
        goal_number: 5,
        code: "G5-M2",
        description: "Percentage of student demonstrate measurable progress",
        category: :student_outcome,
        unit: :percent,
        direction: :higher_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: Decimal.new("0.15"),
        target_36m: Decimal.new("0.2"),
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D38", "raw" => "10-19%"},
          "target_18m" => %{"cell" => "Warwick Goals!H38", "raw" => "0.15"},
          "target_36m" => %{"cell" => "Warwick Goals!P38", "raw" => "0.2"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I36", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 23
      },
      %{
        goal_number: 5,
        code: "G5-M3",
        description: "2025 NDSA ELA Special Education 80-89% Novice",
        category: :student_outcome,
        unit: :percent,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D39", "raw" => "80-89%"},
          "target_18m" => %{"cell" => "Warwick Goals!H39", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P39", "raw" => "Dec 3-4%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I36", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 24
      },
      %{
        goal_number: 5,
        code: "G5-M4",
        description: "2025 NDSA Math Special Education - Novice",
        category: :student_outcome,
        unit: :text,
        direction: :lower_is_better,
        performance_measure: :other,
        baseline_value: nil,
        target_18m: nil,
        target_36m: nil,
        source_values: %{
          "baseline" => %{"cell" => "Warwick Goals!D40", "raw" => "90-100%"},
          "target_18m" => %{"cell" => "Warwick Goals!H40", "raw" => "Dec 2-3%"},
          "target_36m" => %{"cell" => "Warwick Goals!P40", "raw" => "Dec 3-4%"},
          "review_18m_heading" => %{"cell" => "Warwick Goals!I36", "raw" => "Target Check"},
          "direction_basis" => "metric wording (targets not numeric)"
        },
        flags: [:review_18m_column_heading_unconfirmed, :value_as_text],
        position: 25
      }
    ]
  end

  @doc "Historical seasonal ratings as `{metric_code, period_code, score | :not_applicable, source_ref}`."
  def workbook_ratings do
    [
      {"G1-M1", "spr_26", 2, "Warwick Goals!E4"},
      {"G1-M1", "sum_26", 2, "Warwick Goals!F4"},
      {"G1-M2", "spr_26", 2, "Warwick Goals!E5"},
      {"G1-M2", "sum_26", 2, "Warwick Goals!F5"},
      {"G1-M3", "spr_26", 2, "Warwick Goals!E6"},
      {"G1-M3", "sum_26", 2, "Warwick Goals!F6"},
      {"G1-M4", "spr_26", 2, "Warwick Goals!E7"},
      {"G1-M4", "sum_26", 2, "Warwick Goals!F7"},
      {"G2-M1", "spr_26", 1, "Warwick Goals!E11"},
      {"G2-M1", "sum_26", 1, "Warwick Goals!F11"},
      {"G2-M2", "spr_26", 2, "Warwick Goals!E12"},
      {"G2-M2", "sum_26", 2, "Warwick Goals!F12"},
      {"G2-M3", "spr_26", 1, "Warwick Goals!E13"},
      {"G2-M3", "sum_26", 2, "Warwick Goals!F13"},
      {"G2-M4", "spr_26", 1, "Warwick Goals!E14"},
      {"G2-M4", "sum_26", 2, "Warwick Goals!F14"},
      {"G2-M5", "spr_26", 1, "Warwick Goals!E15"},
      {"G2-M5", "sum_26", 2, "Warwick Goals!F15"},
      {"G2-M6", "spr_26", 1, "Warwick Goals!E16"},
      {"G2-M6", "sum_26", 2, "Warwick Goals!F16"},
      {"G2-M7", "spr_26", 1, "Warwick Goals!E17"},
      {"G2-M7", "sum_26", 2, "Warwick Goals!F17"},
      {"G3-M1", "spr_26", 2, "Warwick Goals!E21"},
      {"G3-M1", "sum_26", 2, "Warwick Goals!F21"},
      {"G3-M2", "spr_26", 2, "Warwick Goals!E22"},
      {"G3-M2", "sum_26", 2, "Warwick Goals!F22"},
      {"G3-M3", "spr_26", 2, "Warwick Goals!E23"},
      {"G3-M3", "sum_26", 2, "Warwick Goals!F23"},
      {"G3-M4", "spr_26", 2, "Warwick Goals!E24"},
      {"G3-M4", "sum_26", 2, "Warwick Goals!F24"},
      {"G3-M5", "spr_26", 2, "Warwick Goals!E25"},
      {"G3-M5", "sum_26", 2, "Warwick Goals!F25"},
      {"G4-M1", "spr_26", 2, "Warwick Goals!E29"},
      {"G4-M1", "sum_26", 2, "Warwick Goals!F29"},
      {"G4-M2", "spr_26", 2, "Warwick Goals!E30"},
      {"G4-M2", "sum_26", 2, "Warwick Goals!F30"},
      {"G4-M3", "spr_26", 2, "Warwick Goals!E31"},
      {"G4-M3", "sum_26", 2, "Warwick Goals!F31"},
      {"G4-M4", "spr_26", 2, "Warwick Goals!E32"},
      {"G4-M4", "sum_26", 2, "Warwick Goals!F32"},
      {"G4-M5", "spr_26", 2, "Warwick Goals!E33"},
      {"G4-M5", "sum_26", 2, "Warwick Goals!F33"},
      {"G5-M1", "spr_26", 2, "Warwick Goals!E37"},
      {"G5-M1", "sum_26", 2, "Warwick Goals!F37"},
      {"G5-M2", "spr_26", 2, "Warwick Goals!E38"},
      {"G5-M2", "sum_26", 2, "Warwick Goals!F38"},
      {"G5-M3", "spr_26", 2, "Warwick Goals!E39"},
      {"G5-M3", "sum_26", 2, "Warwick Goals!F39"},
      {"G5-M4", "spr_26", 2, "Warwick Goals!E40"},
      {"G5-M4", "sum_26", 2, "Warwick Goals!F40"}
    ]
  end

  @doc "The plan sets no district-level annual targets (they are per building)."
  def annual_assessment_goals, do: []
end
