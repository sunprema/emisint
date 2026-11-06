defmodule Emisint.Improvement.PaymentEstimateTest do
  @moduledoc """
  The provisional payment rule: checkpoint allocation × weighted review
  score ÷ 3, from formal review ratings only.
  """
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  require Ash.Query

  alias Emisint.Improvement.{GoalPlan, ImplementationRating, Metric, Payment, PaymentEstimate}

  # ── Pure calculation ────────────────────────────────────────────────────────

  defp plan(overrides \\ %{}) do
    Map.merge(
      %{
        program: "nd_first_mou",
        max_rating: 3,
        payment_cap: Decimal.new("70000"),
        allocation_18m: Decimal.new("35000"),
        allocation_36m: Decimal.new("35000"),
        payment_terms_status: :provisional,
        payment_terms_note: "Working note.",
        payment_terms_version: 2
      },
      overrides
    )
  end

  # Two Systems metrics and three Student Outcome metrics.
  @metrics [
    %{id: "s1", code: "S1", category: :systems},
    %{id: "s2", code: "S2", category: :systems},
    %{id: "o1", code: "O1", category: :student_outcome},
    %{id: "o2", code: "O2", category: :student_outcome},
    %{id: "o3", code: "O3", category: :student_outcome}
  ]

  defp ratings(scores) do
    Map.new(scores, fn {id, score} ->
      {id, %{id: "rating-#{id}", rating_state: :rated, score: score}}
    end)
  end

  defp checkpoint(summary, kind), do: Enum.find(summary.checkpoints, &(&1.checkpoint == kind))

  @mixed %{"s1" => 3, "s2" => 2, "o1" => 1, "o2" => 2, "o3" => 0}

  describe "Payment.summary/3" do
    test "18-month: 70% Systems / 30% Student Outcomes, partial score, rounded to cents" do
      summary = Payment.summary(plan(), @metrics, %{review_18m: ratings(@mixed)})
      c = checkpoint(summary, :review_18m)

      assert c.status == :estimated
      assert Decimal.equal?(c.systems_average, "2.5")
      assert Decimal.equal?(c.outcomes_average, "1")
      # 2.5 × 0.70 + 1 × 0.30 = 2.05; 35,000 × 2.05 ÷ 3 = 23,916.666…
      assert Decimal.equal?(c.weighted_score, "2.05")
      assert Decimal.equal?(c.estimate, "23916.67")
      assert Payment.status_text(c) == "$23,916.67"
      assert length(c.inputs) == 5
    end

    test "36-month: 30% Systems / 70% Student Outcomes" do
      summary = Payment.summary(plan(), @metrics, %{review_36m: ratings(@mixed)})
      c = checkpoint(summary, :review_36m)

      # 2.5 × 0.30 + 1 × 0.70 = 1.45; 35,000 × 1.45 ÷ 3 = 16,916.666…
      assert Decimal.equal?(c.weighted_score, "1.45")
      assert Decimal.equal?(c.estimate, "16916.67")
    end

    test "category averages are taken separately before weighting, never pooled" do
      metrics = [
        %{id: "s1", code: "S1", category: :systems},
        %{id: "o1", code: "O1", category: :student_outcome},
        %{id: "o2", code: "O2", category: :student_outcome},
        %{id: "o3", code: "O3", category: :student_outcome}
      ]

      scores = ratings(%{"s1" => 3, "o1" => 0, "o2" => 0, "o3" => 0})
      c = plan() |> Payment.summary(metrics, %{review_18m: scores}) |> checkpoint(:review_18m)

      # Separate: 3 × 0.70 + 0 × 0.30 = 2.1 (a pooled mean would give 0.75).
      assert Decimal.equal?(c.weighted_score, "2.1")
      assert Decimal.equal?(c.estimate, "24500.00")
    end

    test "all zeros is a valid $0.00 estimate, not missing" do
      zeros = ratings(Map.new(@metrics, &{&1.id, 0}))
      c = plan() |> Payment.summary(@metrics, %{review_18m: zeros}) |> checkpoint(:review_18m)

      assert c.status == :estimated
      assert Decimal.equal?(c.estimate, "0")
      assert Payment.status_text(c) == "$0.00"
    end

    test "full scores reach exactly the checkpoint allocation" do
      full = ratings(Map.new(@metrics, &{&1.id, 3}))

      summary = Payment.summary(plan(), @metrics, %{review_18m: full, review_36m: full})

      for kind <- [:review_18m, :review_36m] do
        assert Decimal.equal?(checkpoint(summary, kind).estimate, "35000.00")
      end

      assert summary.combined.status == :complete
      assert Decimal.equal?(summary.combined.amount, "70000.00")
      assert Payment.combined_text(summary.combined) == "$70,000.00 total (both checkpoints)"
    end

    test "the estimate never exceeds the checkpoint allocation" do
      # A score above the maximum cannot be saved (RatingShape); the cap
      # still holds if one ever reached the calculation.
      over = ratings(Map.new(@metrics, &{&1.id, 4}))
      c = plan() |> Payment.summary(@metrics, %{review_18m: over}) |> checkpoint(:review_18m)

      assert Decimal.equal?(c.estimate, "35000.00")
    end

    test "rounds half up to cents" do
      terms = %{
        payment_cap: Decimal.new("2"),
        allocation_18m: Decimal.new("1"),
        allocation_36m: Decimal.new("1")
      }

      metrics = [
        %{id: "s1", code: "S1", category: :systems},
        %{id: "o1", code: "O1", category: :student_outcome},
        %{id: "o2", code: "O2", category: :student_outcome},
        %{id: "o3", code: "O3", category: :student_outcome},
        %{id: "o4", code: "O4", category: :student_outcome}
      ]

      # 0 × 0.70 + 1.25 × 0.30 = 0.375; 1 × 0.375 ÷ 3 = 0.125 → 0.13.
      scores = ratings(%{"s1" => 0, "o1" => 1, "o2" => 1, "o3" => 1, "o4" => 2})

      c =
        terms
        |> plan()
        |> Payment.summary(metrics, %{review_18m: scores})
        |> checkpoint(:review_18m)

      assert Decimal.equal?(c.estimate, "0.13")
    end

    test "a missing rating leaves the checkpoint awaiting review — never $0, never renormalized" do
      partial = @mixed |> Map.delete("o3") |> ratings()
      c = plan() |> Payment.summary(@metrics, %{review_18m: partial}) |> checkpoint(:review_18m)

      assert c.status == :awaiting_review
      assert c.estimate == nil and c.weighted_score == nil
      assert c.missing == ["O3"]
      assert Payment.status_text(c) == "Awaiting review: 1 review rating not recorded"
      refute Payment.status_text(c) =~ "$"
    end

    test "not applicable or unavailable is not silently excluded" do
      scores =
        @mixed
        |> ratings()
        |> Map.put("o3", %{id: "rating-o3", rating_state: :not_applicable, score: nil})

      c = plan() |> Payment.summary(@metrics, %{review_18m: scores}) |> checkpoint(:review_18m)

      assert c.status == :awaiting_review
      assert c.not_scored == [{"O3", :not_applicable}]
      assert Payment.status_text(c) =~ "marked not applicable or unavailable (O3)"
    end

    test "with one checkpoint complete, the combined line is a labeled subtotal" do
      summary = Payment.summary(plan(), @metrics, %{review_18m: ratings(@mixed)})

      assert summary.combined.status == :partial
      assert checkpoint(summary, :review_36m).status == :awaiting_review

      assert Payment.combined_text(summary.combined) ==
               "Subtotal $23,916.67 (18-month review only); the total awaits the other review"
    end

    test "without allocations nothing is estimated" do
      no_terms =
        plan(%{allocation_18m: nil, allocation_36m: nil, payment_terms_status: :unconfirmed})

      summary =
        Payment.summary(no_terms, @metrics, %{review_18m: ratings(Map.new(@metrics, &{&1.id, 3}))})

      assert Enum.all?(summary.checkpoints, &(&1.status == :no_terms))
      assert summary.combined.status == :not_configured
      assert Payment.combined_text(summary.combined) == "Not configured"
      assert summary.label == "Estimated payment — not configured"
      assert Payment.terms_text(summary.terms) =~ "Not configured"
    end

    test "provisional terms are worded as a working assumption, not contract terms" do
      terms = Payment.terms(plan())
      text = Payment.terms_summary(terms)

      assert text =~ "Working assumption, not confirmed contract terms"
      assert text =~ "$70,000.00 total per school across both checkpoints"
      assert text =~ "$35,000.00 to the 18-month review and $35,000.00 to the 36-month review"

      # The details give the provisional sentence once, without restating the summary.
      assert Payment.terms_text(terms) ==
               "Provisional estimate based on an assumed $70,000 total per school, split equally between the 18-month and 36-month checkpoints. Final payment terms are pending confirmation."

      assert Payment.label() == "Estimated payment — provisional cap and split"
    end
  end

  # ── Seeded Fort Yates records ───────────────────────────────────────────────

  describe "Fort Yates terms and review ratings" do
    setup do
      org = seeded_organization!(workbook_ratings?: true)
      [plan] = Ash.read!(GoalPlan, tenant: org.id, authorize?: false)
      metrics = Ash.read!(Metric, tenant: org.id, authorize?: false)

      %{
        org: org,
        plan: plan,
        metrics: metrics,
        contributor: contributor!(org),
        admin: user!(org, :emo_admin),
        review: period!(org, "review_18m")
      }
    end

    test "the seeds set the provisional $70,000 cap split $35,000 / $35,000", %{plan: plan} do
      assert plan.payment_terms_status == :provisional
      assert Decimal.equal?(plan.payment_cap, "70000")
      assert Decimal.equal?(plan.allocation_18m, "35000")
      assert Decimal.equal?(plan.allocation_36m, "35000")
      assert plan.payment_terms_note =~ "Ram authorized a best-estimate payment rule"

      assert plan.payment_terms_note =~
               "our selected provisional assumptions, not terms he specified"
    end

    test "allocations must sum to the cap", %{org: org, plan: plan} do
      assert {:error, error} =
               plan
               |> Ash.Changeset.for_update(
                 :set_payment_terms,
                 %{allocation_18m: Decimal.new("40000")},
                 tenant: org.id,
                 authorize?: false
               )
               |> Ash.update()

      assert Exception.message(error) =~ "must sum to the payment cap"
    end

    test "no user can change the payment terms, not even an org admin", ctx do
      assert {:error, %Ash.Error.Forbidden{}} =
               ctx.plan
               |> Ash.Changeset.for_update(
                 :set_payment_terms,
                 %{payment_terms_status: :confirmed},
                 tenant: ctx.org.id,
                 actor: ctx.admin
               )
               |> Ash.update()
    end

    test "seasonal workbook ratings are never payment inputs", ctx do
      assert Ash.count!(ImplementationRating, tenant: ctx.org.id, authorize?: false) > 0

      summary = Payment.summary(ctx.plan, ctx.metrics, review_ratings(ctx))

      for c <- summary.checkpoints do
        assert c.status == :awaiting_review
        assert length(c.missing) == 18
      end
    end

    test "a seasonal rating can't be recorded in a review period, a review rating can", ctx do
      metric = hd(ctx.metrics)

      attrs = %{
        metric_id: metric.id,
        reporting_period_id: ctx.review.id,
        rating_state: :rated,
        score: 2
      }

      assert {:error, _} =
               Ash.create(ImplementationRating, attrs,
                 action: :record,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )

      assert {:ok, rating} =
               Ash.create(ImplementationRating, attrs,
                 action: :record_review,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )

      assert rating.author_id == ctx.contributor.id

      # And a review rating can't be recorded in a seasonal period.
      assert {:error, _} =
               Ash.create(
                 ImplementationRating,
                 %{attrs | reporting_period_id: period!(ctx.org, "fal_26").id},
                 action: :record_review,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )
    end

    test "a viewer can't record a review rating", ctx do
      viewer = user!(ctx.org, :school_leader)
      membership!(viewer, school!(ctx.org), :viewer, ctx.org)
      metric = hd(ctx.metrics)

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(
                 ImplementationRating,
                 %{
                   metric_id: metric.id,
                   reporting_period_id: ctx.review.id,
                   rating_state: :rated,
                   score: 2
                 },
                 action: :record_review,
                 tenant: ctx.org.id,
                 actor: viewer
               )
    end

    test "an estimate is refused until every review rating is recorded", ctx do
      [first | _] = ctx.metrics
      record_review!(ctx, first, 3)

      assert {:error, error} = record_estimate(ctx, ctx.admin)

      assert Exception.message(error) =~
               "can't be estimated yet: Awaiting review: 17 review ratings"
    end

    test "a recorded estimate keeps its assumptions when the terms later change", ctx do
      for m <- ctx.metrics, do: record_review!(ctx, m, if(m.category == :systems, do: 3, else: 1))

      assert {:error, %Ash.Error.Forbidden{}} = record_estimate(ctx, ctx.contributor)
      assert {:ok, estimate} = record_estimate(ctx, ctx.admin)

      # Systems 3, Outcomes 1: 3 × 0.70 + 1 × 0.30 = 2.4; 35,000 × 2.4 ÷ 3 = 28,000.
      assert estimate.checkpoint == :review_18m
      assert Decimal.equal?(estimate.amount, "28000.00")
      assert Decimal.equal?(estimate.allocation, "35000")
      assert Decimal.equal?(estimate.payment_cap, "70000")
      assert Decimal.equal?(estimate.weighted_score, "2.4")
      assert estimate.terms_status == :provisional
      assert estimate.label == "Estimated payment — provisional cap and split"
      assert length(estimate.inputs) == 18

      ctx.plan
      |> Ash.Changeset.for_update(
        :set_payment_terms,
        %{
          payment_cap: Decimal.new("80000"),
          allocation_18m: Decimal.new("40000"),
          allocation_36m: Decimal.new("40000")
        },
        tenant: ctx.org.id,
        authorize?: false
      )
      |> Ash.update!()

      [stored] = Ash.read!(PaymentEstimate, tenant: ctx.org.id, authorize?: false)
      assert Decimal.equal?(stored.amount, "28000.00")
      assert Decimal.equal?(stored.allocation, "35000")
      assert stored.terms_version == estimate.terms_version

      {:ok, again} = record_estimate(ctx, ctx.admin)
      assert Decimal.equal?(again.amount, "32000.00")
      assert again.terms_version == estimate.terms_version + 1
    end

    test "a corrected review rating replaces the original in the estimate", ctx do
      ratings = for m <- ctx.metrics, do: record_review!(ctx, m, 3)
      {:ok, full} = record_estimate(ctx, ctx.admin)
      assert Decimal.equal?(full.amount, "35000.00")

      systems =
        Enum.find(
          ratings,
          &(Enum.find(ctx.metrics, fn m -> m.id == &1.metric_id end).category == :systems)
        )

      {:ok, _} =
        Ash.create(
          ImplementationRating,
          %{
            corrects_id: systems.id,
            correction_reason: "Entered wrong score",
            rating_state: :rated,
            score: 0
          },
          action: :correct,
          tenant: ctx.org.id,
          actor: ctx.contributor
        )

      {:ok, corrected} = record_estimate(ctx, ctx.admin)

      # Systems (3 × 7 + 0) ÷ 8 = 2.625; 2.625 × 0.70 + 3 × 0.30 = 2.7375; × 35,000 ÷ 3 = 31,937.50.
      assert Decimal.equal?(corrected.amount, "31937.50")
    end
  end

  defp record_review!(ctx, metric, score) do
    Ash.create!(
      ImplementationRating,
      %{
        metric_id: metric.id,
        reporting_period_id: ctx.review.id,
        rating_state: :rated,
        score: score
      },
      action: :record_review,
      tenant: ctx.org.id,
      actor: ctx.contributor
    )
  end

  defp record_estimate(ctx, actor) do
    Ash.create(PaymentEstimate, %{reporting_period_id: ctx.review.id},
      action: :record,
      tenant: ctx.org.id,
      actor: actor
    )
  end

  defp review_ratings(ctx) do
    for code <- ["review_18m", "review_36m"], into: %{} do
      period = period!(ctx.org, code)

      ratings =
        ImplementationRating
        |> Ash.Query.for_read(:current, %{}, tenant: ctx.org.id, authorize?: false)
        |> Ash.Query.filter(reporting_period_id == ^period.id)
        |> Ash.read!()

      {period.kind, Map.new(ratings, &{&1.metric_id, &1})}
    end
  end
end
