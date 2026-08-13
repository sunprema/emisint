defmodule Emisint.Reports.School.CrdComparisonPdf do
  @moduledoc """
  Generates the Composite Resident District (CRD) Comparison PDF for a charter
  (district_code) and school year.

  Compares the charter's own M-STEP proficiency and SAT averages against the
  enrollment-weighted composite of the districts its nonresident students would
  otherwise attend — at two scopes: all resident districts and the top 10 by
  enrollment.

  Resident districts are joined to MdeDistrict by the importer-resolved
  `mde_district_id` (the CRD code is unreliable). Scores come from the same
  MdeDistrictSnapshot / MdeSatResult rollups used by the live dashboard.
  """

  @template_path "priv/typst/school/crd_comparison.typ"
  @top_n 10
  @subject_keys [
    {"ELA", :ela},
    {"Mathematics", :math},
    {"Science", :sci},
    {"Social Studies", :ss}
  ]

  require Ash.Query

  alias Emisint.Assessments.{
    MdeCompositeResidentDistrict,
    MdeDistrictSnapshot,
    MdeEntityMaster,
    MdeSatResult
  }

  @spec generate_report(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate_report(district_code, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(district_code, year)

    config =
      Imprintor.Config.new(template, data,
        root_directory: Application.app_dir(:emisint, "priv/typst")
      )

    Imprintor.compile_to_pdf(config)
  end

  # --- Data assembly ---

  defp build_data(district_code, year) do
    rows =
      MdeCompositeResidentDistrict
      |> Ash.Query.filter(charter_district_code == ^district_code)
      |> Ash.Query.load(:mde_district)
      |> Ash.Query.sort(nonresident_students_enrolled: :desc)
      |> Ash.read!(authorize?: false)

    charter_snap = load_snapshot(district_code, year)
    charter_sat = sat_map(load_sat(district_code, year))
    entity_details = load_entity_details(district_code)

    residents =
      Enum.map(rows, fn r ->
        code = r.mde_district && r.mde_district.district_code
        snap = if code, do: load_snapshot(code, year)
        sat = sat_map(if code, do: load_sat(code, year))
        mstep = subjects_map(snap)

        %{
          name: r.resident_entity_name,
          students: r.nonresident_students_enrolled || 0,
          mstep: mstep,
          mstep_avg: avg_floats(Map.values(mstep)),
          sat: sat,
          has_mstep: not is_nil(snap),
          has_sat: not is_nil(sat)
        }
      end)

    all_scope = scope_summary(residents)
    top10_scope = scope_summary(Enum.take(residents, @top_n))

    charter_mstep = subjects_map(charter_snap)

    %{
      school: %{
        name:
          (charter_snap && charter_snap.district_name) || entity_details.name || district_code,
        district_code: district_code,
        report_date: Date.utc_today() |> Calendar.strftime("%b %d, %Y")
      },
      entity_details: entity_details,
      school_year: year,
      total_residents: length(rows),
      has_any_sat: not is_nil(charter_sat) or all_scope.sat_districts > 0,
      charter: %{
        mstep: Map.put(charter_mstep, :avg, avg_floats(Map.values(charter_mstep))),
        sat: charter_sat || %{math: nil, ebrw: nil, all: nil}
      },
      scopes: %{all: all_scope, top10: top10_scope},
      residents: Enum.map(residents, &resident_row/1)
    }
  end

  defp scope_summary(residents) do
    mstep_scored = Enum.filter(residents, & &1.has_mstep)
    sat_scored = Enum.filter(residents, & &1.has_sat)

    mstep = %{
      ela: weighted(mstep_scored, & &1.mstep.ela),
      math: weighted(mstep_scored, & &1.mstep.math),
      sci: weighted(mstep_scored, & &1.mstep.sci),
      ss: weighted(mstep_scored, & &1.mstep.ss)
    }

    %{
      districts: length(residents),
      mstep_districts: length(mstep_scored),
      mstep_students: Enum.sum(Enum.map(mstep_scored, & &1.students)),
      mstep: Map.put(mstep, :avg, avg_floats(Map.values(mstep))),
      sat_districts: length(sat_scored),
      sat_students: Enum.sum(Enum.map(sat_scored, & &1.students)),
      sat: %{
        math: weighted(sat_scored, & &1.sat.math),
        ebrw: weighted(sat_scored, & &1.sat.ebrw),
        all: weighted(sat_scored, & &1.sat.all)
      }
    }
  end

  defp resident_row(r) do
    %{
      name: r.name,
      students: r.students,
      ela: r.mstep.ela,
      math: r.mstep.math,
      sci: r.mstep.sci,
      ss: r.mstep.ss,
      mstep_avg: r.mstep_avg,
      sat_math: r.sat && r.sat.math,
      sat_ebrw: r.sat && r.sat.ebrw,
      sat_all: r.sat && r.sat.all,
      has_mstep: r.has_mstep,
      has_sat: r.has_sat
    }
  end

  # --- Loaders ---

  defp load_snapshot(district_code, year) do
    MdeDistrictSnapshot
    |> Ash.Query.filter(district_code == ^district_code and school_year == ^year)
    |> Ash.read_one!(authorize?: false)
  end

  defp load_sat(district_code, year) do
    MdeSatResult
    |> Ash.Query.filter(
      district_code == ^district_code and school_year == ^year and
        rollup_level == :district and subgroup == "All Students"
    )
    |> Ash.read_one!(authorize?: false)
  end

  @entity_select [
    :entity_official_name,
    :isd_code,
    :isd_official_name,
    :entity_type_name,
    :entity_county_name,
    :entity_chartering_agency_code,
    :entity_chartering_agency_name,
    :entity_authorized_grades,
    :entity_actual_grades
  ]

  # The charter PSA's MDE entity record. A multi-building PSA may have several
  # rows sharing district_code; the district-level fields (ISD, agency, grades)
  # are identical across them, so the first row is fine.
  defp load_entity_details(district_code) do
    record =
      MdeEntityMaster
      |> Ash.Query.filter(district_code == ^district_code)
      |> Ash.Query.select(@entity_select)
      |> Ash.Query.sort(:entity_code)
      |> Ash.read!(authorize?: false)
      |> List.first()

    %{
      name: record && record.entity_official_name,
      isd_code: record && record.isd_code,
      isd_official_name: record && record.isd_official_name,
      entity_type_name: record && record.entity_type_name,
      county_name: record && record.entity_county_name,
      chartering_agency_code: record && record.entity_chartering_agency_code,
      chartering_agency_name: record && record.entity_chartering_agency_name,
      authorized_grades: record && record.entity_authorized_grades,
      actual_grades: record && record.entity_actual_grades
    }
  end

  # --- Shape helpers ---

  defp subjects_map(nil), do: %{ela: nil, math: nil, sci: nil, ss: nil}

  defp subjects_map(snap) do
    subjects = snap.all_subjects || %{}
    Map.new(@subject_keys, fn {name, key} -> {key, to_float(Map.get(subjects, name))} end)
  end

  defp sat_map(nil), do: nil

  defp sat_map(row) do
    %{
      math: to_float(row.math_score_average),
      ebrw: to_float(row.ebrw_score_average),
      all: to_float(row.all_subject_score_average)
    }
  end

  # Enrollment-weighted mean of one accessor across the given rows.
  defp weighted(rows, fun) do
    {sum, weight} =
      Enum.reduce(rows, {0.0, 0}, fn item, {acc, w} ->
        case fun.(item) do
          nil -> {acc, w}
          v -> {acc + v * item.students, w + item.students}
        end
      end)

    if weight > 0, do: Float.round(sum / weight, 1), else: nil
  end

  defp avg_floats(values) do
    nums = Enum.reject(values, &is_nil/1)
    if nums == [], do: nil, else: Float.round(Enum.sum(nums) / length(nums), 1)
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_float(v), do: v

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end
end
