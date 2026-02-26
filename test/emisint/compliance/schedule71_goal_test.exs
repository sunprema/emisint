defmodule Emisint.Compliance.Schedule71GoalTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Compliance.Schedule71Goal

  defp org_id, do: Ash.UUID.generate()

  defp create_school(oid) do
    Ash.create!(School, %{name: "Test School", mde_district_code: "80010", mde_building_code: "08001"},
      tenant: oid,
      authorize?: false
    )
  end

  defp valid_attrs(school_id) do
    %{
      title: "Grade 5 Math Proficiency >= 65%",
      goal_type: :proficiency_threshold,
      subject: "math",
      testing_window: :spring,
      target_value: Decimal.new("0.65"),
      school_id: school_id
    }
  end

  describe "create/1" do
    test "creates a goal with required attrs" do
      oid = org_id()
      school = create_school(oid)

      assert {:ok, goal} =
               Ash.create(Schedule71Goal, valid_attrs(school.id), tenant: oid, authorize?: false)

      assert goal.title == "Grade 5 Math Proficiency >= 65%"
      assert goal.goal_type == :proficiency_threshold
      assert goal.subject == "math"
      assert goal.testing_window == :spring
      assert Decimal.equal?(goal.target_value, Decimal.new("0.65"))
      assert goal.comparison_operator == :gte
      assert goal.grade_levels == []
      assert goal.school_id == school.id
      assert goal.organization_id == oid
    end

    test "creates with all optional attrs" do
      oid = org_id()
      school = create_school(oid)

      attrs =
        valid_attrs(school.id)
        |> Map.merge(%{
          grade_levels: ["g4", "g5"],
          assessment_type: :m_step,
          exceeds_threshold: Decimal.new("0.75"),
          approaching_threshold: Decimal.new("0.55"),
          subgroup: :economically_disadvantaged
        })

      assert {:ok, goal} = Ash.create(Schedule71Goal, attrs, tenant: oid, authorize?: false)

      assert goal.grade_levels == ["g4", "g5"]
      assert goal.assessment_type == :m_step
      assert Decimal.equal?(goal.exceeds_threshold, Decimal.new("0.75"))
      assert Decimal.equal?(goal.approaching_threshold, Decimal.new("0.55"))
      assert goal.subgroup == :economically_disadvantaged
    end

    test "accepts all goal types" do
      oid = org_id()
      school = create_school(oid)

      for goal_type <- [:proficiency_threshold, :sgp_median, :outperform_district, :growth_target] do
        attrs = valid_attrs(school.id) |> Map.put(:goal_type, goal_type)
        assert {:ok, goal} = Ash.create(Schedule71Goal, attrs, tenant: oid, authorize?: false)
        assert goal.goal_type == goal_type
      end
    end

    test "rejects invalid goal_type" do
      oid = org_id()
      school = create_school(oid)

      assert {:error, _} =
               Ash.create(
                 Schedule71Goal,
                 valid_attrs(school.id) |> Map.put(:goal_type, :unknown),
                 tenant: oid,
                 authorize?: false
               )
    end
  end

  describe "update/1" do
    test "updates mutable fields" do
      oid = org_id()
      school = create_school(oid)
      goal = Ash.create!(Schedule71Goal, valid_attrs(school.id), tenant: oid, authorize?: false)

      assert {:ok, updated} =
               Ash.update(
                 goal,
                 %{title: "Updated Title", target_value: Decimal.new("0.70"), grade_levels: ["g5"]},
                 tenant: oid,
                 authorize?: false
               )

      assert updated.title == "Updated Title"
      assert Decimal.equal?(updated.target_value, Decimal.new("0.70"))
      assert updated.grade_levels == ["g5"]
    end

    test "goal_type and subject are immutable (not in update accept list)" do
      oid = org_id()
      school = create_school(oid)
      goal = Ash.create!(Schedule71Goal, valid_attrs(school.id), tenant: oid, authorize?: false)

      assert {:error, error} =
               Ash.update(goal, %{goal_type: :sgp_median}, tenant: oid, authorize?: false)

      assert error.errors
             |> Enum.any?(&match?(%Ash.Error.Invalid.NoSuchInput{input: :goal_type}, &1))
    end
  end

  describe "paper trail" do
    test "creates a version record on update" do
      oid = org_id()
      school = create_school(oid)
      goal = Ash.create!(Schedule71Goal, valid_attrs(school.id), tenant: oid, authorize?: false)

      Ash.update!(goal, %{target_value: Decimal.new("0.70")}, tenant: oid, authorize?: false)

      loaded = Ash.load!(goal, :paper_trail_versions, tenant: oid, authorize?: false)
      assert length(loaded.paper_trail_versions) >= 1
    end

    test "version captures the changed target_value" do
      oid = org_id()
      school = create_school(oid)
      goal = Ash.create!(Schedule71Goal, valid_attrs(school.id), tenant: oid, authorize?: false)

      Ash.update!(goal, %{target_value: Decimal.new("0.70")}, tenant: oid, authorize?: false)

      loaded = Ash.load!(goal, :paper_trail_versions, tenant: oid, authorize?: false)
      version = hd(loaded.paper_trail_versions)

      # changes_only mode: only changed fields are in the changes map
      assert Map.has_key?(version.changes, "target_value")
    end
  end
end
