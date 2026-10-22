defmodule Emisint.NdInsights.SchoolResults do
  @moduledoc """
  Read model for one school's published ND Insights results.

  * Uses the **latest publication version** of each measure.
  * Keeps annual state results entirely separate from seasonal reporting
    periods: nothing here is assigned to a period.
  * "Proficient or Advanced" is never published as a single value; it is
    derived as the interval `[Proficient low + Advanced low,
    Proficient high + Advanced high]` (capped at 100%), and only when both
    components were published unsuppressed. "Proficient" alone is shown
    separately.
  * Annual goals are compared only when year, subject, assessment type
    (Combined includes the alternate assessment), grade coverage
    ("All Grades"), subgroup ("All"), accommodations ("All") and measure all
    match.
  """
  require Ash.Query

  alias Emisint.NdInsights.{SourceFile, StateResult}

  @performance_levels [
    {"Novice", "Novice"},
    {"Partially", "Approaching Proficiency"},
    {"Proficient", "Proficient"},
    {"Advanced", "Advanced"}
  ]

  @growth_levels [
    {"DoesNotMeet", "Does not meet"},
    {"Approaches", "Approaches"},
    {"Meets", "Meets"},
    {"Exceeds", "Exceeds"}
  ]

  @assessment_types [{"Comp", "Combined"}, {"Reg", "Standard"}, {"Alt", "Alternate"}]

  @engagement_areas [
    {:engagement_overall, "Overall"},
    {:engagement_behavioral, "Behavioral"},
    {:engagement_cognitive, "Cognitive"},
    {:engagement_emotional, "Emotional"}
  ]

  def performance_levels, do: @performance_levels
  def growth_levels, do: @growth_levels
  def assessment_types, do: @assessment_types
  def engagement_areas, do: @engagement_areas

  @doc "Latest-version results and their source files for an InstitutionID, read as `actor`."
  def load(actor, institution_id) when is_binary(institution_id) do
    rows =
      StateResult
      |> Ash.Query.filter(institution_id == ^institution_id)
      |> Ash.read!(actor: actor)
      |> Enum.group_by(& &1.natural_key)
      |> Enum.map(fn {_key, versions} -> Enum.max_by(versions, & &1.publication_version) end)

    file_ids = rows |> Enum.map(& &1.source_file_id) |> Enum.uniq()

    files =
      if file_ids == [],
        do: [],
        else:
          SourceFile
          |> Ash.Query.filter(id in ^file_ids)
          |> Ash.Query.sort(dataset: :asc, file_name: :asc)
          |> Ash.read!(actor: actor)

    %{
      rows: rows,
      files: files,
      years: rows |> Enum.map(& &1.academic_year) |> Enum.uniq() |> Enum.sort(:desc)
    }
  end

  def load(_actor, _institution_id), do: %{rows: [], files: [], years: []}

  def subgroups(rows, year) do
    rows
    |> Enum.filter(
      &(&1.academic_year == year and &1.dataset in [:assessment_performance, :growth_rate])
    )
    |> Enum.map(& &1.subgroup)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1 != "All", &1})
  end

  @doc "Performance rows: `[%{subject, grade, levels: %{measure => row}, tested: row}]`."
  def performance(rows, year, assessment_type, subgroup) do
    tested =
      rows
      |> Enum.filter(&match?(%{dataset: :assessment_participation, measure: "PercentTested"}, &1))
      |> Enum.filter(&slice?(&1, year, assessment_type, subgroup))
      |> Map.new(&{{&1.subject, &1.grade}, &1})

    rows
    |> Enum.filter(
      &(&1.dataset == :assessment_performance and slice?(&1, year, assessment_type, subgroup))
    )
    |> Enum.group_by(&{&1.subject, &1.grade})
    |> Enum.map(fn {{subject, grade} = key, measures} ->
      levels = Map.new(measures, &{&1.measure, &1})

      %{
        subject: subject,
        grade: grade,
        levels: levels,
        proficient_or_advanced: proficient_or_advanced(levels),
        tested: tested[key]
      }
    end)
    |> Enum.sort_by(&{subject_order(&1.subject), grade_order(&1.grade)})
  end

  @doc "Growth rows: `[%{subject, grade, levels: %{measure => row}}]` (no assessment type in this dataset)."
  def growth(rows, year, subgroup) do
    rows
    |> Enum.filter(
      &(&1.dataset == :growth_rate and &1.academic_year == year and &1.subgroup == subgroup)
    )
    |> Enum.group_by(&{&1.subject, &1.grade})
    |> Enum.map(fn {{subject, grade}, measures} ->
      %{subject: subject, grade: grade, levels: Map.new(measures, &{&1.measure, &1})}
    end)
    |> Enum.sort_by(&{subject_order(&1.subject), grade_order(&1.grade)})
  end

  @doc "Engagement Survey results for a year: `[%{area, label, levels: %{engagement_level => row}}]`."
  def engagement(rows, year) do
    for {dataset, label} <- @engagement_areas,
        measures = Enum.filter(rows, &(&1.dataset == dataset and &1.academic_year == year)),
        measures != [] do
      %{area: dataset, label: label, levels: Map.new(measures, &{&1.engagement_level, &1})}
    end
  end

  @doc """
  Engagement Survey participation for a year.

  The "Engagement Participation" download repeats the same value on its
  Committed, Compliant and Disengaged rows (identical for every institution
  and year statewide), and Insights shows it as "Overall Participation —
  participation of the enrolled student body in the engagement survey", one
  value per year. The rows are kept as distinct records; a single value is
  shown only when every published row agrees exactly, otherwise each row is
  returned separately and nothing is combined.

  Returns `nil`, `%{status: :consistent, result: row, rows: rows}` or
  `%{status: :inconsistent, rows: rows}`.
  """
  def survey_participation(rows, year) do
    case Enum.filter(
           rows,
           &(&1.dataset == :engagement_participation and &1.academic_year == year)
         ) do
      [] ->
        nil

      [first | _] = published ->
        published = Enum.sort_by(published, & &1.engagement_level)

        if Enum.all?(published, &same_published_value?(&1, first)),
          do: %{status: :consistent, result: first, rows: published},
          else: %{status: :inconsistent, rows: published}
    end
  end

  defp same_published_value?(a, b) do
    Enum.all?([:value_state, :value, :range_low, :range_high], fn field ->
      case {Map.get(a, field), Map.get(b, field)} do
        {%Decimal{} = x, %Decimal{} = y} -> Decimal.equal?(x, y)
        {x, y} -> x == y
      end
    end)
  end

  defp slice?(row, year, assessment_type, subgroup) do
    row.academic_year == year and row.assessment_type == assessment_type and
      row.subgroup == subgroup and
      row.accommodations in ["All", nil]
  end

  @doc """
  Derived Proficient-or-Advanced interval from published Proficient and
  Advanced values: `{:ok, low, high}` or `{:not_derivable, reason}`.
  """
  def proficient_or_advanced(levels) do
    case derived(levels) do
      {:ok, %{low: low, high: high}} -> {:ok, low, high}
      other -> other
    end
  end

  # Adds the published components as given. `exact?` is true only when both
  # components were published as exact values; no rounding or endpoint
  # allowance is ever applied.
  defp derived(levels) do
    with {:ok, p} <- bounds(levels["Proficient"]),
         {:ok, a} <- bounds(levels["Advanced"]) do
      {:ok,
       %{
         low: Decimal.add(p.low, a.low),
         high: Decimal.min(Decimal.add(p.high, a.high), Decimal.new(1)),
         exact?: p.exact? and a.exact?
       }}
    else
      {:error, reason} -> {:not_derivable, reason}
    end
  end

  defp bounds(nil), do: {:error, "not published"}
  defp bounds(%{value_state: :suppressed}), do: {:error, "suppressed"}
  defp bounds(%{value_state: :exact, value: v}), do: {:ok, %{low: v, high: v, exact?: true}}

  defp bounds(%{value_state: :range, range_low: low, range_high: high}),
    do: {:ok, %{low: low, high: high, exact?: false}}

  @doc """
  Compares an annual Proficient-or-Advanced goal with the matching published
  result (derived from Proficient + Advanced). Only a result matching the
  goal's year, subject, assessment type, all grades, all students, all
  accommodations and measure is used. Returns a map with `:status`:

    * `:not_published` / `:not_derivable` / `:not_comparable`
    * `:pending_range_clarification` — at least one component is a published
      range. The state has not documented what range endpoints mean (e.g.
      whether 0.29 is "up to 29%" or "below 30%"), so no verdict is given.
    * `:meets` / `:below` — both components were published as exact values;
      their sum is compared with the goal as published, with no allowance.
  """
  def compare_goal(%{measure: :proficient_or_advanced} = goal, rows) do
    subject = if goal.subject == :ela, do: "Reading", else: "Math"
    assessment_type = if goal.includes_alternate, do: "Comp", else: "Reg"

    levels =
      rows
      |> Enum.filter(
        &(&1.dataset == :assessment_performance and &1.academic_year == goal.school_year and
            &1.subject == subject and &1.grade == "All Grades" and &1.subgroup == "All" and
            &1.assessment_type == assessment_type and &1.accommodations in ["All", nil])
      )
      |> Map.new(&{&1.measure, &1})

    match = %{
      year: goal.school_year,
      subject: subject,
      assessment_type: assessment_type,
      grade: "All Grades",
      subgroup: "All"
    }

    if levels == %{} do
      %{status: :not_published, match: match}
    else
      case derived(levels) do
        {:not_derivable, reason} ->
          %{status: :not_derivable, reason: reason, match: match}

        {:ok, %{exact?: false} = d} ->
          Map.merge(d, %{status: :pending_range_clarification, match: match, derived: true})

        {:ok, %{exact?: true, low: value} = d} ->
          status = if Decimal.compare(value, goal.target_value) == :lt, do: :below, else: :meets
          Map.merge(d, %{status: status, match: match, derived: true})
      end
    end
  end

  def compare_goal(_goal, _rows), do: %{status: :not_comparable}

  defp subject_order("Reading"), do: 0
  defp subject_order("ELA"), do: 0
  defp subject_order("Math"), do: 1
  defp subject_order("Science"), do: 2
  defp subject_order(_), do: 3

  defp grade_order("All Grades"), do: -1

  defp grade_order(grade) do
    case Integer.parse(grade || "") do
      {n, _} -> n
      :error -> 99
    end
  end
end
