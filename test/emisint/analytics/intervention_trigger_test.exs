defmodule Emisint.Analytics.InterventionTriggerTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Analytics.InterventionTrigger
  alias Emisint.Registry.AcademicYear

  defp org_id, do: Ash.UUID.generate()

  defp create_school(oid) do
    Ash.create!(School,
      %{name: "Trigger Academy", mde_district_code: "25010", mde_building_code: "08001"},
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

  defp create_trigger(oid, school, year, attrs \\ %{}) do
    Ash.create!(InterventionTrigger,
      Map.merge(
        %{
          trigger_type: :goal_at_risk,
          severity: :high,
          triggered_at: DateTime.utc_now(),
          school_id: school.id,
          academic_year_id: year.id
        },
        attrs
      ),
      tenant: oid,
      authorize?: false
    )
  end

  describe "create" do
    test "creates an active trigger by default" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      trigger = create_trigger(oid, school, year)

      assert trigger.status == :active
      assert trigger.trigger_type == :goal_at_risk
      assert trigger.severity == :high
    end

    test "supports all trigger_type values" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      for type <- [:proficiency_declining, :sgp_below_target, :growth_at_risk, :goal_at_risk] do
        t = create_trigger(oid, school, year, %{trigger_type: type})
        assert t.trigger_type == type
      end
    end

    test "supports all severity values" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      for sev <- [:high, :medium, :low] do
        t = create_trigger(oid, school, year, %{severity: sev})
        assert t.severity == sev
      end
    end
  end

  describe ":resolve transition" do
    test "transitions from active to resolved" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      trigger = create_trigger(oid, school, year)

      resolved =
        Ash.update!(trigger,
          %{resolved_at: DateTime.utc_now(), notes: "Goal met in spring window"},
          action: :resolve,
          tenant: oid,
          authorize?: false
        )

      assert resolved.status == :resolved
      assert resolved.resolved_at != nil
      assert resolved.notes == "Goal met in spring window"
    end
  end

  describe ":dismiss transition" do
    test "transitions from active to dismissed" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      trigger = create_trigger(oid, school, year)

      dismissed =
        Ash.update!(trigger,
          %{notes: "Data error — dismissed by admin"},
          action: :dismiss,
          tenant: oid,
          authorize?: false
        )

      assert dismissed.status == :dismissed
    end
  end

  describe ":reactivate transition" do
    test "transitions from resolved back to active" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      trigger = create_trigger(oid, school, year)

      resolved =
        Ash.update!(trigger, %{resolved_at: DateTime.utc_now()},
          action: :resolve, tenant: oid, authorize?: false)

      reactivated =
        Ash.update!(resolved, %{}, action: :reactivate, tenant: oid, authorize?: false)

      assert reactivated.status == :active
    end

    test "transitions from dismissed back to active" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      trigger = create_trigger(oid, school, year)

      dismissed =
        Ash.update!(trigger, %{}, action: :dismiss, tenant: oid, authorize?: false)

      reactivated =
        Ash.update!(dismissed, %{}, action: :reactivate, tenant: oid, authorize?: false)

      assert reactivated.status == :active
    end
  end

  describe ":update action" do
    test "updates severity on an existing trigger" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      trigger = create_trigger(oid, school, year, %{severity: :medium})

      updated =
        Ash.update!(trigger, %{severity: :high}, tenant: oid, authorize?: false)

      assert updated.severity == :high
    end
  end

  describe "multitenancy" do
    test "triggers are isolated per org" do
      oid_a = org_id()
      oid_b = org_id()

      school_a = create_school(oid_a)
      year_a = create_year(oid_a)
      create_trigger(oid_a, school_a, year_a)

      school_b =
        Ash.create!(School,
          %{name: "Other Acad", mde_district_code: "25010", mde_building_code: "08002"},
          tenant: oid_b,
          authorize?: false
        )

      year_b = create_year(oid_b)
      create_trigger(oid_b, school_b, year_b)

      assert length(Ash.read!(InterventionTrigger, tenant: oid_a, authorize?: false)) == 1
      assert length(Ash.read!(InterventionTrigger, tenant: oid_b, authorize?: false)) == 1
    end
  end
end
