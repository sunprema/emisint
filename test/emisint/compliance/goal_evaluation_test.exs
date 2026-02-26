defmodule Emisint.Compliance.GoalEvaluationTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Assessments.{AssessmentResult, CompetitorData}
  alias Emisint.Compliance.{GoalEvaluation, Schedule71Goal}
  alias Emisint.Compliance.Calculations.EvaluateGoalStatus
  alias Emisint.Registry.{AcademicYear, Enrollment, Student}

  defp org_id, do: Ash.UUID.generate()

  # ── Setup helpers ──────────────────────────────────────────────────────────

  defp create_school(oid, code \\ "08001") do
    Ash.create!(School,
      %{name: "Great Lakes Academy", mde_district_code: "25010", mde_building_code: code},
      tenant: oid,
      authorize?: false
    )
  end

  defp create_student(oid, uic) do
    Ash.create!(Student, %{uic: uic, first_name: "Test", last_name: "Student"},
      tenant: oid,
      authorize?: false
    )
  end

  defp create_year(oid) do
    Ash.create!(AcademicYear,
      %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
      tenant: oid,
      authorize?: false
    )
  end

  defp enroll!(oid, student, school, year, grade \\ :g5) do
    Ash.create!(Enrollment,
      %{
        grade_level: grade,
        enrolled_at: ~D[2024-09-03],
        student_id: student.id,
        school_id: school.id,
        academic_year_id: year.id
      },
      tenant: oid,
      authorize?: false
    )
  end

  defp create_result!(oid, student, year, attrs) do
    Ash.create!(AssessmentResult,
      Map.merge(
        %{
          assessment_type: :m_step,
          subject: "math",
          testing_window: :spring,
          student_id: student.id,
          academic_year_id: year.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp create_goal!(oid, school, attrs) do
    Ash.create!(Schedule71Goal,
      Map.merge(
        %{
          title: "Test Goal",
          subject: "math",
          testing_window: :spring,
          target_value: Decimal.new("0.65"),
          school_id: school.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  defp recalculate!(oid, goal, year) do
    Ash.create!(GoalEvaluation,
      %{schedule71_goal_id: goal.id, academic_year_id: year.id},
      action: :recalculate,
      tenant: oid,
      authorize?: false
    )
  end

  # ── EvaluateGoalStatus unit tests ──────────────────────────────────────────

  describe "EvaluateGoalStatus.evaluate/5" do
    test "returns :insufficient_data for nil actual" do
      assert EvaluateGoalStatus.evaluate(nil, Decimal.new("50"), :gte, nil, nil) ==
               :insufficient_data
    end

    test "returns :exceeds when actual >= exceeds_threshold" do
      assert EvaluateGoalStatus.evaluate(
               Decimal.new("80"),
               Decimal.new("65"),
               :gte,
               Decimal.new("75"),
               Decimal.new("55")
             ) == :exceeds
    end

    test "returns :meets when actual >= target but below exceeds_threshold" do
      assert EvaluateGoalStatus.evaluate(
               Decimal.new("70"),
               Decimal.new("65"),
               :gte,
               Decimal.new("75"),
               Decimal.new("55")
             ) == :meets
    end

    test "returns :approaching when actual >= approaching_threshold but below target" do
      assert EvaluateGoalStatus.evaluate(
               Decimal.new("60"),
               Decimal.new("65"),
               :gte,
               Decimal.new("75"),
               Decimal.new("55")
             ) == :approaching
    end

    test "returns :below when actual is below all thresholds" do
      assert EvaluateGoalStatus.evaluate(
               Decimal.new("40"),
               Decimal.new("65"),
               :gte,
               Decimal.new("75"),
               Decimal.new("55")
             ) == :below
    end

    test "handles missing thresholds" do
      assert EvaluateGoalStatus.evaluate(Decimal.new("70"), Decimal.new("65"), :gte, nil, nil) ==
               :meets

      assert EvaluateGoalStatus.evaluate(Decimal.new("60"), Decimal.new("65"), :gte, nil, nil) ==
               :below
    end
  end

  # ── :sgp_median branch ────────────────────────────────────────────────────

  describe "recalculate with goal_type :sgp_median" do
    test "computes median SGP and returns :meets when >= target" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      # 3 students enrolled, SGP values: 40, 50, 70 → median = 50
      Enum.each([{"S001", 40}, {"S002", 50}, {"S003", 70}], fn {uic, sgp} ->
        s = create_student(oid, uic)
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{sgp: sgp})
      end)

      goal =
        create_goal!(oid, school, %{
          goal_type: :sgp_median,
          assessment_type: :m_step,
          target_value: Decimal.new("50")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :meets
      assert eval.data_points_count == 3
      assert Decimal.equal?(eval.actual_value, Decimal.new("50"))
    end

    test "returns :below when median SGP < target" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      Enum.each([{"S001", 30}, {"S002", 40}, {"S003", 45}], fn {uic, sgp} ->
        s = create_student(oid, uic)
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{sgp: sgp})
      end)

      goal =
        create_goal!(oid, school, %{
          goal_type: :sgp_median,
          target_value: Decimal.new("50")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :below
    end

    test "returns :insufficient_data when no students enrolled" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      goal = create_goal!(oid, school, %{goal_type: :sgp_median, target_value: Decimal.new("50")})

      eval = recalculate!(oid, goal, year)

      assert eval.status == :insufficient_data
      assert eval.data_points_count == 0
    end

    test "returns :insufficient_data when no results have SGP values" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      s = create_student(oid, "S001")
      enroll!(oid, s, school, year)
      # Result with no SGP
      create_result!(oid, s, year, %{proficiency_level: "3"})

      goal = create_goal!(oid, school, %{goal_type: :sgp_median, target_value: Decimal.new("50")})

      eval = recalculate!(oid, goal, year)

      assert eval.status == :insufficient_data
    end
  end

  # ── :proficiency_threshold branch ─────────────────────────────────────────

  describe "recalculate with goal_type :proficiency_threshold" do
    test "computes proficiency rate and returns :meets when >= target" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      # 10 students, 7 at levels "3" or "4" → rate = 0.7
      levels = ["3", "4", "3", "4", "3", "4", "3", "1", "2", "1"]

      Enum.each(Enum.with_index(levels), fn {level, i} ->
        s = create_student(oid, "S#{String.pad_leading(Integer.to_string(i), 3, "0")}")
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{proficiency_level: level})
      end)

      goal =
        create_goal!(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65"),
          exceeds_threshold: Decimal.new("0.80")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :meets
      assert eval.data_points_count == 10
      # 7/10 = 0.7
      assert Decimal.compare(eval.actual_value, Decimal.new("0.7")) == :eq
    end

    test "returns :approaching when rate is between approaching and target" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      # 6 proficient out of 10 → 0.6
      levels = ["3", "4", "3", "4", "3", "4", "1", "2", "1", "2"]

      Enum.each(Enum.with_index(levels), fn {level, i} ->
        s = create_student(oid, "S#{String.pad_leading(Integer.to_string(i), 3, "0")}")
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{proficiency_level: level})
      end)

      goal =
        create_goal!(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65"),
          approaching_threshold: Decimal.new("0.55")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :approaching
    end

    test "filters by grade_levels when specified" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      # g5 student: proficient; g4 student: not proficient
      s5 = create_student(oid, "S001")
      enroll!(oid, s5, school, year, :g5)
      create_result!(oid, s5, year, %{proficiency_level: "4"})

      s4 = create_student(oid, "S002")
      enroll!(oid, s4, school, year, :g4)
      create_result!(oid, s4, year, %{proficiency_level: "1"})

      # Goal only covers g5 → should see 1/1 = 1.0, not 1/2 = 0.5
      goal =
        create_goal!(oid, school, %{
          goal_type: :proficiency_threshold,
          grade_levels: ["g5"],
          target_value: Decimal.new("0.65")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :meets
      assert eval.data_points_count == 1
    end
  end

  # ── :growth_target branch ─────────────────────────────────────────────────

  describe "recalculate with goal_type :growth_target" do
    test "computes on-track rate and returns :meets when >= target" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      # 3 students: 2 on track, 1 not (scale_score >= growth_target = on track)
      [
        {"S001", Decimal.new("2450"), Decimal.new("2400")},
        {"S002", Decimal.new("2550"), Decimal.new("2500")},
        {"S003", Decimal.new("2200"), Decimal.new("2300")}
      ]
      |> Enum.each(fn {uic, scale, target} ->
        s = create_student(oid, uic)
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{scale_score: scale, growth_target: target})
      end)

      goal =
        create_goal!(oid, school, %{
          goal_type: :growth_target,
          # 2/3 ≈ 0.667 ≥ 0.60
          target_value: Decimal.new("0.60")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :meets
      assert eval.data_points_count == 3
    end
  end

  # ── :outperform_district branch ───────────────────────────────────────────

  describe "recalculate with goal_type :outperform_district" do
    test "computes school_rate minus district_rate and returns :meets when positive" do
      oid = org_id()
      # school has mde_district_code "25010"
      school = create_school(oid)
      year = create_year(oid)

      # 7/10 proficient → school_rate = 0.70
      levels = ["3", "4", "3", "4", "3", "4", "3", "1", "2", "1"]

      Enum.each(Enum.with_index(levels), fn {level, i} ->
        s = create_student(oid, "S#{String.pad_leading(Integer.to_string(i), 3, "0")}")
        enroll!(oid, s, school, year)
        create_result!(oid, s, year, %{proficiency_level: level})
      end)

      # District proficiency: 0.65 → school outperforms by 0.05
      Ash.create!(CompetitorData,
        %{
          district_name: "Flint Community Schools",
          mde_district_code: "25010",
          subject: "math",
          grade_level: "all",
          proficiency_rate: Decimal.new("0.65"),
          academic_year_label: "2024-2025"
        },
        authorize?: false
      )

      # Goal: school - district >= 0 (outperforming means positive difference)
      goal =
        create_goal!(oid, school, %{
          goal_type: :outperform_district,
          target_value: Decimal.new("0")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :meets
      assert eval.data_points_count == 10
      # actual ≈ 0.70 - 0.65 = 0.05
      assert Decimal.compare(eval.actual_value, Decimal.new("0")) == :gt
    end

    test "returns :insufficient_data when no competitor data exists for district" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      s = create_student(oid, "S001")
      enroll!(oid, s, school, year)
      create_result!(oid, s, year, %{proficiency_level: "4"})

      # No CompetitorData for this district
      goal =
        create_goal!(oid, school, %{
          goal_type: :outperform_district,
          target_value: Decimal.new("0")
        })

      eval = recalculate!(oid, goal, year)

      assert eval.status == :insufficient_data
    end
  end

  # ── Upsert / recalculate behaviour ────────────────────────────────────────

  describe "recalculate upsert" do
    test "creates a new evaluation on first call" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      goal = create_goal!(oid, school, %{goal_type: :sgp_median, target_value: Decimal.new("50")})

      eval = recalculate!(oid, goal, year)

      assert eval.status == :insufficient_data

      {:ok, evals} = Ash.read(GoalEvaluation, tenant: oid, authorize?: false)
      assert length(evals) == 1
    end

    test "updates the existing record on subsequent calls" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      s = create_student(oid, "S001")
      enroll!(oid, s, school, year)

      goal = create_goal!(oid, school, %{goal_type: :sgp_median, target_value: Decimal.new("50")})

      # First call — no results yet
      recalculate!(oid, goal, year)

      # Add a result, recalculate again
      create_result!(oid, s, year, %{sgp: 55})
      recalculate!(oid, goal, year)

      {:ok, evals} = Ash.read(GoalEvaluation, tenant: oid, authorize?: false)
      # Still only one record (upserted)
      assert length(evals) == 1
      assert hd(evals).status == :meets
    end
  end

  # ── Threshold snapshots ───────────────────────────────────────────────────

  describe "threshold snapshots" do
    test "snapshots goal thresholds into the evaluation record" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      goal =
        create_goal!(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65"),
          exceeds_threshold: Decimal.new("0.80"),
          approaching_threshold: Decimal.new("0.50")
        })

      eval = recalculate!(oid, goal, year)

      assert Decimal.equal?(eval.target_value, Decimal.new("0.65"))
      assert Decimal.equal?(eval.exceeds_threshold, Decimal.new("0.80"))
      assert Decimal.equal?(eval.approaching_threshold, Decimal.new("0.50"))
      assert eval.comparison_operator == :gte
    end
  end

  # ── derived_status calculation ────────────────────────────────────────────

  describe "derived_status calculation" do
    test "derived_status matches stored status" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      goal =
        create_goal!(oid, school, %{
          goal_type: :proficiency_threshold,
          target_value: Decimal.new("0.65")
        })

      eval = recalculate!(oid, goal, year)

      loaded = Ash.load!(eval, :derived_status, tenant: oid, authorize?: false)
      assert loaded.derived_status == eval.status
    end
  end

  # ── PaperTrail ────────────────────────────────────────────────────────────

  describe "paper trail" do
    test "creates version records on updates to a goal evaluation" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      goal = create_goal!(oid, school, %{goal_type: :sgp_median, target_value: Decimal.new("50")})

      eval = recalculate!(oid, goal, year)

      Ash.update!(eval, %{status: :meets, actual_value: Decimal.new("55")},
        tenant: oid,
        authorize?: false
      )

      loaded = Ash.load!(eval, :paper_trail_versions, tenant: oid, authorize?: false)
      assert length(loaded.paper_trail_versions) >= 1
    end
  end
end
