defmodule Emisint.Improvement.WorkbookPaymentTermsTest do
  @moduledoc """
  Payment terms reconciled with the workbook (November 13, 2026):
  "Performance-Based Payment" rows 4–11 share the formulas of C3:I11, so
  every participant's 18-month payout is (weighted score ÷ 3) × $70,000 with
  Systems 70% / Outcomes 30%. No source sets a 36-month allocation: its
  weighted score is shown and its payment allocation needs confirmation.
  Buildings (including Solen High School) get no terms and no payment rows.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Improvement.{GoalPlan, Payment, PaymentPreview, Pilot, Portfolio, Seeds}

  @participants [
    Seeds.FortYates,
    Seeds.CannonBall,
    Seeds.Oberon,
    Seeds.Warwick,
    Seeds.Mandaree,
    Seeds.Dunseith,
    Seeds.Drayton,
    Seeds.ValleyMiddle
  ]

  defp plan(attrs \\ %{}) do
    Map.merge(
      %{
        program: "nd_first_mou",
        max_rating: 3,
        payment_terms_note: nil,
        payment_terms_version: 1
      },
      Map.merge(Seeds.Participant.workbook_payment_terms(), attrs)
    )
  end

  defp metrics(systems, outcomes) do
    s = for i <- 1..systems, do: %{id: "s#{i}", code: "S#{i}", category: :systems}
    o = for i <- 1..outcomes, do: %{id: "o#{i}", code: "O#{i}", category: :student_outcome}
    s ++ o
  end

  defp rated(metrics, fun),
    do: Map.new(metrics, &{&1.id, %{id: "r-" <> &1.id, rating_state: :rated, score: fun.(&1)}})

  defp checkpoint(summary, c), do: Enum.find(summary.checkpoints, &(&1.checkpoint == c))

  describe "the workbook formula" do
    test "18-month: (weighted ÷ 3) × $70,000, as Performance-Based Payment!I3:I11" do
      ms = metrics(4, 4)
      # Systems 2 (row C), Outcomes 3 (row E): D = 1.4, F = 0.9, G = 2.3, H = 0.7667.
      ratings = rated(ms, &if(&1.category == :systems, do: 2, else: 3))
      c = plan() |> Payment.summary(ms, %{review_18m: ratings}) |> checkpoint(:review_18m)

      assert c.status == :estimated
      assert Decimal.equal?(c.weighted_score, "2.3")
      # I = H × 70000 = 2.3 ÷ 3 × 70000 = 53,666.666… → $53,666.67.
      assert Payment.money(c.estimate) == "$53,666.67"
      assert Decimal.equal?(c.allocation, "70000")

      # The workbook's example row 3: C = E = 2.25 → I = 52,500.
      ex =
        rated(ms, fn _ -> 2 end)
        |> Map.merge(%{"s1" => %{id: "x", rating_state: :rated, score: 3}})

      c = plan() |> Payment.summary(ms, %{review_18m: ex}) |> checkpoint(:review_18m)
      # Systems (3+2+2+2) ÷ 4 = 2.25; Outcomes 2: G = 2.25 × .7 + 2 × .3 = 2.175.
      assert Payment.money(c.estimate) == "$50,750.00"

      full = rated(ms, fn _ -> 3 end)
      c = plan() |> Payment.summary(ms, %{review_18m: full}) |> checkpoint(:review_18m)
      assert Payment.money(c.estimate) == "$70,000.00"
    end

    test "36-month: 30% / 70% weighted score shown, amount withheld until its allocation is confirmed" do
      ms = metrics(2, 2)
      ratings = rated(ms, &if(&1.category == :systems, do: 2, else: 1))
      summary = Payment.summary(plan(), ms, %{review_18m: ratings, review_36m: ratings})
      c36 = checkpoint(summary, :review_36m)

      assert c36.status == :allocation_unconfirmed
      assert c36.allocation_unconfirmed?
      assert c36.estimate == nil
      # 2 × 0.3 + 1 × 0.7 = 1.3.
      assert Decimal.equal?(c36.weighted_score, "1.3")
      assert Payment.allocation_text(c36) == "Needs confirmation"

      assert Payment.status_text(c36) ==
               "Weighted score 1.30 of 3; payment allocation needs confirmation"

      # Never a $0 36-month amount: the total is a labeled subtotal.
      assert summary.combined.status == :partial

      assert Payment.combined_text(summary.combined) ==
               "Subtotal $39,666.67 (18-month review only); the 36-month review payment allocation needs confirmation"
    end

    test "missing and not-scored ratings still withhold the amount (the completeness safeguard)" do
      ms = metrics(2, 2)
      partial = rated(ms, fn _ -> 3 end) |> Map.delete("o2")
      c = plan() |> Payment.summary(ms, %{review_18m: partial}) |> checkpoint(:review_18m)
      assert c.status == :awaiting_review and c.estimate == nil
      assert Payment.status_text(c) == "Awaiting review: 1 review rating not recorded"

      # An explicit N/A is not applicable: excluded, so the estimate calculates.
      na = Map.put(partial, "o2", %{id: "n", rating_state: :not_applicable, score: nil})
      c = plan() |> Payment.summary(ms, %{review_18m: na}) |> checkpoint(:review_18m)
      assert c.status == :estimated
      assert Payment.money(c.estimate) == "$70,000.00"

      unavailable = Map.put(partial, "o2", %{id: "u", rating_state: :unavailable, score: nil})
      c = plan() |> Payment.summary(ms, %{review_18m: unavailable}) |> checkpoint(:review_18m)
      assert c.status == :awaiting_review
    end

    test "no Fort Yates split survives, and no terms are invented for buildings" do
      terms = Seeds.Participant.workbook_payment_terms()
      assert Decimal.equal?(terms.allocation_18m, "70000")
      assert terms.allocation_36m == nil
      refute inspect(terms) =~ "35000"

      for module <- @participants, do: assert(module.payment_terms() == terms, inspect(module))

      for module <- Seeds.available_schools() -- @participants do
        refute function_exported?(module, :payment_terms, 0), inspect(module)
        assert module.goal_plan().payment_cap == nil
      end
    end
  end

  describe "seeded records" do
    setup do
      org =
        seeded_organization!(
          name: "Workbook terms",
          schools: Seeds.available_schools(),
          workbook_ratings?: true
        )

      %{org: org, admin: user!(org, :emo_admin)}
    end

    test "all eight participants have the workbook terms; buildings have none", %{org: org} do
      plans =
        GoalPlan
        |> Ash.Query.load(:school)
        |> Ash.read!(tenant: org.id, authorize?: false)
        |> Map.new(&{&1.school.slug, &1})

      participant_slugs = Enum.map(@participants, & &1.school().slug)
      assert Enum.sort(participant_slugs) == Enum.sort(Enum.map(Pilot.roster(), & &1.slug))

      for slug <- participant_slugs do
        p = plans[slug]
        assert Decimal.equal?(p.allocation_18m, "70000"), slug
        assert p.allocation_36m == nil, slug
        assert p.payment_terms_status == :provisional, slug
      end

      for {slug, p} <- plans, slug not in participant_slugs do
        assert p.allocation_18m == nil and p.allocation_36m == nil and p.payment_cap == nil, slug
      end
    end

    test "the portfolio and preview count each participant once, never a building", %{
      org: org,
      admin: admin
    } do
      summary = Portfolio.summary(%Emisint.Scope{current_user: admin, current_tenant: org.id})
      slugs = Enum.map(summary.rows, & &1.slug)
      assert length(slugs) == 8
      assert Enum.sort(slugs) == Enum.sort(Enum.map(@participants, & &1.school().slug))
      refute "solen-high-school" in slugs

      preview = PaymentPreview.build(summary, "sum_26", :review_18m)
      assert Enum.map(preview.rows, & &1.slug) == slugs
      # Formal review: every participant has terms and awaits its review ratings.
      assert Enum.all?(summary.rows, &(&1.payment.estimate.status == :awaiting_review))
      assert Enum.all?(summary.rows, &Decimal.equal?(&1.payment.estimate.allocation, "70000"))
    end
  end
end
