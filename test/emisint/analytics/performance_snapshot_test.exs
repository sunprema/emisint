defmodule Emisint.Analytics.PerformanceSnapshotTest do
  use Emisint.DataCase, async: true

  alias Emisint.Accounts.School
  alias Emisint.Analytics.PerformanceSnapshot
  alias Emisint.Registry.AcademicYear

  defp org_id, do: Ash.UUID.generate()

  defp create_school(oid) do
    Ash.create!(School,
      %{name: "Snapshot Academy", mde_district_code: "25010", mde_building_code: "08001"},
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

  defp school_wide_attrs(school, year) do
    %{
      snapshot_type: :school_wide,
      subject: "math",
      testing_window: :fall,
      school_id: school.id,
      academic_year_id: year.id,
      proficiency_rate: Decimal.new("0.72"),
      student_count: 100
    }
  end

  describe "create" do
    test "creates a school-wide snapshot with defaults" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      snap = Ash.create!(PerformanceSnapshot, school_wide_attrs(school, year), tenant: oid, authorize?: false)

      assert snap.snapshot_type == :school_wide
      assert snap.grade_level == "all"
      assert snap.subgroup == :all
      assert snap.subject == "math"
      assert snap.testing_window == :fall
      assert Decimal.equal?(snap.proficiency_rate, Decimal.new("0.72"))
    end

    test "creates a by_grade snapshot" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      snap =
        Ash.create!(PerformanceSnapshot,
          %{
            snapshot_type: :by_grade,
            subject: "reading",
            grade_level: "g5",
            testing_window: :winter,
            school_id: school.id,
            academic_year_id: year.id,
            student_count: 25
          },
          tenant: oid,
          authorize?: false
        )

      assert snap.snapshot_type == :by_grade
      assert snap.grade_level == "g5"
    end
  end

  describe ":upsert action" do
    test "upserts on the unique identity — updates existing snapshot" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)
      attrs = school_wide_attrs(school, year)

      Ash.create!(PerformanceSnapshot, attrs, action: :upsert, tenant: oid, authorize?: false)

      updated_attrs = Map.merge(attrs, %{proficiency_rate: Decimal.new("0.85"), student_count: 110})
      Ash.create!(PerformanceSnapshot, updated_attrs, action: :upsert, tenant: oid, authorize?: false)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      assert length(snaps) == 1
      assert Decimal.equal?(hd(snaps).proficiency_rate, Decimal.new("0.85"))
      assert hd(snaps).student_count == 110
    end

    test "creates separate snapshots for different subjects" do
      oid = org_id()
      school = create_school(oid)
      year = create_year(oid)

      math_attrs = school_wide_attrs(school, year)
      reading_attrs = Map.put(math_attrs, :subject, "reading")

      Ash.create!(PerformanceSnapshot, math_attrs, action: :upsert, tenant: oid, authorize?: false)
      Ash.create!(PerformanceSnapshot, reading_attrs, action: :upsert, tenant: oid, authorize?: false)

      snaps = Ash.read!(PerformanceSnapshot, tenant: oid, authorize?: false)
      assert length(snaps) == 2
    end
  end

  describe "multitenancy" do
    test "snapshots are isolated per org" do
      oid_a = org_id()
      oid_b = org_id()

      school_a = create_school(oid_a)
      year_a = create_year(oid_a)
      Ash.create!(PerformanceSnapshot, school_wide_attrs(school_a, year_a), tenant: oid_a, authorize?: false)

      school_b =
        Ash.create!(School,
          %{name: "Other Academy", mde_district_code: "25010", mde_building_code: "08002"},
          tenant: oid_b,
          authorize?: false
        )

      year_b = create_year(oid_b)
      Ash.create!(PerformanceSnapshot, school_wide_attrs(school_b, year_b), tenant: oid_b, authorize?: false)

      assert length(Ash.read!(PerformanceSnapshot, tenant: oid_a, authorize?: false)) == 1
      assert length(Ash.read!(PerformanceSnapshot, tenant: oid_b, authorize?: false)) == 1
    end
  end
end
