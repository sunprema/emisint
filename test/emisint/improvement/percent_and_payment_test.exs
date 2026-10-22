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

  describe "Payment.summary/2" do
    test "awaits review, has no amount, and counts categories from the plan's metrics" do
      org = seeded_organization!(workbook_ratings?: true)
      [plan] = Ash.read!(GoalPlan, tenant: org.id, authorize?: false)
      metrics = Ash.read!(Metric, tenant: org.id, authorize?: false)

      summary = Payment.summary(plan, metrics)

      assert summary.status == :awaiting_review
      assert summary.amount == nil
      assert summary.systems_metric_count == 8
      assert summary.outcomes_metric_count == 10
      assert Decimal.equal?(summary.systems_weight, "0.70")
      assert Decimal.equal?(summary.payment_cap, "70000")
    end

    test "counts follow the metrics given, not hard-coded totals" do
      plan = %{payment_cap: nil, systems_weight: nil, outcomes_weight: nil, max_rating: 3}

      metrics = [
        %{category: :systems},
        %{category: :student_outcome},
        %{category: :student_outcome}
      ]

      assert %{systems_metric_count: 1, outcomes_metric_count: 2} = Payment.summary(plan, metrics)
    end
  end
end
