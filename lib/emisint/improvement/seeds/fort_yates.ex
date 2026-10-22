defmodule Emisint.Improvement.Seeds.FortYates do
  @moduledoc """
  Fort Yates Middle School definitions for the ND First MOU pilot,
  transcribed from:

    * `ND First School MOU Goal Overview.xlsx`, sheet "Ft Yates Goals"
      (last updated 2026-08-18) and sheet "Performance-Based Payment"
    * `North Dakota - ND First Schools.pdf`, p.17 (annual ELA/math targets)

  The source files are not committed. Every value cites its source cell.

  Percent values are normalized proportions (0.6 = 60%). `Ft Yates Goals!P7`
  (90) and `P16` (80) are General-formatted while every other target is a
  decimal, so their scale is unconfirmed: the raw values are kept in
  `source_values` and `target_36m` is left unset.

  Goal 4's review column (I26) is headed "Target Check" rather than
  "18-Month Review Rating", although the payment formula reads it; those
  metrics carry `:review_18m_column_heading_unconfirmed`.
  """

  @sheet "Ft Yates Goals"
  @workbook_last_updated ~D[2026-08-18]

  def workbook_last_updated, do: @workbook_last_updated

  def school do
    %{
      name: "Fort Yates Middle School",
      short_name: "Fort Yates",
      slug: "fort-yates-ms",
      state: "ND",
      state_entity_id: "4300429212",
      district_name: "Ft Yates Public School District",
      grade_span: "5-8",
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
        "ND First School MOU Goal Overview.xlsx: '#{@sheet}' (last updated 2026-08-18) and " <>
          "'Performance-Based Payment'. Progress-monitoring link listed as TBD (#{@sheet}!B1)."
    }
  end

  # {code, label, kind, workbook column}
  def reporting_periods do
    [
      {"spr_26", "Spr '26", :seasonal, "E"},
      {"sum_26", "Sum '26", :seasonal, "F"},
      {"fal_26", "Fal '26", :seasonal, "G"},
      {"review_18m", "18-Month Review", :review_18m, "I"},
      {"win_27", "Win '27", :seasonal, "J"},
      {"spr_27", "Spr '27", :seasonal, "K"},
      {"sum_27", "Sum '27", :seasonal, "L"},
      {"fal_27", "Fal '27", :seasonal, "M"},
      {"win_28", "Win '28", :seasonal, "N"},
      {"spr_28", "Spr '28", :seasonal, "O"},
      {"review_36m", "36-Month Review", :review_36m, "Q"}
    ]
    |> Enum.with_index(1)
    |> Enum.map(fn {{code, label, kind, column}, position} ->
      %{code: code, label: label, kind: kind, position: position, source_column: column}
    end)
  end

  def goals do
    [
      %{
        number: 1,
        title: "Operational Reliability & System Coherence",
        description:
          "Operational Reliability & System Coherence: Fort Yates Middle School will establish and sustain " <>
            "documented operational systems that protect instructional time, clarify staff roles, ensure " <>
            "continuity during staffing transitions, and strengthen governance transparency.",
        implementation_steps: %{"spr_26" => 5, "sum_26" => 4, "fal_26" => 3},
        source_ref: "#{@sheet}!B2; steps E2:G2"
      },
      %{
        number: 2,
        title: "Literacy Growth",
        description:
          "Literacy Growth: Fort Yates Middle School will increase literacy proficiency and student growth " <>
            "outcomes as measured by ND A+ summative and interim assessments, through strengthened, consistent " <>
            "instructional routines and data-driven decision-making",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 3, "fal_26" => 4},
        source_ref: "#{@sheet}!B11; steps E11:G11"
      },
      %{
        number: 3,
        title: "Mathematics Growth",
        description:
          "Mathematics Growth: Fort Yates Middle School will increase mathematics proficiency and student " <>
            "growth outcomes, as measured by ND A+ summative and interim assessments, while reducing the " <>
            "percentage of students perfoming at the novice level through aligned instructional systems and " <>
            "data-drive practices",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 3, "fal_26" => 4},
        source_ref: "#{@sheet}!B18; steps E18:G18"
      },
      %{
        number: 4,
        title: "Student Engagement and Academic Identity",
        description:
          "Student Engagement and Academic Identity: Fort Yates Middle School will increase student engagement, " <>
            "through academically rigorous, culturally grounded instructional practices that strengthen student " <>
            "connection to learning, identity, and future pathways, resulting in improved literacy and " <>
            "mathematics outcomes",
        implementation_steps: %{"spr_26" => 1, "sum_26" => 3, "fal_26" => 4},
        source_ref: "#{@sheet}!B25; steps E25:G25"
      }
    ]
  end

  # {goal, row, code, category, direction, measure, description, baseline, t18, t36,
  #  spr_26 rating, sum_26 rating}
  # t36 == {:unconfirmed, raw} keeps the raw value and leaves target_36m unset.
  @metric_rows [
    {1, 4, "G1-M1", :systems, :higher_is_better, :other,
     "Percentage of core instructional blocks protected from non-emergency interruption", "0.6",
     "0.9", "0.95", 1, 2},
    {1, 5, "G1-M2", :systems, :higher_is_better, :other,
     "% of staffing absences are covered weekly", "0.6", "0.7", "0.75", 1, 1},
    {1, 6, "G1-M3", :systems, :higher_is_better, :other,
     "% of leadership absences are covered weekly", "0.5", "0.8", "0.9", 1, 1},
    {1, 7, "G1-M4", :systems, :higher_is_better, :other,
     "Percentage of staff positions with updated job descriptions", "0.3", "0.7",
     {:unconfirmed, "90"}, 1, 1},
    {1, 8, "G1-M5", :systems, :higher_is_better, :other,
     "Percentage of staffing transitions follow a formal onboarding or exit protocol", "0", "0.8",
     "0.9", 1, 1},
    {1, 9, "G1-M6", :systems, :higher_is_better, :other,
     "Percentage of board meeting minutes published within established timeline", "0.5", "0.8",
     "0.85", 1, 1},
    {2, 13, "G2-M1", :student_outcome, :higher_is_better, :proficient,
     "Percentage of students in Proficient performance level", "0.22", "0.27", "0.32", 2, 2},
    {2, 14, "G2-M2", :student_outcome, :lower_is_better, :novice,
     "Percentage of students in Novice performance level", "0.46", "0.39", "0.31", 2, 2},
    {2, 15, "G2-M3", :student_outcome, :higher_is_better, :met_growth_expectation,
     "Percentage of students met state growth expectations", "0.38", "0.43", "0.51", 2, 2},
    {2, 16, "G2-M4", :systems, :higher_is_better, :other,
     "Percentage of core instructional systems are implemented with fidelity", "0.03", "0.5",
     {:unconfirmed, "80"}, 2, 2},
    {3, 20, "G3-M1", :student_outcome, :higher_is_better, :proficient,
     "Percentage of students in Proficient performance level", "0.05", "0.08", "0.12", 2, 2},
    {3, 21, "G3-M2", :student_outcome, :lower_is_better, :novice,
     "Percentage of students in Novice performance level", "0.78", "0.72", "0.68", 2, 2},
    {3, 22, "G3-M3", :student_outcome, :higher_is_better, :met_growth_expectation,
     "Percentage of students met state growth expectations", "0.41", "0.46", "0.52", 2, 2},
    {3, 23, "G3-M4", :systems, :higher_is_better, :other,
     "Percentage of core instructional systems are implemented with fidelity", "0.03", "0.5",
     "0.8", 2, 2},
    {4, 27, "G4-M1", :student_outcome, :higher_is_better, :other,
     "Percentage of students actively engaged based on current observations", "0.3", "0.35",
     "0.4", 1, 1},
    {4, 28, "G4-M2", :student_outcome, :lower_is_better, :other,
     "Percentage of students identified as emotionally disengaged based on student engagement survey data",
     "0.429", "0.329", "0.229", 1, 1},
    {4, 29, "G4-M3", :student_outcome, :lower_is_better, :other,
     "Percentage of student are behaviorally disengaged based on student engagement survey data",
     "0.163", "0.12", "0.08", 1, 1},
    {4, 30, "G4-M4", :student_outcome, :lower_is_better, :other,
     "Percentage of students cognitively disengaged based on student engagement survey data",
     "0.102", "0.07", "0.05", 1, 1}
  ]

  @doc "Metric definitions keyed by goal number."
  def metrics do
    @metric_rows
    |> Enum.with_index(1)
    |> Enum.map(fn {{goal, row, code, category, direction, measure, description, baseline, t18,
                     t36, _, _}, position} ->
      {target_36m, t36_flags} = target_36m(t36)

      %{
        goal_number: goal,
        code: code,
        description: description,
        category: category,
        unit: :percent,
        direction: direction,
        performance_measure: measure,
        baseline_value: Decimal.new(baseline),
        target_18m: Decimal.new(t18),
        target_36m: target_36m,
        source_values: %{
          "baseline" => %{"cell" => "#{@sheet}!D#{row}", "raw" => baseline},
          "target_18m" => %{"cell" => "#{@sheet}!H#{row}", "raw" => t18},
          "target_36m" => %{"cell" => "#{@sheet}!P#{row}", "raw" => raw(t36)}
        },
        flags: t36_flags ++ if(goal == 4, do: [:review_18m_column_heading_unconfirmed], else: []),
        position: position
      }
    end)
  end

  @doc """
  Historical seasonal ratings from columns E (Spr '26) and F (Sum '26), as
  `{metric_code, period_code, score, source_ref}`.
  """
  def workbook_ratings do
    Enum.flat_map(@metric_rows, fn {_, row, code, _, _, _, _, _, _, _, spr, sum} ->
      [
        {code, "spr_26", spr, "#{@sheet}!E#{row}"},
        {code, "sum_26", sum, "#{@sheet}!F#{row}"}
      ]
    end)
  end

  @doc "Annual Proficient-or-Advanced targets from the PDF, p.17."
  def annual_assessment_goals do
    [
      {"2025-2026", "0.25", "0.11"},
      {"2026-2027", "0.30", "0.16"},
      {"2027-2028", "0.34", "0.21"},
      {"2028-2029", "0.39", "0.26"},
      {"2029-2030", "0.43", "0.32"},
      {"2030-2031", "0.47", "0.37"}
    ]
    |> Enum.flat_map(fn {year, ela, math} ->
      [{year, :ela, ela}, {year, :math, math}]
    end)
    |> Enum.map(fn {year, subject, target} ->
      %{
        school_year: year,
        subject: subject,
        target_value: Decimal.new(target),
        measure: :proficient_or_advanced,
        includes_alternate: true,
        source_ref: "North Dakota - ND First Schools.pdf p.17 (Annual Proficiency Targets)"
      }
    end)
  end

  defp target_36m({:unconfirmed, _raw}), do: {nil, [:target_36m_needs_confirmation]}
  defp target_36m(value), do: {Decimal.new(value), []}

  defp raw({:unconfirmed, raw}), do: raw
  defp raw(value), do: value
end
