defmodule Emisint.Improvement.NaRatingRuleTest do
  @moduledoc """
  N/A handling in ND First payment calculations (November 13, 2026), the
  same in the formal-review calculation (`Payment`) and the current-ratings
  preview (`PaymentPreview`):

    * an explicit N/A rating is excluded from the category average and from
      the required-rating count;
    * a missing (unentered) applicable rating still withholds the estimate,
      and is never turned into N/A;
    * a numeric 0 counts;
    * a category with no numeric rating makes the estimate unavailable
      (never 0, weight never moved to the other category).
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures

  alias Emisint.Improvement.{ImplementationRating, Payment, PaymentPreview, Portfolio, Seeds}

  defp plan,
    do:
      Map.merge(
        %{
          program: "nd_first_mou",
          max_rating: 3,
          payment_terms_note: nil,
          payment_terms_version: 1
        },
        Seeds.Participant.workbook_payment_terms()
      )

  # Two Systems and two Student Outcome metrics.
  @metrics [
    %{id: "s1", code: "S1", category: :systems},
    %{id: "s2", code: "S2", category: :systems},
    %{id: "o1", code: "O1", category: :student_outcome},
    %{id: "o2", code: "O2", category: :student_outcome}
  ]

  defp score(n),
    do: %{id: "r#{System.unique_integer([:positive])}", rating_state: :rated, score: n}

  defp na,
    do: %{id: "n#{System.unique_integer([:positive])}", rating_state: :not_applicable, score: nil}

  defp formal(ratings, checkpoint \\ :review_18m) do
    plan()
    |> Payment.summary(@metrics, %{checkpoint => ratings})
    |> Map.fetch!(:checkpoints)
    |> Enum.find(&(&1.checkpoint == checkpoint))
  end

  # The same ratings as the current-ratings preview sees them (one period).
  defp preview(ratings, checkpoint \\ :review_18m) do
    row = %{
      slug: "x",
      name: "x",
      href: "x",
      group: "g",
      workbook_note: nil,
      status: :loaded,
      defs: %{
        plan: plan(),
        metrics: @metrics,
        periods: [%{id: "p", code: "sum_26", label: "Sum '26", kind: :seasonal, position: 1}]
      },
      ratings: %{"p" => ratings}
    }

    %{rows: [row]} |> PaymentPreview.build("sum_26", checkpoint) |> Map.fetch!(:rows) |> hd()
  end

  test "an explicit N/A is excluded from the average and the required count" do
    ratings = %{"s1" => score(3), "s2" => na(), "o1" => score(1), "o2" => score(2)}
    c = formal(ratings)

    # Systems = 3 (not (3 + 0) ÷ 2); Outcomes = 1.5; 3 × 0.7 + 1.5 × 0.3 = 2.55.
    assert c.status == :estimated
    assert Decimal.equal?(c.systems_average, 3)
    assert Decimal.equal?(c.weighted_score, "2.55")
    assert Payment.money(c.estimate) == "$59,500.00"
    assert c.excluded_na == ["S2"]
    assert Payment.coverage_text(c) == "3 of 3 applicable metrics rated · 1 N/A excluded"

    p = preview(ratings)
    assert PaymentPreview.payment_text(p) == {:amount, "$59,500.00"}
    assert %{rated: 3, applicable: 3, na: 1, missing: 0} = p.coverage
    assert p.complete?
  end

  test "a missing applicable rating withholds the estimate and is not treated as N/A" do
    ratings = %{"s1" => score(3), "o1" => score(1), "o2" => score(2)}
    c = formal(ratings)

    assert c.status == :awaiting_review and c.estimate == nil
    assert c.missing == ["S2"]
    assert c.excluded_na == []
    assert Payment.coverage_text(c) == "3 of 4 applicable metrics rated"
    assert Payment.status_text(c) == "Awaiting review: 1 review rating not recorded"

    p = preview(ratings)

    assert PaymentPreview.payment_text(p) ==
             {:withheld, "Withheld: 1 of 4 applicable ratings not recorded"}

    refute p.complete?
  end

  test "a numeric 0 is a rating and counts" do
    ratings = %{"s1" => score(0), "s2" => score(0), "o1" => score(0), "o2" => score(3)}
    c = formal(ratings)

    assert c.status == :estimated
    assert Decimal.equal?(c.systems_average, 0)
    # 0 × 0.7 + 1.5 × 0.3 = 0.45; $70,000 × 0.45 ÷ 3 = $10,500.
    assert Payment.money(c.estimate) == "$10,500.00"
    assert Payment.coverage_text(c) == "4 of 4 applicable metrics rated"
    assert PaymentPreview.payment_text(preview(ratings)) == {:amount, "$10,500.00"}

    # All zeros: a real $0.00 estimate, not "missing".
    zeros = Map.new(@metrics, &{&1.id, score(0)})
    assert Payment.money(formal(zeros).estimate) == "$0.00"
  end

  test "an entirely N/A category makes the estimate unavailable, never 0 or reweighted" do
    ratings = %{"s1" => na(), "s2" => na(), "o1" => score(3), "o2" => score(3)}

    for checkpoint <- [:review_18m, :review_36m] do
      c = formal(ratings, checkpoint)
      assert c.status == :category_unavailable, inspect(checkpoint)
      assert c.empty_categories == [:systems]
      assert c.estimate == nil and c.weighted_score == nil
      assert c.systems_average == nil
      assert Decimal.equal?(c.outcomes_average, 3)

      assert Payment.status_text(c) ==
               "Estimate unavailable: no numeric Systems ratings (a category is never scored 0 or reweighted)"

      assert Payment.coverage_text(c) == "2 of 2 applicable metrics rated · 2 N/A excluded"

      p = preview(ratings, checkpoint)

      assert {:unavailable, "Estimate unavailable: no numeric Systems ratings" <> _} =
               PaymentPreview.payment_text(p)

      assert p.weighted == nil
      assert PaymentPreview.average_reason(p.systems) == "All 2 N/A: no numeric ratings"
    end
  end

  test "Dunseith: the workbook's N/A (G5-M3) is excluded and the preview calculates" do
    org =
      seeded_organization!(
        name: "N/A rule",
        schools: [Seeds.Dunseith],
        workbook_ratings?: true
      )

    states = fn ->
      ImplementationRating
      |> Ash.read!(tenant: org.id, authorize?: false)
      |> Enum.map(&{&1.id, &1.rating_state, &1.score})
      |> Enum.sort()
    end

    before = states.()
    # Stored exactly as the workbook (Dunseith Goals!E27, F27 = "N/A").
    assert Enum.count(before, &match?({_, :not_applicable, nil}, &1)) == 2

    assert {"G5-M3", "sum_26", :not_applicable, "Dunseith Goals!F27"} in Seeds.Dunseith.workbook_ratings()

    summary =
      Portfolio.summary(%Emisint.Scope{
        current_user: user!(org, :emo_admin),
        current_tenant: org.id
      })

    [row] = PaymentPreview.build(summary, "sum_26", :review_18m).rows

    assert %{rated: 15, applicable: 15, na: 1, missing: 0} = row.coverage
    assert row.complete?
    # Systems 13 ÷ 6, Outcomes 17 ÷ 9: 2.0833…; $70,000 × 2.0833… ÷ 3.
    assert PaymentPreview.payment_text(row) == {:amount, "$48,611.11"}

    assert Payment.coverage_text(row.estimate) ==
             "15 of 15 applicable metrics rated · 1 N/A excluded"

    # Reading never changes stored ratings.
    assert states.() == before
  end
end
