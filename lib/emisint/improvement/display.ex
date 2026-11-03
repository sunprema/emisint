defmodule Emisint.Improvement.Display do
  @moduledoc """
  Text rules shared by the school dashboard and the school PDF, so both show
  values, missing data and uncertainty the same way.

  * Targets: a number in the metric's unit; a workbook cell that is not a
    plain number is shown verbatim and never classified; an Excel date where
    a number is expected, or a 36-month target flagged for confirmation,
    "needs confirmation"; an empty cell is "Not set".
  * Actual results: exact, a range (never a midpoint), "Suppressed",
    "Unavailable" or "Not reported" — never zero for missing data.
  * Ratings: the documented 0–3 rubric label, "N/A", "Unavailable" or
    "Not rated".
  """
  alias Emisint.Improvement.{Percent, Rubric}

  @date ~r/^\d{4}-\d{2}-\d{2}$/

  @doc "`{:number | :text | :date | :needs_confirmation | :empty, display_text}` for a baseline or target."
  def target(metric, field) do
    value = Map.get(metric, field)
    source = get_in(metric.source_values || %{}, [source_key(field)]) || %{}
    raw = source["raw"]
    flags = metric.flags || []

    cond do
      field == :target_36m and :target_36m_needs_confirmation in flags ->
        {:needs_confirmation, "Needs confirmation"}

      value != nil ->
        {:number, number(metric, value)}

      is_binary(raw) and :source_value_is_date in flags and Regex.match?(@date, raw) ->
        {:date, "Needs confirmation"}

      is_binary(raw) ->
        {:text, raw}

      true ->
        {:empty, "Not set"}
    end
  end

  # Display-only spelling fixes for imported goal descriptions. The stored
  # description keeps the workbook's wording (Ft Yates Goals!B18).
  @description_corrections [
    {"perfoming", "performing"},
    {"data-drive practices", "data-driven practices"}
  ]

  @doc "A goal description as displayed: the stored text with known typos corrected."
  def goal_description(nil), do: nil

  def goal_description(text) when is_binary(text) do
    Enum.reduce(@description_corrections, text, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end

  @doc "The workbook cell and raw value behind a baseline or target, if recorded."
  def target_source(metric, field) do
    case get_in(metric.source_values || %{}, [source_key(field)]) do
      %{"cell" => cell} = source -> %{cell: cell, raw: source["raw"]}
      _ -> nil
    end
  end

  @doc "The unit name shown beside a metric whose values are not percentages."
  def unit_label(%{unit: :percentile}), do: "Growth percentile"
  def unit_label(_metric), do: nil

  @doc "A value in the metric's unit (growth percentiles have no `%` sign)."
  def number(%{unit: :percent}, value), do: Percent.format(value)
  def number(_metric, %Decimal{} = value), do: Decimal.to_string(value, :normal)
  def number(_metric, nil), do: nil

  @doc "An actual result as text."
  def actual(nil, _metric), do: "Not reported"
  def actual(%{value_state: :exact, value: v}, metric), do: number(metric, v)

  def actual(%{value_state: :range, range_low: l, range_high: h}, metric),
    do: "#{number(metric, l)}–#{number(metric, h)} (range)"

  def actual(%{value_state: :suppressed, suppression_reason: nil}, _metric), do: "Suppressed"

  def actual(%{value_state: :suppressed, suppression_reason: r}, _metric),
    do: "Suppressed (source: “#{r}”)"

  def actual(%{value_state: :unavailable}, _metric), do: "Unavailable"

  @doc "An implementation rating as text."
  def rating(nil), do: "Not rated"
  def rating(%{rating_state: :rated, score: s}), do: "#{s} · #{Rubric.label(s)}"
  def rating(%{rating_state: :not_applicable}), do: "N/A"
  def rating(%{rating_state: :unavailable}), do: "Unavailable"

  @doc """
  The status tone of a rubric score (Goals Dashboard!A15:A18): 3 Demonstrated
  Progress `:success`, 2 Implementation on Track `:info`, 1 Some Progress
  `:warning`, 0 Not Started `:error`.
  """
  def score_tone(3), do: :success
  def score_tone(2), do: :info
  def score_tone(1), do: :warning
  def score_tone(_), do: :error

  @doc "`score_tone/1` for a rating; unrated, N/A and unavailable ratings are `:neutral`."
  def rating_tone(%{rating_state: :rated, score: s}), do: score_tone(s)
  def rating_tone(_rating), do: :neutral

  defp source_key(:baseline_value), do: "baseline"
  defp source_key(field), do: to_string(field)
end
