defmodule Emisint.Registry.AcademicYearTest do
  use Emisint.DataCase, async: true

  alias Emisint.Registry.AcademicYear

  defp org_id, do: Ash.UUID.generate()

  defp create_year(oid, label \\ "2024-2025") do
    Ash.create!(
      AcademicYear,
      %{label: label, start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
      tenant: oid,
      authorize?: false
    )
  end

  describe "create/1" do
    test "creates an academic year with required attrs" do
      oid = org_id()

      assert {:ok, year} =
               Ash.create(
                 AcademicYear,
                 %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
                 tenant: oid,
                 authorize?: false
               )

      assert year.label == "2024-2025"
      assert year.start_date == ~D[2024-09-03]
      assert year.active == true
      assert year.organization_id == oid
    end

    test "creates with all testing window columns" do
      oid = org_id()

      assert {:ok, year} =
               Ash.create(
                 AcademicYear,
                 %{
                   label: "2024-2025",
                   start_date: ~D[2024-09-03],
                   end_date: ~D[2025-06-13],
                   fall_window_start: ~D[2024-09-09],
                   fall_window_end: ~D[2024-10-04],
                   winter_window_start: ~D[2025-01-06],
                   winter_window_end: ~D[2025-01-31],
                   spring_window_start: ~D[2025-04-07],
                   spring_window_end: ~D[2025-05-02]
                 },
                 tenant: oid,
                 authorize?: false
               )

      assert year.fall_window_start == ~D[2024-09-09]
      assert year.spring_window_end == ~D[2025-05-02]
    end

    test "requires label" do
      assert {:error, error} =
               Ash.create(
                 AcademicYear,
                 %{start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
                 tenant: org_id(),
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :label))
    end

    test "enforces unique label per org" do
      oid = org_id()
      create_year(oid)

      assert {:error, error} =
               Ash.create(
                 AcademicYear,
                 %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]},
                 tenant: oid,
                 authorize?: false
               )

      assert error.errors |> Enum.any?(&(&1.field == :label))
    end

    test "same label is allowed for different orgs" do
      assert {:ok, _} = Ash.create(AcademicYear, %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]}, tenant: org_id(), authorize?: false)
      assert {:ok, _} = Ash.create(AcademicYear, %{label: "2024-2025", start_date: ~D[2024-09-03], end_date: ~D[2025-06-13]}, tenant: org_id(), authorize?: false)
    end
  end

  describe "multitenancy" do
    test "read is scoped to organization_id" do
      oid1 = org_id()
      oid2 = org_id()

      create_year(oid1)
      create_year(oid2)

      {:ok, results} = Ash.read(AcademicYear, tenant: oid1, authorize?: false)

      assert length(results) == 1
      assert hd(results).organization_id == oid1
    end
  end

  describe "update/1" do
    test "updates active flag" do
      oid = org_id()
      year = create_year(oid, "2023-2024")

      assert {:ok, updated} = Ash.update(year, %{active: false}, tenant: oid, authorize?: false)
      assert updated.active == false
    end
  end
end
