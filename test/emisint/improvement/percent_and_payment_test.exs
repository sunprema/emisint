defmodule Emisint.Improvement.PercentAndPaymentTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  alias Emisint.Improvement.{GoalPlan, Metric, Payment, Percent}

  describe "Percent.parse/1" do
    test "normalizes familiar 0–100 input to 0–1" do
      assert {:ok, value} = Percent.parse("24.5")
      assert Decimal.equal?(value, "0.245")

      assert {:ok, value} = Percent.parse(" 80 % ")
      assert Decimal.equal?(value, "0.8")

      assert {:ok, value} = Percent.parse("0")
      assert Decimal.equal?(value, 0)

      assert {:ok, value} = Percent.parse("100")
      assert Decimal.equal?(value, 1)
    end

    test "blank input is nil, not zero" do
      assert {:ok, nil} = Percent.parse("")
      assert {:ok, nil} = Percent.parse("   ")
      assert {:ok, nil} = Percent.parse(nil)
    end

    test "rejects out-of-range and non-numeric input" do
      assert {:error, _} = Percent.parse("-1")
      assert {:error, _} = Percent.parse("100.1")
      assert {:error, _} = Percent.parse("abc")
      assert {:error, _} = Percent.parse("24,5")
    end

    test "formats proportions back to percentages" do
      assert Percent.format(Decimal.new("0.245")) == "24.5%"
      assert Percent.format(Decimal.new("0.9")) == "90%"
      assert Percent.format(Decimal.new("0.429")) == "42.9%"
      assert Percent.format(nil) == nil
      assert Percent.number(Decimal.new("0.27")) == "27"
    end
  end

  describe "Payment.summary/3" do
    test "with no formal review ratings, every checkpoint awaits review and no amount is shown" do
      org = seeded_organization!(workbook_ratings?: true)
      [plan] = Ash.read!(GoalPlan, tenant: org.id, authorize?: false)
      metrics = Ash.read!(Metric, tenant: org.id, authorize?: false)

      summary = Payment.summary(plan, metrics)

      assert summary.systems_metric_count == 8
      assert summary.outcomes_metric_count == 10
      assert summary.terms.status == :provisional
      assert Decimal.equal?(summary.terms.cap, "70000")

      assert Enum.all?(
               summary.checkpoints,
               &(&1.status == :awaiting_review and &1.estimate == nil)
             )

      # The 36-month allocation isn't set by any source: said, never treated as $0.
      [eighteen, thirty_six] = summary.checkpoints
      refute eighteen.allocation_unconfirmed?
      assert thirty_six.allocation_unconfirmed?
      assert summary.combined.status == :awaiting_review

      assert Payment.combined_text(summary.combined) ==
               "Awaiting review; the 36-month review payment allocation needs confirmation"
    end

    test "uses the confirmed per-checkpoint weights, not one fixed pair" do
      assert [eighteen, thirty_six] = Payment.checkpoints("nd_first_mou")

      assert eighteen.checkpoint == :review_18m
      assert Decimal.equal?(eighteen.systems_weight, "0.70")
      assert Decimal.equal?(eighteen.outcomes_weight, "0.30")

      assert thirty_six.checkpoint == :review_36m
      assert Decimal.equal?(thirty_six.systems_weight, "0.30")
      assert Decimal.equal?(thirty_six.outcomes_weight, "0.70")

      # Other programs have no confirmed weights; nothing is assumed.
      assert Payment.checkpoints("other_program") == []
    end

    test "counts follow the metrics given, not hard-coded totals" do
      plan = %{
        payment_cap: nil,
        allocation_18m: nil,
        allocation_36m: nil,
        payment_terms_status: :unconfirmed,
        payment_terms_note: nil,
        payment_terms_version: 1,
        program: "nd_first_mou",
        max_rating: 3
      }

      metrics = [
        %{id: "a", code: "A", category: :systems},
        %{id: "b", code: "B", category: :student_outcome},
        %{id: "c", code: "C", category: :student_outcome}
      ]

      assert %{systems_metric_count: 1, outcomes_metric_count: 2} = Payment.summary(plan, metrics)
    end
  end
end
