defmodule Emisint.NdInsights.Parser do
  @moduledoc """
  Parses official ND Insights CSV downloads (https://insights.nd.gov/Data)
  into one observation per published measure.

  Verified against the 2021-22 … 2024-25 downloads (see `PLAN_nd_first.md`):

    * **Assessment Performance** — `NoviceRangeLow/High`, `PartiallyRangeLow/High`,
      `ProficientRangeLow/High`, `AdvancedRangeLow/High` (proportions). The CSV
      level "Partially" is shown on the Insights website as
      "Approaching Proficiency".
    * **Assessment Participation** — `PercentTestedRangeLow/High`.
    * **Growth Rate** — `DoesNotMeet`, `Approaches`, `Meets`, `Exceeds` ranges,
      plus `OverallGrowthLevel` (an ordinal level) and `OverallGrowthPercentile`.
    * **Engagement Survey** — one file per area, wide by academic year; cells
      are `"0.30-0.34"` ranges or exact proportions.

  Values are kept exactly as published:

    * low == high → `:exact`; low < high → `:range` (never a midpoint);
    * an empty cell or `*` → `:suppressed` (the Data page states that
      "In cases where data is suppressed, an asterisk (*) or an empty cell is
      shown"); the verbatim cell is kept in `source_text`;
    * groups the state did not publish have **no row at all** and produce no
      observation.

  Only rows whose `InstitutionID` is in `:institution_ids` are returned, but
  every source dimension is retained for later portfolio use.
  """

  NimbleCSV.define(__MODULE__.CSV, separator: ",", escape: "\"")

  @range_measures %{
    assessment_performance: ~w(Novice Partially Proficient Advanced),
    assessment_participation: ~w(PercentTested),
    growth_rate: ~w(DoesNotMeet Approaches Meets Exceeds)
  }

  @dimension_columns %{
    assessment_performance:
      ~w(AcademicYear InstitutionName InstitutionID Grade Subject AssessmentType Accomodations Subgroup),
    assessment_participation:
      ~w(AcademicYear InstitutionName InstitutionID Grade Subject AssessmentType Accomodations Subgroup),
    growth_rate: ~w(AcademicYear EntityLevel InstitutionName InstitutionID Subject Grade Subgroup)
  }

  @engagement_areas %{
    "Overall" => :engagement_overall,
    "Behavioral" => :engagement_behavioral,
    "Cognitive" => :engagement_cognitive,
    "Emotional" => :engagement_emotional,
    "Participation" => :engagement_participation
  }

  @datasets [
    :assessment_performance,
    :assessment_participation,
    :growth_rate | Map.values(@engagement_areas)
  ]

  def datasets, do: @datasets

  @type observation :: map()

  @doc """
  Parses `path`. Returns `{:ok, %{dataset:, publication_version:, rows_read:,
  observations: [...], errors: [...]}}` or `{:error, reason}`.
  """
  def parse_file(path, opts) do
    institution_ids = opts |> Keyword.fetch!(:institution_ids) |> MapSet.new()
    file_name = Path.basename(path)

    with {:ok, content} <- File.read(path),
         [header | rows] <-
           content |> strip_bom() |> __MODULE__.CSV.parse_string(skip_headers: false),
         {:ok, dataset} <- detect_dataset(file_name, header) do
      {observations, errors} =
        rows
        |> Enum.with_index(2)
        |> Enum.map(fn {cells, line} -> {Map.new(Enum.zip(header, cells)), line} end)
        |> Enum.filter(fn {row, _line} ->
          MapSet.member?(institution_ids, String.trim(row["InstitutionID"] || ""))
        end)
        |> Enum.flat_map(fn {row, line} -> row_observations(dataset, row, line) end)
        |> Enum.split_with(&match?({:ok, _}, &1))

      {:ok,
       %{
         dataset: dataset,
         file_name: file_name,
         publication_version: publication_version(file_name),
         rows_read: length(rows),
         observations: Enum.map(observations, fn {:ok, o} -> o end),
         errors: Enum.map(errors, fn {:error, e} -> e end)
       }}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, posix} -> {:error, "could not read #{file_name}: #{inspect(posix)}"}
      [] -> {:error, "#{file_name} is empty"}
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(content), do: content

  @doc "The `-vYYYYMMDD` publication stamp in an Insights file name, if present."
  def publication_version(file_name) do
    case Regex.run(~r/-v(\d{8})\.csv$/i, file_name) do
      [_, version] -> version
      nil -> nil
    end
  end

  defp detect_dataset(file_name, header) do
    has? = &(&1 in header)

    cond do
      has?.("NoviceRangeLow") -> check_header(:assessment_performance, header)
      has?.("PercentTestedRangeLow") -> check_header(:assessment_participation, header)
      has?.("DoesNotMeetRangeLow") -> check_header(:growth_rate, header)
      has?.("EngagementLevel") -> engagement_dataset(file_name, header)
      true -> {:error, "#{file_name}: unrecognized Insights columns #{inspect(header)}"}
    end
  end

  defp check_header(dataset, header) do
    expected =
      @dimension_columns[dataset] ++
        Enum.flat_map(@range_measures[dataset], &["#{&1}RangeLow", "#{&1}RangeHigh"]) ++
        if(dataset == :growth_rate, do: ~w(OverallGrowthLevel OverallGrowthPercentile), else: [])

    case expected -- header do
      [] -> {:ok, dataset}
      missing -> {:error, "#{dataset} file is missing columns #{inspect(missing)}"}
    end
  end

  defp engagement_dataset(file_name, header) do
    with [_, area] <- Regex.run(~r/Insights-Engagement-([A-Za-z]+)-/, file_name),
         {:ok, dataset} <- Map.fetch(@engagement_areas, area),
         [] <- ~w(Institution EntityLevel InstitutionID DistrictName EngagementLevel) -- header do
      {:ok, dataset}
    else
      _ -> {:error, "#{file_name}: cannot identify the Engagement Survey area or columns"}
    end
  end

  # ---------------------------------------------------------------------------
  # Rows → observations
  # ---------------------------------------------------------------------------

  defp row_observations(:growth_rate = dataset, row, line) do
    ranges = Enum.map(@range_measures[dataset], &range_observation(dataset, row, line, &1))

    ranges ++
      [
        single_observation(dataset, row, line, "OverallGrowthLevel", :level),
        single_observation(dataset, row, line, "OverallGrowthPercentile", :percentile)
      ]
  end

  defp row_observations(dataset, row, line) when is_map_key(@range_measures, dataset) do
    Enum.map(@range_measures[dataset], &range_observation(dataset, row, line, &1))
  end

  defp row_observations(dataset, row, line) do
    # Engagement: one column per academic year.
    row
    |> Map.keys()
    |> Enum.filter(&Regex.match?(~r/^\d{4}-\d{4}$/, &1))
    |> Enum.sort()
    |> Enum.map(fn year -> engagement_observation(dataset, row, line, year) end)
  end

  defp range_observation(dataset, row, line, measure) do
    low_text = row["#{measure}RangeLow"]
    high_text = row["#{measure}RangeHigh"]

    with {:ok, value} <- range_value(low_text, high_text) do
      {:ok, build(dataset, row, measure, :proportion, value, "#{low_text}|#{high_text}")}
    else
      {:error, message} -> {:error, %{line: line, measure: measure, message: message}}
    end
  end

  defp single_observation(dataset, row, line, column, unit) do
    text = row[column]

    case number_or_suppressed(text) do
      {:ok, value} -> {:ok, build(dataset, row, column, unit, value, text)}
      {:error, message} -> {:error, %{line: line, measure: column, message: message}}
    end
  end

  defp engagement_observation(dataset, row, line, year) do
    text = row[year]

    parsed =
      case String.split(String.trim(text || ""), "-") do
        [low, high] when low != "" and high != "" -> range_value(low, high)
        _ -> number_or_suppressed(text)
      end

    case parsed do
      {:ok, value} ->
        {:ok,
         build(dataset, Map.put(row, "AcademicYear", year), "Percent", :proportion, value, text)}

      {:error, message} ->
        {:error, %{line: line, measure: year, message: message}}
    end
  end

  defp range_value(low_text, high_text) do
    case {decimal(low_text), decimal(high_text)} do
      {:suppressed, :suppressed} ->
        {:ok, %{value_state: :suppressed}}

      {%Decimal{} = low, %Decimal{} = high} ->
        cond do
          not proportion?(low) or not proportion?(high) -> {:error, "range is outside 0–1"}
          Decimal.compare(low, high) == :gt -> {:error, "range low exceeds high"}
          Decimal.equal?(low, high) -> {:ok, %{value_state: :exact, value: low}}
          true -> {:ok, %{value_state: :range, range_low: low, range_high: high}}
        end

      _ ->
        {:error, "unreadable range #{inspect(low_text)}–#{inspect(high_text)}"}
    end
  end

  defp number_or_suppressed(text) do
    case decimal(text) do
      :suppressed -> {:ok, %{value_state: :suppressed}}
      %Decimal{} = value -> {:ok, %{value_state: :exact, value: value}}
      :error -> {:error, "unreadable value #{inspect(text)}"}
    end
  end

  defp decimal(text) do
    case String.trim(text || "") do
      "" ->
        :suppressed

      "*" ->
        :suppressed

      trimmed ->
        case Decimal.parse(trimmed) do
          {number, ""} -> number
          _ -> :error
        end
    end
  end

  defp proportion?(d), do: Decimal.compare(d, 0) != :lt and Decimal.compare(d, 1) != :gt

  defp build(dataset, row, measure, unit, value, source_text) do
    dims = %{
      dataset: dataset,
      academic_year: trim(row["AcademicYear"]),
      institution_id: trim(row["InstitutionID"]),
      institution_name: trim(row["InstitutionName"] || row["Institution"]),
      entity_level: trim(row["EntityLevel"]),
      district_name: trim(row["DistrictName"]),
      subject: trim(row["Subject"]),
      grade: trim(row["Grade"]),
      assessment_type: trim(row["AssessmentType"]),
      accommodations: trim(row["Accomodations"]),
      subgroup: trim(row["Subgroup"]),
      engagement_level: trim(row["EngagementLevel"]),
      measure: measure
    }

    dims
    |> Map.merge(%{value: nil, range_low: nil, range_high: nil})
    |> Map.merge(value)
    |> Map.merge(%{
      unit: unit,
      source_text: source_text,
      raw_row: row,
      natural_key: natural_key(dims)
    })
  end

  @key_fields [
    :dataset,
    :academic_year,
    :institution_id,
    :subject,
    :grade,
    :assessment_type,
    :accommodations,
    :subgroup,
    :engagement_level,
    :measure
  ]

  @doc "The identity of a published measure, independent of the file it came from."
  def natural_key(dims), do: Enum.map_join(@key_fields, "|", &to_string(Map.get(dims, &1) || ""))

  defp trim(nil), do: nil

  defp trim(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
