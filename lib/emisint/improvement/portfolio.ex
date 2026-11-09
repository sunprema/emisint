defmodule Emisint.Improvement.Portfolio do
  @moduledoc """
  The ND FIRST portfolio summary on `/school-goals`, following the first two
  visible sheets of "ND First School MOU Goal Overview.xlsx": **"Goals
  Dashboard"** ("Overall Goal Progress — Average Rubric Score") and
  **"Performance-Based Payment"** ("Performance Based Payments (18-month
  review)"), plus the "Group" column of the hidden first sheet, **"School
  Directory"**.

  **One row per participant.** Rows follow the workbook's row order (Fort
  Yates, Solen [Cannon Ball], Oberon, Warwick, Mandaree, Dunseith, Drayton,
  Valley MS).
  Each participant's workbook sheet is its main record's goal plan: the
  school for a single-building participant, the district for a district
  participant. Building records have no workbook ratings or payment, so they
  are never rows and never add to a figure. A participant whose main record
  the user can't read shows no figures; one with no readable page is left
  out. The workbook's "Solen" row is the Cannon Ball participant (confirmed
  by the user, November 9, 2026): it is shown as Cannon Ball, from Cannon
  Ball Elementary School's goal plan, in Solen's workbook position.

  **Goals Dashboard columns** (workbook formulas, per participant sheet):

    * `# of Systems Metrics` / `# of Student Outcomes Metrics` —
      `COUNTIF(sheet!A:A, "Systems" | "Student Outcome")`: the plan's metrics
      by category.
    * `Spr '26`, `Sum '26`, `Fal '26` — `AVERAGEIF(sheet!A:A, category,
      sheet!E:E | F:F | G:G)`: the mean of the current **seasonal
      implementation ratings** per category. Only scored ratings count, as
      `AVERAGEIF` skips blanks and text; N/A, unavailable and missing are
      excluded, never zero.
    * `18m Check` — the same, on column I: the current **formal 18-month
      review ratings**.
    * `Win '27` … `Spr '28` — `AVERAGE(sheet!J:J … O:O)`: one mean over all
      scored seasonal ratings of the period (the workbook doesn't split these
      by category).
    * `Systems Check 36 m`, `Systems Weighted Score (30%)`, `Outcomes Check 36
      m`, `Outcomes Weighted Score (70%)` — the workbook gives headings but no
      formulas. The checks follow the `18m Check` formula on the 36-month
      review ratings; the weighted scores multiply them by the headed weights,
      which are the confirmed 36-month weights (`Payment.checkpoints/1`).
    * `AVERAGE` row — `AVERAGE(C5:C12)` etc.: the mean of the shown
      participants' values, skipping blanks, with its coverage. (The
      workbook's own E13:L13 also include its "Example School" row; the
      example is not a participant and is not included here.)

  **Performance-Based Payment columns** (18-month review): `18-month Systems
  score` and `Outcomes Score` are the `18m Check` averages; `Systems Weighted
  (70%)` = score × 70%, `Outcomes Weighted (30%)` = score × 30%; `Overall
  Weighted Score` = their sum, only when both exist; `Performance %` =
  overall ÷ 3. The payout column is the existing payment estimate
  (`Payment.summary/3`), not the workbook's `% × $70,000`: it uses each plan's
  configured 18-month allocation and requires every metric's review rating.
  It is "Not configured" when the plan has no payment terms and "Awaiting
  review" until the ratings are complete. The workbook has no total row, so
  no portfolio payment total is calculated.

  Averages are exact decimals; rounding is for display only.
  """

  alias Emisint.Improvement.{Dashboard, Payment, Pilot}

  # Workbook row order ("Goals Dashboard" A5:A12, "Performance-Based Payment"
  # A4:A11), with each participant's sheet ("Tab Name", column B) and its
  # "School Directory" Group. `workbook_note`: the workbook's own row name
  # when it differs from the participant's name.
  @workbook_rows [
    %{
      workbook_name: "Fort Yates",
      sheet: "Ft Yates Goals",
      group: "South Team",
      slug: "fort-yates-ms"
    },
    %{
      workbook_name: "Solen",
      sheet: "Solen Goals",
      group: "South Team",
      slug: "cannon-ball-elementary",
      workbook_note: "Workbook row “Solen”"
    },
    %{
      workbook_name: "Oberon",
      sheet: "Oberon Goals",
      group: "South Team",
      slug: "oberon-elementary"
    },
    %{
      workbook_name: "Warwick",
      sheet: "Warwick Goals",
      group: "South Team",
      slug: "warwick-public-school-district"
    },
    %{
      workbook_name: "Mandaree",
      sheet: "Mandaree Goals",
      group: "North Team",
      slug: "mandaree-public-school-district"
    },
    %{
      workbook_name: "Dunseith",
      sheet: "Dunseith Goals",
      group: "North Team",
      slug: "dunseith-public-school-district"
    },
    %{
      workbook_name: "Drayton",
      sheet: "Drayton Goals",
      group: "North Team",
      slug: "drayton-public-school-district"
    },
    %{
      workbook_name: "Valley MS",
      sheet: "Valley Goals",
      group: "North Team",
      slug: "valley-middle-school"
    }
  ]

  # "Goals Dashboard" columns E–V: {key, heading, reporting period, kind}.
  @progress_columns [
    {:spr_26, "Spr '26", "spr_26", :split},
    {:sum_26, "Sum '26", "sum_26", :split},
    {:fal_26, "Fal '26", "fal_26", :split},
    {:check_18m, "18m Check", "review_18m", :split},
    {:win_27, "Win '27", "win_27", :overall},
    {:spr_27, "Spr '27", "spr_27", :overall},
    {:sum_27, "Sum '27", "sum_27", :overall},
    {:fal_27, "Fal '27", "fal_27", :overall},
    {:win_28, "Win '28", "win_28", :overall},
    {:spr_28, "Spr '28", "spr_28", :overall},
    {:check_36m, "36m Check", "review_36m", :weighted}
  ]

  @doc "The workbook's participant rows, in order (configuration, not data)."
  def workbook_rows, do: @workbook_rows

  @doc "The \"Goals Dashboard\" period columns: `[{key, heading, period_code, kind}]`."
  def progress_columns, do: @progress_columns

  @doc """
  The portfolio summary for `scope`'s user: `%{rows, average, weights,
  coverage}`. Every read runs as the user, so rows and averages cover only
  what they may read.
  """
  def summary(scope) do
    schools = Dashboard.list_schools(scope, institution_ids: Pilot.institution_ids())
    readable = MapSet.new(schools, & &1.slug)
    by_slug = Map.new(schools, &{&1.slug, &1})
    tabs = readable |> Pilot.tabs() |> Map.new(&{&1.slug, &1})
    weights = weights()

    rows =
      Enum.flat_map(@workbook_rows, fn w ->
        case tabs[w.slug] do
          %{enabled?: true, href: href} = tab ->
            [
              participant_row(
                scope,
                Map.put_new(w, :workbook_note, nil),
                tab,
                href,
                by_slug[w.slug],
                weights
              )
            ]

          _ ->
            []
        end
      end)

    data_rows = Enum.filter(rows, &(&1.status == :loaded))

    %{
      rows: rows,
      average: average_row(data_rows),
      weights: weights,
      coverage: %{loaded: length(data_rows), listed: length(rows)}
    }
  end

  defp weights do
    for c <- Payment.checkpoints("nd_first_mou"), into: %{} do
      {c.checkpoint, %{systems: c.systems_weight, outcomes: c.outcomes_weight}}
    end
  end

  # The participant's main record isn't readable (e.g. a building-only
  # member): the row links to the readable page and shows no figures.
  defp participant_row(_scope, w, tab, href, nil, _weights),
    do: Map.merge(w, %{name: tab.name, href: href, status: :no_access})

  defp participant_row(scope, w, tab, href, school, weights) do
    base = Map.merge(w, %{name: tab.name, href: href, school: school})

    case Dashboard.load_plan(scope, school) do
      {:ok, defs} ->
        ratings = Dashboard.current_ratings(scope, school)
        Map.merge(base, %{status: :loaded} |> Map.merge(figures(defs, ratings, weights)))

      {:error, :no_plan} ->
        Map.put(base, :status, :no_plan)
    end
  end

  @doc """
  One participant's figures from its plan definitions (`Dashboard.load_plan/2`)
  and its current ratings by period id (`Dashboard.current_ratings/2`).
  """
  def figures(defs, ratings_by_period, weights) do
    metrics = defs.metrics
    period_ids = Map.new(defs.periods, &{&1.code, &1.id})
    ratings_for = fn code -> Map.get(ratings_by_period, period_ids[code], %{}) end

    columns =
      Map.new(@progress_columns, fn {key, _heading, code, kind} ->
        {key, column(kind, metrics, ratings_for.(code), weights)}
      end)

    check = columns.check_18m
    w18 = weights.review_18m

    systems_weighted = scale(check.systems.value, w18.systems)
    outcomes_weighted = scale(check.outcomes.value, w18.outcomes)
    overall = add_both(systems_weighted, outcomes_weighted)

    %{
      counts: %{
        systems: Enum.count(metrics, &(&1.category == :systems)),
        outcomes: Enum.count(metrics, &(&1.category == :student_outcome))
      },
      columns: columns,
      payment: %{
        systems_score: check.systems,
        systems_weighted: systems_weighted,
        outcomes_score: check.outcomes,
        outcomes_weighted: outcomes_weighted,
        overall: overall,
        performance: overall && Decimal.div(overall, Decimal.new(defs.plan.max_rating)),
        estimate: Enum.find(defs.payment.checkpoints, &(&1.checkpoint == :review_18m)),
        terms: defs.payment.terms
      }
    }
  end

  defp column(:split, metrics, ratings, _weights),
    do: %{
      systems: average(metrics, ratings, :systems),
      outcomes: average(metrics, ratings, :student_outcome)
    }

  defp column(:overall, metrics, ratings, _weights),
    do: %{overall: average(metrics, ratings, nil)}

  defp column(:weighted, metrics, ratings, weights) do
    systems = average(metrics, ratings, :systems)
    outcomes = average(metrics, ratings, :student_outcome)

    %{
      systems: systems,
      systems_weighted: scale(systems.value, weights.review_36m.systems),
      outcomes: outcomes,
      outcomes_weighted: scale(outcomes.value, weights.review_36m.outcomes)
    }
  end

  # AVERAGEIF semantics: the mean of the scored ratings of the category's
  # metrics (all metrics when `category` is nil); nil when none is scored.
  defp average(metrics, ratings, category) do
    in_scope = Enum.filter(metrics, &(category == nil or &1.category == category))

    scores =
      for m <- in_scope,
          %{rating_state: :rated, score: score} <- [ratings[m.id]],
          score != nil,
          do: score

    %{value: mean(scores), rated: length(scores), total: length(in_scope)}
  end

  defp mean([]), do: nil

  defp mean(values),
    do:
      Decimal.div(
        Enum.reduce(values, Decimal.new(0), &Decimal.add(to_dec(&1), &2)),
        length(values)
      )

  defp to_dec(%Decimal{} = d), do: d
  defp to_dec(n), do: Decimal.new(n)

  defp scale(nil, _weight), do: nil
  defp scale(value, weight), do: Decimal.mult(value, weight)

  defp add_both(nil, _), do: nil
  defp add_both(_, nil), do: nil
  defp add_both(a, b), do: Decimal.add(a, b)

  # The workbook's AVERAGE row: per column, the mean of the participants'
  # values that exist, with how many participants contributed.
  defp average_row(rows) do
    counts = %{
      systems: avg_of(rows, &Decimal.new(&1.counts.systems)),
      outcomes: avg_of(rows, &Decimal.new(&1.counts.outcomes))
    }

    columns =
      Map.new(@progress_columns, fn {key, _h, _code, kind} ->
        fields =
          case kind do
            :split -> [:systems, :outcomes]
            :overall -> [:overall]
            :weighted -> [:systems, :outcomes]
          end

        {key,
         Map.new(fields, fn f -> {f, avg_of(rows, &get_in(&1, [:columns, key, f, :value]))} end)}
      end)

    %{counts: counts, columns: columns, participants: length(rows)}
  end

  defp avg_of(rows, fun) do
    values = rows |> Enum.map(fun) |> Enum.reject(&is_nil/1)
    %{value: mean(values), of: length(values), participants: length(rows)}
  end

  # ── Display ─────────────────────────────────────────────────────────────

  @doc """
  The workbook's conditional-format band for an average ("Goals Dashboard"
  E3:U12): ≤ 0.49 → 0, 0.50–1.49 → 1, 1.50–2.49 → 2, ≥ 2.5 → 3, nil between
  the bands (as in the workbook). Compared at the workbook's two decimals.
  """
  def band(nil), do: nil

  def band(%Decimal{} = value) do
    v = Decimal.round(value, 2, :half_up)

    cond do
      Decimal.compare(v, Decimal.new("0.49")) != :gt -> 0
      between?(v, "0.5", "1.49") -> 1
      between?(v, "1.5", "2.49") -> 2
      Decimal.compare(v, Decimal.new("2.5")) != :lt -> 3
      true -> nil
    end
  end

  defp between?(v, low, high),
    do:
      Decimal.compare(v, Decimal.new(low)) != :lt and Decimal.compare(v, Decimal.new(high)) != :gt

  @doc "An average or score to two decimals, e.g. \"1.92\"; nil stays nil."
  def number(nil), do: nil
  def number(%Decimal{} = d), do: d |> Decimal.round(2, :half_up) |> Decimal.to_string(:normal)

  @doc "A proportion as a whole percentage, e.g. \"75%\"."
  def percent(nil), do: nil

  def percent(%Decimal{} = d),
    do:
      (d |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_string(:normal)) <> "%"
end
