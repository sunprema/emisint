defmodule Emisint.Improvement.PaymentPreviewTest do
  @moduledoc """
  The read-only current-ratings payment preview (`PaymentPreview`): period
  selection, both checkpoint weightings, missing versus zero ratings,
  incomplete coverage and missing payment terms. Pure: synthetic plans and
  ratings, no database.
  """
  use ExUnit.Case, async: true

  alias Emisint.Improvement.{Payment, PaymentPreview}

  @periods [
    %{id: "p-spr", code: "spr_26", label: "Spr '26", kind: :seasonal, position: 1},
    %{id: "p-sum", code: "sum_26", label: "Sum '26", kind: :seasonal, position: 2},
    %{id: "p-fal", code: "fal_26", label: "Fal '26", kind: :seasonal, position: 3},
    %{id: "p-18m", code: "review_18m", label: "18-month review", kind: :review_18m, position: 4}
  ]

  # Two Systems and two Student Outcome metrics.
  @metrics [
    %{id: "s1", code: "G1-M1", category: :systems},
    %{id: "s2", code: "G1-M2", category: :systems},
    %{id: "o1", code: "G2-M1", category: :student_outcome},
    %{id: "o2", code: "G2-M2", category: :student_outcome}
  ]

  defp plan(terms) do
    Map.merge(
      %{
        program: "nd_first_mou",
        max_rating: 3,
        payment_cap: nil,
        allocation_18m: nil,
        allocation_36m: nil,
        payment_terms_status: nil,
        payment_terms_note: nil,
        payment_terms_version: nil
      },
      terms
    )
  end

  @provisional %{
    payment_cap: Decimal.new("70000"),
    allocation_18m: Decimal.new("35000"),
    allocation_36m: Decimal.new("35000"),
    payment_terms_status: :provisional
  }

  defp rated(score),
    do: %{id: "r-#{System.unique_integer([:positive])}", rating_state: :rated, score: score}

  defp state(s), do: %{id: "r-#{System.unique_integer([:positive])}", rating_state: s, score: nil}

  # `ratings`: %{period_id => %{metric_id => rating}}
  defp row(slug, ratings, terms \\ %{}, periods \\ @periods) do
    %{
      slug: slug,
      name: slug,
      href: slug,
      group: "Team",
      workbook_note: nil,
      status: :loaded,
      defs: %{plan: plan(terms), metrics: @metrics, periods: periods},
      ratings: ratings
    }
  end

  defp summary(rows), do: %{rows: rows}

  defp all(s1, s2, o1, o2), do: %{"s1" => s1, "s2" => s2, "o1" => o1, "o2" => o2}

  defp preview(rows, period, checkpoint \\ :review_18m),
    do: PaymentPreview.build(summary(rows), period, checkpoint)

  defp only(p, slug), do: Enum.find(p.rows, &(&1.slug == slug))

  describe "period selection" do
    test "defaults to the latest seasonal period with any recorded rating, across participants" do
      rows = [
        row("a", %{"p-spr" => all(rated(1), rated(1), rated(1), rated(1))}),
        row("b", %{"p-sum" => %{"s1" => state(:not_applicable)}}),
        # Review ratings never choose the preview period.
        row("c", %{"p-18m" => all(rated(3), rated(3), rated(3), rated(3))})
      ]

      assert PaymentPreview.default_period(summary(rows)) == "sum_26"

      assert Enum.map(PaymentPreview.periods(summary(rows)), &{&1.code, &1.rated?}) == [
               {"spr_26", true},
               {"sum_26", true},
               {"fal_26", false}
             ]
    end

    test "uses the same period for every participant and never falls back" do
      rows = [
        row("a", %{"p-sum" => all(rated(2), rated(2), rated(1), rated(1))}),
        # "b" has Spr '26 ratings only: in Sum '26 it has none, and Spr '26 isn't used.
        row("b", %{"p-spr" => all(rated(3), rated(3), rated(3), rated(3))}, @provisional)
      ]

      p = preview(rows, "sum_26")
      assert p.period.code == "sum_26"
      b = only(p, "b")
      assert b.period.code == "sum_26"
      assert b.systems.value == nil and b.outcomes.value == nil
      assert b.coverage.recorded == 0
      assert PaymentPreview.average_reason(b.systems) == "No scored ratings (0 of 2 applicable)"
      assert PaymentPreview.weighted_reason(b) == "Needs both averages"

      assert PaymentPreview.payment_text(b) ==
               {:withheld, "Withheld: 4 of 4 applicable ratings not recorded"}
    end

    test "no period with ratings: nothing selected, every row says why" do
      p = preview([row("a", %{})], PaymentPreview.default_period(summary([row("a", %{})])))
      assert p.period == nil
      assert %{status: :no_period} = only(p, "a")
      assert PaymentPreview.row_reason(:no_period, nil) == "No reporting period selected."
    end

    test "a plan without the selected period says so instead of using another" do
      periods = Enum.reject(@periods, &(&1.code == "fal_26"))
      rows = [row("a", %{"p-fal" => %{}}), row("b", %{}, %{}, periods)]
      p = preview(rows, "fal_26")

      assert %{status: :period_not_in_plan} = only(p, "b")

      assert PaymentPreview.row_reason(:period_not_in_plan, p.period) ==
               "This plan has no Fal '26 period; no other period is used."
    end
  end

  describe "weights" do
    # Systems 2 and 2, Outcomes 1 and 1: averages 2 and 1.
    defp complete,
      do: [row("fy", %{"p-sum" => all(rated(2), rated(2), rated(1), rated(1))}, @provisional)]

    test "18-month: 70% Systems / 30% Outcomes, with the configured 18-month allocation" do
      r = only(preview(complete(), "sum_26", :review_18m), "fy")

      assert Decimal.equal?(r.systems.value, 2) and Decimal.equal?(r.outcomes.value, 1)
      # 2 × 0.7 + 1 × 0.3 = 1.7; $35,000 × 1.7 ÷ 3 = $19,833.33.
      assert Decimal.equal?(r.weighted, "1.7")
      assert r.complete?
      assert PaymentPreview.payment_text(r) == {:amount, "$19,833.33"}
      assert r.provisional_terms?
    end

    test "36-month: 30% Systems / 70% Outcomes, with the configured 36-month allocation" do
      p = preview(complete(), "sum_26", :review_36m)
      r = only(p, "fy")

      assert p.weights == %{systems: Decimal.new("0.30"), outcomes: Decimal.new("0.70")}
      # 2 × 0.3 + 1 × 0.7 = 1.3; $35,000 × 1.3 ÷ 3 = $15,166.67.
      assert Decimal.equal?(r.weighted, "1.3")
      assert PaymentPreview.payment_text(r) == {:amount, "$15,166.67"}
    end

    test "the amount equals the formal-review formula on the same ratings" do
      ratings = all(rated(2), rated(2), rated(1), rated(1))
      plan = plan(@provisional)

      formal =
        Payment.summary(plan, @metrics, %{review_18m: ratings}).checkpoints
        |> Enum.find(&(&1.checkpoint == :review_18m))

      r = only(preview(complete(), "sum_26"), "fy")
      assert r.estimate.estimate == formal.estimate
      assert Decimal.equal?(r.weighted, formal.weighted_score)
    end
  end

  describe "missing versus zero, and incomplete coverage" do
    test "an explicit 0 counts; the payment is calculated" do
      r =
        only(
          preview(
            [row("a", %{"p-sum" => all(rated(0), rated(2), rated(0), rated(0))}, @provisional)],
            "sum_26"
          ),
          "a"
        )

      assert Decimal.equal?(r.systems.value, 1)
      assert Decimal.equal?(r.outcomes.value, 0)
      assert %{rated: 2, total: 2} = r.outcomes
      # 1 × 0.7 + 0 × 0.3 = 0.7; $35,000 × 0.7 ÷ 3 = $8,166.67.
      assert PaymentPreview.payment_text(r) == {:amount, "$8,166.67"}
    end

    test "a missing rating is left out of the average, shown as partial, and withholds the payment" do
      r =
        only(
          preview(
            [
              row(
                "a",
                %{"p-sum" => %{"s1" => rated(3), "o1" => rated(0), "o2" => rated(3)}},
                @provisional
              )
            ],
            "sum_26"
          ),
          "a"
        )

      # Systems: only s1 scored (3), not (3 + 0) ÷ 2.
      assert Decimal.equal?(r.systems.value, 3)
      assert %{rated: 1, total: 2} = r.systems
      assert Decimal.equal?(r.outcomes.value, "1.5")

      assert %{recorded: 3, rated: 3, applicable: 4, na: 0, total: 4, missing: 1, unavailable: 0} =
               r.coverage

      refute r.complete?
      # A partial weighted score is shown; the amount isn't.
      assert Decimal.equal?(r.weighted, "2.55")

      assert PaymentPreview.payment_text(r) ==
               {:withheld, "Withheld: 1 of 4 applicable ratings not recorded"}

      assert r.estimate.estimate == nil
    end

    test "N/A is excluded; unavailable is not a score and withholds the payment" do
      ratings = all(rated(2), state(:not_applicable), rated(1), state(:unavailable))
      r = only(preview([row("a", %{"p-sum" => ratings}, @provisional)], "sum_26"), "a")

      assert %{rated: 1, total: 2, na: 1, applicable: 1} = r.systems
      assert %{rated: 2, applicable: 3, na: 1, missing: 0, unavailable: 1} = r.coverage

      assert PaymentPreview.payment_text(r) ==
               {:withheld, "Withheld: 1 marked unavailable"}

      # With the unavailable one rated, the N/A metric is simply left out.
      ratings = all(rated(2), state(:not_applicable), rated(1), rated(1))
      r = only(preview([row("a", %{"p-sum" => ratings}, @provisional)], "sum_26"), "a")
      assert r.complete?
      # Systems 2 (s2 N/A excluded), Outcomes 1: 2 × 0.7 + 1 × 0.3 = 1.7; $35,000 × 1.7 ÷ 3.
      assert PaymentPreview.payment_text(r) == {:amount, "$19,833.33"}
    end
  end

  describe "payment terms" do
    test "missing terms: scores are shown, the payment says terms aren't configured" do
      r =
        only(
          preview(
            [row("a", %{"p-sum" => all(rated(2), rated(2), rated(1), rated(1))})],
            "sum_26"
          ),
          "a"
        )

      assert Decimal.equal?(r.weighted, "1.7")
      assert PaymentPreview.payment_text(r) == {:no_terms, "Payment terms not configured"}
      refute r.provisional_terms?
    end

    test "confirmed terms aren't labeled provisional" do
      terms = %{@provisional | payment_terms_status: :confirmed}

      r =
        only(
          preview(
            [row("a", %{"p-sum" => all(rated(3), rated(3), rated(3), rated(3))}, terms)],
            "sum_26"
          ),
          "a"
        )

      assert PaymentPreview.payment_text(r) == {:amount, "$35,000.00"}
      refute r.provisional_terms?
    end
  end

  describe "for_participant/4 (the school page card)" do
    defp defs(terms \\ @provisional),
      do: %{plan: plan(terms), metrics: @metrics, periods: @periods}

    defp period(code), do: Enum.find(@periods, &(&1.code == code))

    test "the same figures as the portfolio row for that period" do
      for ratings <- [
            all(rated(0), rated(0), rated(0), rated(3)),
            all(rated(3), state(:not_applicable), rated(1), rated(2)),
            %{"s1" => rated(3), "o1" => rated(1), "o2" => rated(2)}
          ],
          checkpoint <- [:review_18m, :review_36m] do
        card = PaymentPreview.for_participant(defs(), period("sum_26"), ratings, checkpoint)

        portfolio =
          only(
            preview([row("a", %{"p-sum" => ratings}, @provisional)], "sum_26", checkpoint),
            "a"
          )

        assert PaymentPreview.payment_text(card.row) == PaymentPreview.payment_text(portfolio)
        assert card.row.coverage == portfolio.coverage
        assert card.row.weighted == portfolio.weighted
      end
    end

    test "an explicit 0 counts, N/A is excluded and a missing rating withholds" do
      zeros = all(rated(0), rated(0), rated(0), rated(3))
      card = PaymentPreview.for_participant(defs(), period("sum_26"), zeros)
      # 0 × 0.7 + 1.5 × 0.3 = 0.45; $35,000 × 0.45 ÷ 3 = $5,250.
      assert PaymentPreview.headline(card.row) == {:amount, "Estimated payment: $5,250.00"}

      na = all(rated(3), state(:not_applicable), rated(1), rated(2))
      card = PaymentPreview.for_participant(defs(), period("sum_26"), na)
      assert PaymentPreview.headline(card.row) == {:amount, "Estimated payment: $29,750.00"}
      assert Payment.coverage_text(card.row.estimate) =~ "1 N/A excluded"

      missing = %{"s1" => rated(3), "o1" => rated(1), "o2" => rated(2)}
      card = PaymentPreview.for_participant(defs(), period("sum_26"), missing)

      assert PaymentPreview.headline(card.row) ==
               {:withheld, "Withheld: 1 of 4 applicable ratings not recorded"}

      assert PaymentPreview.basis_text(card) ==
               "Sum '26 ratings · 18-month checkpoint (Systems 70% / Student Outcomes 30%)"

      assert card.row[:provisional_terms?]
    end

    test "a period without ratings is that period's preview, never another's" do
      card = PaymentPreview.for_participant(defs(), period("fal_26"), %{})
      assert card.period.code == "fal_26"

      assert PaymentPreview.headline(card.row) ==
               {:withheld, "Withheld: 4 of 4 applicable ratings not recorded"}
    end

    test "a review period selects nothing and says why" do
      card = PaymentPreview.for_participant(defs(), period("review_18m"), %{})
      assert card.row.status == :review_period
      assert {:unavailable, reason} = PaymentPreview.headline(card.row)
      assert reason =~ "18-month review is a formal review period"
      assert PaymentPreview.basis_text(card) =~ "18-month review (formal review period)"
    end

    test "no terms: no amount and no provisional label" do
      card =
        PaymentPreview.for_participant(
          defs(%{}),
          period("sum_26"),
          all(rated(2), rated(2), rated(1), rated(1))
        )

      assert PaymentPreview.headline(card.row) == {:no_terms, "Payment terms not configured"}
      refute card.row[:provisional_terms?]
    end
  end

  test "rows without figures keep their reason and are counted once" do
    rows = [
      row("a", %{}),
      %{slug: "b", name: "b", href: "x", group: "g", workbook_note: nil, status: :no_access},
      %{slug: "c", name: "c", href: "c", group: "g", workbook_note: nil, status: :no_plan}
    ]

    p = preview(rows, "sum_26")
    assert Enum.map(p.rows, & &1.slug) == ~w(a b c)
    assert Enum.map(p.rows, & &1.status) == [:loaded, :no_access, :no_plan]
    assert PaymentPreview.row_reason(:no_plan, p.period) == "No goal plan recorded."
  end
end
