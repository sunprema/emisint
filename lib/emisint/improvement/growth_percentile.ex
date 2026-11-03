defmodule Emisint.Improvement.GrowthPercentile do
  @moduledoc """
  Fort Yates growth metrics G2-M3 (ELA) and G3-M3 (Math) are **Overall
  Growth Percentiles**, not the percentage of students meeting growth
  expectations (project decision, October 31, 2026: Ram confirmed the
  baselines are growth percentiles; see PLAN_nd_first.md).

  * **Definition.** The workbook cells (`Ft Yates Goals!D/H/P15` and `…22`)
    are percent-formatted (0.38 shows as 38%). The numbers are kept and read
    as percentiles: 0.38 → 38. The original cells and the workbook wording
    stay in `source_values`. `definition/1` is used by the seed;
    `run/2` converts an existing database to exactly the same record.
  * **ND Insights source.** Growth Rate `OverallGrowthPercentile` for the
    subject, the published **All Grades** row, all students, as published.
    Not Meets, Meets + Exceeds, `OverallGrowthLevel`, or an average of the
    grade rows.
  * **Annual, not seasonal.** A published value is used only for a result
    entered at the 18- or 36-month review, for an explicitly chosen school
    year and an intentional save, with its provenance kept. It is never
    copied into seasonal periods, and no review result is filled in
    automatically from the baseline or the latest available year.
  * **Eligible years are not established.** Which assessment year applies
    to each checkpoint has not been decided, so no year is refused or
    preferred here; published years are shown as reference only until a
    user chooses one. (2024-2025 holds the same values as the workbook
    baselines, 38 and 41.)
  """
  require Ash.Query

  alias Emisint.Accounts.School
  alias Emisint.Improvement.{ActualResult, GoalPlan, Metric}
  alias Emisint.Improvement.Seeds.FortYates
  alias Emisint.NdInsights.StateResult

  @decision_date "2026-10-31"
  @hundred Decimal.new(100)

  # {Insights growth subject, label}
  @metrics %{"G2-M3" => {"ELA", "ELA"}, "G3-M3" => {"Math", "Math"}}

  @conversion_ref "growth_percentile_decision:#{@decision_date}"

  def decision_date, do: @decision_date
  def conversion_ref, do: @conversion_ref
  def codes, do: Map.keys(@metrics)

  @doc "Whether `metric` is one of the Fort Yates growth-percentile metrics."
  def metric?(%{unit: :percentile, performance_measure: :growth_percentile}), do: true
  def metric?(_metric), do: false

  @doc """
  The growth-percentile definition for a seeded Fort Yates metric (built
  from the workbook row as a percent metric); other metrics pass through.
  """
  def definition(%{code: code} = attrs) when is_map_key(@metrics, code) do
    {subject, label} = Map.fetch!(@metrics, code)
    [_, row] = Regex.run(~r/!D(\d+)$/, attrs.source_values["baseline"]["cell"])

    %{
      attrs
      | description: "Overall growth percentile (#{label})",
        unit: :percentile,
        performance_measure: :growth_percentile,
        baseline_value: scale(attrs.baseline_value),
        target_18m: scale(attrs.target_18m),
        target_36m: scale(attrs.target_36m),
        source_values:
          Map.merge(attrs.source_values, %{
            "description" => %{"row" => "Ft Yates Goals row #{row}", "raw" => attrs.description},
            "unit_decision" => %{
              "date" => @decision_date,
              "decision" =>
                "Growth baselines and targets are Overall Growth Percentiles (confirmed by Ram, accepted as the project decision).",
              "conversion" =>
                "The workbook cells are percent-formatted proportions; each number is kept and read as a percentile (0.38 → 38)."
            },
            "nd_insights" => insights_mapping(subject)
          })
    }
  end

  def definition(attrs), do: attrs

  defp scale(nil), do: nil
  defp scale(%Decimal{} = value), do: value |> Decimal.mult(@hundred) |> Decimal.normalize()

  defp insights_mapping(subject) do
    %{
      "dataset" => "growth_rate",
      "measure" => "OverallGrowthPercentile",
      "subject" => subject,
      "grade" => "All Grades",
      "subgroup" => "All"
    }
  end

  @doc "The ND Insights mapping recorded on a growth-percentile metric, or nil."
  def mapping(%{source_values: %{"nd_insights" => %{} = m}} = metric) do
    if metric?(metric), do: m
  end

  def mapping(_metric), do: nil

  @doc """
  The published `OverallGrowthPercentile` rows (latest publication version)
  for a metric's subject, All Grades and all students, newest year first.
  `rows` are `NdInsights.SchoolResults.load/2` rows.
  """
  def published(rows, metric) do
    case mapping(metric) do
      nil ->
        []

      m ->
        rows
        |> Enum.filter(
          &(&1.dataset == :growth_rate and &1.measure == m["measure"] and
              &1.subject == m["subject"] and &1.grade == m["grade"] and
              &1.subgroup == m["subgroup"])
        )
        |> Enum.sort_by(& &1.academic_year, :desc)
    end
  end

  @source_year ~r/^ND Insights Growth Rate (\d{4}-\d{4}) · /

  @doc "The published school year a result was taken from (from its `source_ref`), or nil."
  def source_year(%{source: :nd_insights, source_ref: ref}) when is_binary(ref) do
    case Regex.run(@source_year, ref) do
      [_, year] -> year
      _ -> nil
    end
  end

  def source_year(_entry), do: nil

  @doc """
  The published row for `institution_id`, `metric` and `year`, read without
  authorization (public state data). Latest publication version wins.
  """
  def published_row(institution_id, metric, year) do
    with %{} = m <- mapping(metric) do
      StateResult
      |> Ash.Query.filter(
        institution_id == ^institution_id and dataset == :growth_rate and
          measure == ^m["measure"] and subject == ^m["subject"] and grade == ^m["grade"] and
          subgroup == ^m["subgroup"] and academic_year == ^year
      )
      |> Ash.Query.load(:source_file)
      |> Ash.read!(authorize?: false)
      |> Enum.max_by(& &1.publication_version, fn -> nil end)
    end
  end

  @doc "The provenance text stored on a result taken from a published row."
  def source_ref(row) do
    file = if row.source_file, do: " · file #{row.source_file.file_name}", else: ""

    "ND Insights Growth Rate #{row.academic_year} · #{row.subject} · #{row.grade} · " <>
      "All students · OverallGrowthPercentile · version #{row.publication_version}#{file}"
  end

  # ---------------------------------------------------------------------------
  # Conversion of an existing database
  # ---------------------------------------------------------------------------

  @doc """
  Converts the Fort Yates G2-M3 and G3-M3 definitions in `organization_id`
  from the percent reading to growth percentiles, matching `definition/1`.
  Repeat-safe: an already converted metric is `:unchanged`. A metric whose
  stored values match neither the original percent definition nor the
  percentile definition is `:drift` and left untouched.

  Current actual results recorded under the percent reading (0.45 for 45)
  are restated by an appended `:convert_unit` correction (45), keeping the
  original entry and its author; nothing is updated or deleted. That needs
  `actor:` (recorded as the recorder).

  Returns `{:ok, %{converted: [...], unchanged: [...], drift: [...], restated: n}}`.
  """
  def run(organization_id, opts \\ []) do
    case fort_yates_plan(organization_id) do
      nil ->
        {:ok, %{converted: [], unchanged: [], drift: [], restated: 0}}

      plan ->
        expected = expected_definitions()

        Metric
        |> Ash.Query.filter(goal_plan_id == ^plan.id and code in ^Map.keys(expected))
        |> Ash.read!(tenant: organization_id, authorize?: false)
        |> Enum.reduce_while(
          {:ok, %{converted: [], unchanged: [], drift: [], restated: 0}},
          fn metric, {:ok, acc} ->
            case convert(metric, Map.fetch!(expected, metric.code), organization_id, opts) do
              {:ok, key, restated} ->
                {:cont,
                 {:ok,
                  %{acc | key => acc[key] ++ [metric.code], restated: acc.restated + restated}}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end
        )
    end
  end

  defp fort_yates_plan(org_id) do
    %{state_entity_id: id, slug: slug} = FortYates.school()
    program = FortYates.goal_plan().program

    with %School{} = school <-
           School
           |> Ash.Query.filter(state_entity_id == ^id and slug == ^slug)
           |> Ash.read_one!(tenant: org_id, authorize?: false) do
      GoalPlan
      |> Ash.Query.filter(school_id == ^school.id and program == ^program)
      |> Ash.Query.sort(definition_version: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(tenant: org_id, authorize?: false)
    end
  end

  defp expected_definitions do
    FortYates.metrics()
    |> Enum.filter(&is_map_key(@metrics, &1.code))
    |> Map.new(&{&1.code, Map.delete(&1, :goal_number)})
  end

  @fields [
    :description,
    :unit,
    :performance_measure,
    :baseline_value,
    :target_18m,
    :target_36m,
    :source_values
  ]

  defp convert(metric, expected, org_id, opts) do
    cond do
      matches?(metric, expected) ->
        {:ok, :unchanged, 0}

      original?(metric, expected) ->
        Emisint.Repo.transaction(fn ->
          # No notifiers are configured; notifications are collected so none
          # are reported as missed inside the transaction.
          {converted, _notifications} =
            metric
            |> Ash.Changeset.for_update(:apply_unit_decision, Map.take(expected, @fields),
              tenant: org_id,
              authorize?: false
            )
            |> Ash.update!(return_notifications?: true)

          case restate_actuals(converted, org_id, opts[:actor]) do
            {:ok, n} -> n
            {:error, reason} -> Emisint.Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, n} -> {:ok, :converted, n}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:ok, :drift, 0}
    end
  end

  defp matches?(metric, expected),
    do: Enum.all?(@fields, &same?(Map.get(metric, &1), expected[&1]))

  # The original percent definition: the seed's values before the decision.
  defp original?(metric, expected) do
    metric.unit == :percent and
      metric.description == expected.source_values["description"]["raw"] and
      Enum.all?([:baseline_value, :target_18m, :target_36m], fn field ->
        same?(scale(Map.get(metric, field)), expected[field])
      end) and
      Enum.all?(["baseline", "target_18m", "target_36m"], fn key ->
        metric.source_values[key] == expected.source_values[key]
      end)
  end

  defp same?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  defp same?(a, b), do: a == b

  defp restate_actuals(metric, org_id, actor) do
    current =
      ActualResult
      |> Ash.Query.for_read(:current, %{}, tenant: org_id, authorize?: false)
      |> Ash.Query.filter(metric_id == ^metric.id)
      |> Ash.read!()

    cond do
      current == [] ->
        {:ok, 0}

      is_nil(actor) ->
        {:error,
         "#{metric.code} has #{length(current)} recorded actual result(s); pass actor: to restate them"}

      true ->
        Enum.reduce_while(current, {:ok, 0}, fn entry, {:ok, n} ->
          case restate(entry, org_id, actor) do
            {:ok, _entry, _notifications} -> {:cont, {:ok, n + 1}}
            {:error, error} -> {:halt, {:error, Exception.message(error)}}
          end
        end)
    end
  end

  defp restate(entry, org_id, actor) do
    ActualResult
    |> Ash.Changeset.for_create(
      :convert_unit,
      %{
        corrects_id: entry.id,
        author_id: entry.author_id,
        value_state: entry.value_state,
        value: scale(entry.value),
        range_low: scale(entry.range_low),
        range_high: scale(entry.range_high),
        suppression_reason: entry.suppression_reason,
        measurement_date: entry.measurement_date,
        notes: entry.notes,
        evidence_links: Enum.map(entry.evidence_links, &Map.take(&1, [:url, :label])),
        source_ref: @conversion_ref,
        correction_reason:
          "Unit correction (#{@decision_date} decision): the value was entered as a percentage and is restated as a growth percentile; the number is unchanged."
      },
      tenant: org_id,
      actor: actor,
      authorize?: false
    )
    |> Ash.create(return_notifications?: true)
  end

  @doc """
  Entries of one metric recorded under the percent reading: those in a
  period that a `:unit_conversion` entry restated, recorded before it.
  Used to display superseded history in its original unit.
  """
  def legacy_entry_ids(entries) do
    conversions =
      for %{source: :unit_conversion} = e <- entries,
          into: %{},
          do: {e.reporting_period_id, e.recorded_at}

    for e <- entries,
        e.source != :unit_conversion,
        at = conversions[e.reporting_period_id],
        at != nil and DateTime.compare(e.recorded_at, at) != :gt,
        into: MapSet.new(),
        do: e.id
  end

  @doc "Whether a reporting period is an 18- or 36-month review."
  def review_period?(%{kind: kind}), do: kind in [:review_18m, :review_36m]
end
