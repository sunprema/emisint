defmodule Emisint.Improvement.AccessPolicyTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Accounts.{School, SchoolMembership}
  alias Emisint.Improvement.{ActualResult, Goal, GoalPlan, ImplementationRating, Metric}

  setup do
    org_a = seeded_organization!(name: "Org A")
    org_b = seeded_organization!(name: "Org B")

    # A second school in Org A, to test cross-school isolation.
    other_school =
      Ash.create!(
        School,
        %{name: "Other School", slug: "other-school", state: "ND", state_entity_id: "0000000001"},
        tenant: org_a.id,
        authorize?: false
      )

    other_plan =
      Ash.create!(
        GoalPlan,
        %{school_id: other_school.id, program: "nd_first_mou", name: "Other plan"},
        tenant: org_a.id,
        authorize?: false
      )

    other_goal =
      Ash.create!(Goal, %{goal_plan_id: other_plan.id, number: 1, title: "Other goal"},
        tenant: org_a.id,
        authorize?: false
      )

    other_metric =
      Ash.create!(
        Metric,
        %{
          goal_id: other_goal.id,
          code: "X-M1",
          description: "Other metric",
          category: :systems,
          direction: :higher_is_better,
          position: 1
        },
        tenant: org_a.id,
        authorize?: false
      )

    viewer = user!(org_a, :school_leader)
    membership!(viewer, school!(org_a), :viewer, org_a)

    %{
      org_a: org_a,
      org_b: org_b,
      other_school: other_school,
      other_metric: other_metric,
      contributor: contributor!(org_a),
      viewer: viewer,
      no_membership: user!(org_a, :school_leader),
      liaison: user!(org_a, :authorizer_liaison),
      admin_a: user!(org_a, :emo_admin),
      admin_b: user!(org_b, :emo_admin),
      system_admin: user!(nil, :system_admin)
    }
  end

  defp metric_ids(actor, org),
    do: Metric |> Ash.read!(tenant: org.id, actor: actor) |> Enum.map(& &1.id)

  defp record(actor, org, metric, period_code \\ "fal_26") do
    Ash.create(
      ActualResult,
      %{
        metric_id: metric.id,
        reporting_period_id: period!(org, period_code).id,
        value_state: :exact,
        value: Decimal.new("0.5"),
        measurement_date: ~D[2026-10-01]
      },
      action: :record,
      tenant: org.id,
      actor: actor
    )
  end

  describe "reads" do
    test "members see only their school's data", ctx do
      fort_yates_ids =
        ctx.org_a
        |> then(&Ash.read!(Metric, tenant: &1.id, authorize?: false))
        |> Enum.reject(&(&1.id == ctx.other_metric.id))
        |> Enum.map(& &1.id)

      for actor <- [ctx.contributor, ctx.viewer] do
        ids = metric_ids(actor, ctx.org_a)
        assert length(ids) == 18
        assert Enum.sort(ids) == Enum.sort(fort_yates_ids)
        refute ctx.other_metric.id in ids
      end

      assert [%{slug: "fort-yates-ms"}] =
               Ash.read!(School, tenant: ctx.org_a.id, actor: ctx.contributor)
    end

    test "users without a membership see nothing, regardless of role", ctx do
      for actor <- [ctx.no_membership, ctx.liaison] do
        assert metric_ids(actor, ctx.org_a) == []
        assert Ash.read!(School, tenant: ctx.org_a.id, actor: actor) == []
      end
    end

    test "org admins see every school in their own organization only", ctx do
      assert length(metric_ids(ctx.admin_a, ctx.org_a)) == 19
      assert length(Ash.read!(School, tenant: ctx.org_a.id, actor: ctx.admin_a)) == 2
    end

    test "a forged tenant returns nothing", ctx do
      assert metric_ids(ctx.admin_b, ctx.org_a) == []
      assert Ash.read!(ImplementationRating, tenant: ctx.org_a.id, actor: ctx.admin_b) == []
      assert Ash.read!(SchoolMembership, tenant: ctx.org_a.id, actor: ctx.admin_b) == []
    end

    test "a member of one org cannot read their membership's school via another org's tenant",
         ctx do
      assert metric_ids(ctx.contributor, ctx.org_b) == []
    end

    test "system admins see whichever organization is selected", ctx do
      a_ids = metric_ids(ctx.system_admin, ctx.org_a)
      b_ids = metric_ids(ctx.system_admin, ctx.org_b)

      assert length(a_ids) == 19
      assert length(b_ids) == 18
      assert MapSet.disjoint?(MapSet.new(a_ids), MapSet.new(b_ids))
    end
  end

  describe "writes" do
    test "contributors can record for their own school only", ctx do
      assert {:ok, _} = record(ctx.contributor, ctx.org_a, metric!(ctx.org_a, "G1-M1"))

      other_period =
        Ash.create!(
          Emisint.Improvement.ReportingPeriod,
          %{
            goal_plan_id: ctx.other_metric.goal_plan_id,
            code: "fal_26",
            label: "Fal '26",
            kind: :seasonal,
            position: 1
          },
          tenant: ctx.org_a.id,
          authorize?: false
        )

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 ActualResult,
                 %{
                   metric_id: ctx.other_metric.id,
                   reporting_period_id: other_period.id,
                   value_state: :exact,
                   value: Decimal.new("0.5"),
                   measurement_date: ~D[2026-10-01]
                 },
                 action: :record,
                 tenant: ctx.org_a.id,
                 actor: ctx.contributor
               )
    end

    test "viewers, non-members and other orgs' admins cannot record", ctx do
      metric = metric!(ctx.org_a, "G1-M1")

      for actor <- [ctx.viewer, ctx.no_membership, ctx.liaison, ctx.admin_b] do
        assert {:error, %Ash.Error.Forbidden{}} = record(actor, ctx.org_a, metric)
      end
    end

    test "org admins and system admins can record", ctx do
      assert {:ok, _} = record(ctx.admin_a, ctx.org_a, metric!(ctx.org_a, "G1-M1"))
      assert {:ok, _} = record(ctx.system_admin, ctx.org_b, metric!(ctx.org_b, "G1-M1"))
    end

    test "forged IDs from another organization are not found", ctx do
      foreign_metric = metric!(ctx.org_a, "G1-M1")
      own_period = period!(ctx.org_b, "fal_26")

      assert {:error, error} =
               Ash.create(
                 ActualResult,
                 %{
                   metric_id: foreign_metric.id,
                   reporting_period_id: own_period.id,
                   value_state: :exact,
                   value: Decimal.new("0.5"),
                   measurement_date: ~D[2026-10-01]
                 },
                 action: :record,
                 tenant: ctx.org_b.id,
                 actor: ctx.admin_b
               )

      assert :metric_id in error_fields(error)
    end

    test "a period from another organization is not found", ctx do
      own_metric = metric!(ctx.org_b, "G1-M1")
      foreign_period = period!(ctx.org_a, "fal_26")

      assert {:error, error} =
               Ash.create(
                 ImplementationRating,
                 %{
                   metric_id: own_metric.id,
                   reporting_period_id: foreign_period.id,
                   rating_state: :rated,
                   score: 1
                 },
                 action: :record,
                 tenant: ctx.org_b.id,
                 actor: ctx.admin_b
               )

      assert :reporting_period_id in error_fields(error)
    end

    test "a correction link to another organization's entry is not found", ctx do
      {:ok, foreign_entry} = record(ctx.admin_a, ctx.org_a, metric!(ctx.org_a, "G1-M1"))

      assert {:error, error} =
               Ash.create(
                 ActualResult,
                 %{
                   corrects_id: foreign_entry.id,
                   correction_reason: "forged",
                   value_state: :exact,
                   value: Decimal.new("0.1"),
                   measurement_date: ~D[2026-10-01]
                 },
                 action: :correct,
                 tenant: ctx.org_b.id,
                 actor: ctx.admin_b
               )

      assert :corrects_id in error_fields(error)
    end

    test "contributors cannot correct another school's entry", ctx do
      other_period =
        Ash.create!(
          Emisint.Improvement.ReportingPeriod,
          %{
            goal_plan_id: ctx.other_metric.goal_plan_id,
            code: "fal_26",
            label: "Fal '26",
            kind: :seasonal,
            position: 1
          },
          tenant: ctx.org_a.id,
          authorize?: false
        )

      {:ok, other_entry} =
        Ash.create(
          ActualResult,
          %{
            metric_id: ctx.other_metric.id,
            reporting_period_id: other_period.id,
            value_state: :exact,
            value: Decimal.new("0.5"),
            measurement_date: ~D[2026-10-01]
          },
          action: :record,
          tenant: ctx.org_a.id,
          actor: ctx.admin_a
        )

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 ActualResult,
                 %{
                   corrects_id: other_entry.id,
                   correction_reason: "not mine",
                   value_state: :exact,
                   value: Decimal.new("0.1"),
                   measurement_date: ~D[2026-10-01]
                 },
                 action: :correct,
                 tenant: ctx.org_a.id,
                 actor: ctx.contributor
               )
    end

    test "definitions cannot be created by non-system-admins", ctx do
      goal =
        Goal
        |> Ash.Query.filter(number == 1 and school_id == ^school!(ctx.org_a).id)
        |> Ash.read_one!(tenant: ctx.org_a.id, authorize?: false)

      attrs = %{
        goal_id: goal.id,
        code: "G1-M9",
        description: "x",
        category: :systems,
        direction: :higher_is_better,
        position: 99
      }

      for actor <- [ctx.contributor, ctx.admin_a] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Ash.create(Metric, attrs, tenant: ctx.org_a.id, actor: actor)
      end
    end
  end

  describe "memberships" do
    test "org admins can grant access; contributors cannot", ctx do
      user = user!(ctx.org_a, :school_leader)
      attrs = %{user_id: user.id, school_id: ctx.other_school.id, role: :viewer}

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(SchoolMembership, attrs, tenant: ctx.org_a.id, actor: ctx.contributor)

      assert {:ok, _} =
               Ash.create(SchoolMembership, attrs, tenant: ctx.org_a.id, actor: ctx.admin_a)
    end

    test "a user from another organization cannot be granted membership", ctx do
      outsider = user!(ctx.org_b, :school_leader)

      assert {:error, error} =
               Ash.create(
                 SchoolMembership,
                 %{user_id: outsider.id, school_id: school!(ctx.org_a).id, role: :viewer},
                 tenant: ctx.org_a.id,
                 actor: ctx.admin_a
               )

      assert :user_id in error_fields(error)
    end

    test "a school from another organization cannot be referenced", ctx do
      user = user!(ctx.org_b, :school_leader)

      assert {:error, error} =
               Ash.create(
                 SchoolMembership,
                 %{user_id: user.id, school_id: school!(ctx.org_a).id, role: :viewer},
                 tenant: ctx.org_b.id,
                 actor: ctx.admin_b
               )

      assert :school_id in error_fields(error)
    end

    test "members see only their own memberships", ctx do
      assert [membership] =
               Ash.read!(SchoolMembership, tenant: ctx.org_a.id, actor: ctx.contributor)

      assert membership.user_id == ctx.contributor.id
      assert length(Ash.read!(SchoolMembership, tenant: ctx.org_a.id, actor: ctx.admin_a)) == 2
    end
  end
end
