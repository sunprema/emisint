defmodule Emisint.Assessments.MdeCompositeResidentDistrictImporterTest do
  use Emisint.DataCase, async: false

  require Ash.Query

  alias Emisint.Assessments.MdeCompositeResidentDistrict
  alias Emisint.Assessments.MdeCompositeResidentDistrictImporter, as: Importer
  alias Emisint.Assessments.MdeDistrict

  @header "School Year,Entity Name,District Code,Other Entity Name,CRD District Code,Grade,Number of Nonresident Students Enrolled"

  defp write_csv(rows) do
    path = Path.join(System.tmp_dir!(), "crd_test_#{System.unique_integer([:positive])}.csv")
    File.write!(path, Enum.join([@header | rows], "\n") <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp seed_districts do
    Ash.create!(
      MdeDistrict,
      %{district_code: "63300", district_name: "Waterford School District"}, authorize?: false)

    Ash.create!(MdeDistrict, %{district_code: "47010", district_name: "Brighton Area Schools"},
      authorize?: false
    )
  end

  defp all_rows do
    MdeCompositeResidentDistrict
    |> Ash.read!(authorize?: false)
  end

  defp row_by_crd(code) do
    MdeCompositeResidentDistrict
    |> Ash.Query.filter(crd_district_code == ^code)
    |> Ash.read_one!(authorize?: false)
  end

  describe "import_file/1" do
    test "imports rows, resolves districts by name, and reports stats" do
      seed_districts()

      path =
        write_csv([
          # leading-zero charter code, exact name → matched
          "2025-26,AGBU,063901,Waterford School District,33330,All Grades K-12,8",
          # uppercase name → still matched (case/whitespace-insensitive)
          "2025-26,AGBU,63901,BRIGHTON AREA SCHOOLS,47010,All Grades K-12,1",
          # no matching district → imported with nil mde_district_id
          "2025-26,AGBU,63901,Nonexistent District,99999,All Grades K-12,3"
        ])

      assert {:ok, stats} = Importer.import_file(path)

      assert stats.records == 3
      assert stats.matched == 2
      assert stats.unmatched == 1
      assert stats.errors == 0
      assert stats.error_file == nil

      assert length(all_rows()) == 3
    end

    test "normalizes the charter code, stores the CRD code raw, and parses the count as integer" do
      seed_districts()

      path =
        write_csv(["2025-26,AGBU,063901,Waterford School District,33330,All Grades K-12,8"])

      assert {:ok, _stats} = Importer.import_file(path)

      row = row_by_crd("33330")
      # leading zero stripped to match mde_districts convention
      assert row.charter_district_code == "63901"
      # CRD code is stored exactly as given (it is NOT an MDE code)
      assert row.crd_district_code == "33330"
      assert row.nonresident_students_enrolled == 8
      assert is_integer(row.nonresident_students_enrolled)
    end

    test "resolves mde_district_id by name and leaves it nil when there is no match" do
      seed_districts()
      waterford = waterford_district()

      path =
        write_csv([
          "2025-26,AGBU,63901,Waterford School District,33330,All Grades K-12,8",
          "2025-26,AGBU,63901,Nonexistent District,99999,All Grades K-12,3"
        ])

      assert {:ok, _stats} = Importer.import_file(path)

      assert row_by_crd("33330").mde_district_id == waterford.id
      assert row_by_crd("99999").mde_district_id == nil
    end

    test "is idempotent and updates non-key fields on re-import (upsert on composite key)" do
      seed_districts()

      path1 = write_csv(["2025-26,AGBU,63901,Waterford School District,33330,All Grades K-12,8"])
      assert {:ok, _} = Importer.import_file(path1)
      assert length(all_rows()) == 1
      assert row_by_crd("33330").nonresident_students_enrolled == 8

      # same composite key, different count → updates in place, no new row
      path2 = write_csv(["2025-26,AGBU,63901,Waterford School District,33330,All Grades K-12,42"])
      assert {:ok, _} = Importer.import_file(path2)
      assert length(all_rows()) == 1
      assert row_by_crd("33330").nonresident_students_enrolled == 42
    end

    test "handles a UTF-8 BOM on the header row" do
      seed_districts()

      path = Path.join(System.tmp_dir!(), "crd_bom_#{System.unique_integer([:positive])}.csv")

      File.write!(
        path,
        "﻿" <>
          @header <>
          "\n2025-26,AGBU,63901,Waterford School District,33330,All Grades K-12,8\n"
      )

      on_exit(fn -> File.rm(path) end)

      assert {:ok, stats} = Importer.import_file(path)
      assert stats.records == 1
      assert row_by_crd("33330").school_year == "2025-26"
    end

    test "returns an error tuple when the file does not exist" do
      assert {:error, msg} = Importer.import_file("/nope/missing.csv")
      assert msg =~ "File not found"
    end
  end

  defp waterford_district do
    MdeDistrict
    |> Ash.Query.filter(district_code == "63300")
    |> Ash.read_one!(authorize?: false)
  end
end
