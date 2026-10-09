defmodule Emisint.Assessments.CrdComparison do
  @moduledoc """
  Composite Resident District (CRD) comparison math, shared by the district
  detail page, the authorizer portfolio CRD Dashboard, and the CRD PDF so the
  "CRD Delta" is computed one way everywhere.

  CRD Delta = charter all-subjects M-STEP proficiency
            − enrollment-weighted composite of its resident districts

  The charter side is an unweighted mean of the four scored subjects. The
  composite side is the unweighted mean of four enrollment-weighted subject
  means, where the weight is `nonresident_students_enrolled` from
  `MdeCompositeResidentDistrict`. Every intermediate value is rounded to one
  decimal, matching the detail page's historical behaviour exactly.

  Resident districts are resolved through the importer-populated
  `mde_district_id`, never the unreliable `crd_district_code`. Districts with
  no `MdeDistrictSnapshot` for the year are counted but excluded from the
  weighted composite.
  """

  require Ash.Query

  alias Emisint.Assessments.{MdeCompositeResidentDistrict, MdeDistrict, MdeDistrictSnapshot}

  @subjects ["ELA", "Mathematics", "Science", "Social Studies"]

  @doc "The M-STEP subjects that feed the all-subjects average."
  def subjects, do: @subjects

  # ---------------------------------------------------------------------------
  # Pure math
  # ---------------------------------------------------------------------------

  @doc """
  Enrollment-weighted mean of one subject across resident rows.

  Each row is `%{subjects: %{subject => Decimal | nil}, weight: integer}`.
  Rows with a nil value for the subject contribute neither score nor weight.
  Returns a one-decimal `Decimal`, or nil when no row has the subject.
  """
  def weighted_subject(rows, subject) do
    {weighted_sum, weight} =
      Enum.reduce(rows, {0.0, 0}, fn rd, {sum, w} ->
        case Map.get(rd.subjects, subject) do
          nil -> {sum, w}
          d -> {sum + to_float(d) * rd.weight, w + rd.weight}
        end
      end)

    if weight > 0, do: Decimal.from_float(Float.round(weighted_sum / weight, 1)), else: nil
  end

  @doc """
  Unweighted mean of the non-nil values in a `%{subject => Decimal}` map,
  rounded to one decimal. Returns nil for an empty or all-nil map.
  """
  def avg_of_subjects(map) when is_map(map) do
    vals =
      map
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_float/1)

    case vals do
      [] -> nil
      list -> Decimal.from_float(Float.round(Enum.sum(list) / length(list), 1))
    end
  end

  def avg_of_subjects(_), do: nil

  @doc """
  `%{subject => weighted Decimal}` across the scored resident rows for every
  subject in `subjects/0`.
  """
  def composite_subjects(scored_rows) do
    Map.new(@subjects, fn s -> {s, weighted_subject(scored_rows, s)} end)
  end

  @doc """
  The CRD Delta as a one-decimal float: `charter_avg − composite_avg`.
  Returns nil when either side is nil.
  """
  def delta(nil, _composite_avg), do: nil
  def delta(_charter_avg, nil), do: nil

  def delta(charter_avg, composite_avg) do
    Float.round(to_float(charter_avg) - to_float(composite_avg), 1)
  end

  # ---------------------------------------------------------------------------
  # Portfolio loader
  # ---------------------------------------------------------------------------

  @doc """
  CRD Delta for every charter district in `charter_codes` for the assessment
  `year`, in two database reads regardless of portfolio size.

  Returns one row per charter code:

      %{
        district_code: "81902",
        district_name: "Central Academy",
        charter_avg: Decimal | nil,
        composite_avg: Decimal | nil,
        delta: float | nil,
        resident_count: 12,
        scored_count: 10,
        total_students: 384,
        excluded?: false,
        exclusion_reason: nil | String.t()
      }

  Rows with a delta come first, sorted best to worst; excluded rows follow,
  sorted by name.
  """
  def portfolio_deltas([], _year), do: []

  def portfolio_deltas(charter_codes, year) do
    charter_codes = charter_codes |> Enum.reject(&is_nil/1) |> Enum.uniq()

    crd_rows =
      MdeCompositeResidentDistrict
      |> Ash.Query.filter(charter_district_code in ^charter_codes)
      |> Ash.Query.load(:mde_district)
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.charter_district_code)

    resident_codes =
      crd_rows
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&resident_code/1)
      |> Enum.reject(&is_nil/1)

    snapshots =
      MdeDistrictSnapshot
      |> Ash.Query.select([:district_code, :district_name, :all_subjects])
      |> Ash.Query.filter(
        district_code in ^Enum.uniq(charter_codes ++ resident_codes) and school_year == ^year
      )
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.district_code, &1})

    names = fallback_names(charter_codes, crd_rows, snapshots)

    charter_codes
    |> Enum.map(&build_row(&1, Map.get(crd_rows, &1, []), snapshots, names))
    |> sort_rows()
  end

  # Excluded charters have no snapshot to take a name from. Use the CRD
  # import's charter_entity_name where there are CRD rows, and look the rest
  # up in MdeDistrict (usually zero to two codes, so a third read is cheap).
  defp fallback_names(charter_codes, crd_rows, snapshots) do
    from_crd =
      Map.new(crd_rows, fn {code, rows} ->
        {code, Enum.find_value(rows, &present(&1.charter_entity_name))}
      end)

    missing =
      Enum.reject(charter_codes, fn code ->
        Map.has_key?(snapshots, code) or Map.get(from_crd, code)
      end)

    from_district =
      if missing == [] do
        %{}
      else
        MdeDistrict
        |> Ash.Query.select([:district_code, :district_name])
        |> Ash.Query.filter(district_code in ^missing)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.district_code, present(&1.district_name)})
      end

    Map.merge(from_district, from_crd, fn _k, d, c -> c || d end)
  end

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(s) when is_binary(s), do: String.trim(s) |> present_trimmed()

  defp present_trimmed(""), do: nil
  defp present_trimmed(s), do: s

  defp build_row(code, rows, snapshots, names) do
    charter_snap = Map.get(snapshots, code)
    charter_subjects = subjects_from_snapshot(charter_snap)
    charter_avg = avg_of_subjects(charter_subjects)

    residents =
      Enum.map(rows, fn r ->
        resident_snap = snapshots[resident_code(r)]

        %{
          weight: r.nonresident_students_enrolled || 0,
          subjects: subjects_from_snapshot(resident_snap),
          has_data: not is_nil(resident_snap)
        }
      end)

    scored = Enum.filter(residents, & &1.has_data)
    composite_avg = scored |> composite_subjects() |> avg_of_subjects()
    delta = delta(charter_avg, composite_avg)

    exclusion_reason =
      cond do
        rows == [] -> "No CRD data"
        is_nil(charter_snap) -> "No M-STEP snapshot for this year"
        is_nil(charter_avg) -> "No scored subjects for this year"
        scored == [] -> "No resident district has M-STEP data"
        is_nil(composite_avg) -> "Resident districts have no scored subjects"
        true -> nil
      end

    %{
      district_code: code,
      district_name:
        (charter_snap && present(charter_snap.district_name)) || Map.get(names, code) || code,
      charter_avg: charter_avg,
      composite_avg: composite_avg,
      delta: delta,
      resident_count: length(residents),
      scored_count: length(scored),
      total_students: Enum.sum(Enum.map(scored, & &1.weight)),
      excluded?: is_nil(delta),
      exclusion_reason: exclusion_reason
    }
  end

  defp sort_rows(rows) do
    {scored, excluded} = Enum.split_with(rows, &(not &1.excluded?))

    Enum.sort_by(scored, & &1.delta, :desc) ++
      Enum.sort_by(excluded, &String.downcase(&1.district_name))
  end

  defp resident_code(%{mde_district: %{district_code: code}}), do: code
  defp resident_code(_), do: nil

  defp subjects_from_snapshot(nil), do: %{}
  defp subjects_from_snapshot(%{all_subjects: nil}), do: %{}

  defp subjects_from_snapshot(%{all_subjects: map}) do
    Map.new(map, fn {k, v} -> {k, to_decimal(v)} end)
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)
  defp to_decimal(i) when is_integer(i), do: Decimal.new(i)

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(f) when is_float(f), do: f
  defp to_float(i) when is_integer(i), do: i * 1.0
end
