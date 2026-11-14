defmodule Emisint.Improvement.PortfolioTest do
  @moduledoc """
  The ND FIRST portfolio summary (`Portfolio.summary/1`) against the
  workbook's "Goals Dashboard" and "Performance-Based Payment" sheets:
  workbook values, one row per participant (no district/building double
  counting), missing data kept missing, and rows filtered by permissions.
  """
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  alias Emisint.Improvement.{Dashboard, ImplementationRating, Payment, Portfolio, Seeds}

  @participants ~w(fort-yates-ms cannon-ball-elementary oberon-elementary warwick-public-school-district mandaree-public-school-district dunseith-public-school-district drayton-public-school-district valley-middle-school)

  @buildings ~w(drayton-elementary drayton-high-school dunseith-elementary dunseith-high-school mandaree-elementary mandaree-high-school warwick-elementary warwick-middle-school warwick-high-school)

  setup do
    org =
      seeded_organization!(
        name: "ND First portfolio",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp scope(user, org), do: %Emisint.Scope{current_user: user, current_tenant: org.id}
  defp row(summary, slug), do: Enum.find(summary.rows, &(&1.slug == slug))
  defp dec(s), do: Decimal.new(s)

  # Workbook cached values have 9–10 significant digits.
  defp assert_close(%Decimal{} = value, expected) do
    assert Decimal.compare(Decimal.abs(Decimal.sub(value, dec(expected))), dec("0.000000001")) ==
             :lt,
           "#{value} != #{expected}"
  end

  describe "Goals Dashboard values" do
    test "counts and Spr '26 / Sum '26 averages match the workbook (Goals Dashboard!C5:H12)",
         ctx do
      s = Portfolio.summary(scope(ctx.admin, ctx.org))

      # {slug, C, D, E, F, G, H} as cached in the workbook.
      for {slug, c, d, e, f, g, h} <- [
            {"fort-yates-ms", 8, 10, "1.25", "1.6", "1.375", "1.6"},
            {"oberon-elementary", 9, 12, "1", "1.583333333", "1.666666667", "1.916666667"},
            {"warwick-public-school-district", 14, 11, "1.857142857", "1.636363636",
             "1.928571429", "2"},
            {"mandaree-public-school-district", 3, 3, "1", "3", "2", "3"},
            {"dunseith-public-school-district", 7, 9, "1.833333333", "1.888888889", "2.166666667",
             "1.888888889"},
            {"drayton-public-school-district", 6, 7, "1.333333333", "2.142857143", "1.666666667",
             "2.142857143"},
            {"valley-middle-school", 16, 10, "1.461538462", "1.4", "2.125", "1.8"}
          ] do
        r = row(s, slug)
        assert r.status == :loaded, slug
        assert r.counts == %{systems: c, outcomes: d}, slug
        assert_close(r.columns.spr_26.systems.value, e)
        assert_close(r.columns.spr_26.outcomes.value, f)
        assert_close(r.columns.sum_26.systems.value, g)
        assert_close(r.columns.sum_26.outcomes.value, h)
      end

      # Workbook group ("School Directory" G2:G9) and order.
      assert Enum.map(s.rows, & &1.workbook_name) ==
               [
                 "Fort Yates",
                 "Solen",
                 "Oberon",
                 "Warwick",
                 "Mandaree",
                 "Dunseith",
                 "Drayton",
                 "Valley MS"
               ]

      assert row(s, "valley-middle-school").group == "North Team"
      assert row(s, "fort-yates-ms").group == "South Team"
    end

    test "unscored ratings are left out, not counted as zero (AVERAGEIF)", ctx do
      s = Portfolio.summary(scope(ctx.admin, ctx.org))
      # Valley Spr '26 Systems: 13 of 16 scored in the workbook (E12 = 1.461538462).
      assert %{rated: 13, total: 16} = row(s, "valley-middle-school").columns.spr_26.systems
      # Dunseith Spr '26 Systems: 6 of 7 (E10 = 1.833333333).
      assert %{rated: 6, total: 7} =
               row(s, "dunseith-public-school-district").columns.spr_26.systems
    end

    test "the AVERAGE row averages the shown participants' values with its coverage", ctx do
      a = Portfolio.summary(scope(ctx.admin, ctx.org)).average

      assert a.participants == 8
      # (8 + 5 + 9 + 14 + 3 + 7 + 6 + 16) / 8 = 8.5, as the workbook's C13.
      assert Decimal.equal?(a.counts.systems.value, "8.5")
      assert a.counts.systems.of == 8
      # Spr '26 Systems: mean of the eight E values (Cannon Ball, the workbook's Solen row: 1.2).
      expected =
        ~w(1.25 1.2 1 1.857142857142857142857142857 1 1.833333333333333333333333333 1.333333333333333333333333333 1.461538461538461538461538462)
        |> Enum.map(&dec/1)
        |> Enum.reduce(&Decimal.add/2)
        |> Decimal.div(8)

      assert_close(a.columns.spr_26.systems.value, Decimal.to_string(expected))
      # No participant has Fal '26 ratings: missing, not zero.
      assert a.columns.fal_26.systems == %{value: nil, of: 0, participants: 8}
    end
  end

  describe "participants, not buildings" do
    test "one row per participant; buildings add no rows, ratings or payment", ctx do
      s = Portfolio.summary(scope(ctx.admin, ctx.org))
      slugs = for r <- s.rows, r.slug, do: r.slug

      assert slugs == [
               "fort-yates-ms",
               "cannon-ball-elementary",
               "oberon-elementary",
               "warwick-public-school-district",
               "mandaree-public-school-district",
               "dunseith-public-school-district",
               "drayton-public-school-district",
               "valley-middle-school"
             ]

      assert Enum.sort(slugs) == Enum.sort(@participants)
      refute Enum.any?(slugs, &(&1 in @buildings))
      assert s.coverage == %{loaded: 8, listed: 8}
      assert s.average.participants == 8
      # The Drayton row is the district's own workbook sheet (6 + 7 metrics).
      assert row(s, "drayton-public-school-district").counts == %{systems: 6, outcomes: 7}
    end

    test "the workbook's Solen row is the Cannon Ball participant, not a ninth row", ctx do
      s = Portfolio.summary(scope(ctx.admin, ctx.org))
      assert length(s.rows) == 8
      assert [cb] = Enum.filter(s.rows, &(&1.workbook_name == "Solen"))
      assert %{slug: "cannon-ball-elementary", name: "Cannon Ball", status: :loaded} = cb

      viewer = user!(ctx.org, :school_leader)
      membership!(viewer, school!(ctx.org, "oberon-elementary"), :viewer, ctx.org)

      refute Enum.any?(
               Portfolio.summary(scope(viewer, ctx.org)).rows,
               &(&1.workbook_name == "Solen")
             )
    end
  end

  describe "missing data and review ratings" do
    test "no review ratings: checks and payment stay missing for every participant", ctx do
      s = Portfolio.summary(scope(ctx.admin, ctx.org))
      fy = row(s, "fort-yates-ms")

      assert fy.columns.fal_26.systems.value == nil

      assert fy.columns.check_18m.systems == %{
               value: nil,
               rated: 0,
               total: 8,
               na: 0,
               applicable: 8
             }

      assert fy.payment.overall == nil and fy.payment.performance == nil
      assert fy.payment.estimate.status == :awaiting_review
      assert Payment.status_text(fy.payment.estimate) =~ "Awaiting review"

      # Every participant has the workbook's 18-month terms (November 13, 2026).
      oberon = row(s, "oberon-elementary")
      assert oberon.payment.estimate.status == :awaiting_review
      assert Payment.status_text(oberon.payment.estimate) =~ "Awaiting review: 21 review ratings"
      assert Decimal.equal?(oberon.payment.estimate.allocation, "70000")
    end

    test "partial review ratings give a partial check and no estimate; complete ones an estimate",
         ctx do
      admin_scope = scope(ctx.admin, ctx.org)
      {:ok, defs} = Dashboard.load_plan(admin_scope, school!(ctx.org, "fort-yates-ms"))
      review = Enum.find(defs.periods, &(&1.kind == :review_18m))

      {systems, outcomes} = Enum.split_with(defs.metrics, &(&1.category == :systems))
      record = fn m, score -> record_review!(ctx, m, review, score) end

      # Systems only: the Systems check exists; overall needs both categories.
      Enum.each(systems, &record.(&1, 3))
      fy_row = row(Portfolio.summary(scope(ctx.admin, ctx.org)), "fort-yates-ms")
      assert %{rated: 8, total: 8} = fy_row.columns.check_18m.systems
      assert Decimal.equal?(fy_row.payment.systems_weighted, "2.1")
      assert fy_row.payment.outcomes_score.value == nil
      assert fy_row.payment.overall == nil
      assert fy_row.payment.estimate.status == :awaiting_review

      # Every metric rated: 3 × 70% + 1 × 30% = 2.4; 2.4 ÷ 3 = 80%; the workbook's
      # I column: 80% × $70,000 = $56,000.
      Enum.each(outcomes, &record.(&1, 1))
      fy_row = row(Portfolio.summary(scope(ctx.admin, ctx.org)), "fort-yates-ms")
      assert Decimal.equal?(fy_row.payment.overall, "2.4")
      assert Portfolio.percent(fy_row.payment.performance) == "80%"
      assert fy_row.payment.estimate.status == :estimated
      assert Decimal.equal?(fy_row.payment.estimate.estimate, "56000.00")

      assert Decimal.equal?(
               fy_row.payment.estimate.estimate,
               Decimal.mult(fy_row.payment.performance, 70000)
             )

      # Seasonal columns are unaffected by review ratings.
      assert_close(fy_row.columns.spr_26.systems.value, "1.25")
    end
  end

  describe "access" do
    test "a school member sees only that participant, and averages cover only it", ctx do
      viewer = user!(ctx.org, :school_leader)
      membership!(viewer, school!(ctx.org, "oberon-elementary"), :viewer, ctx.org)

      s = Portfolio.summary(scope(viewer, ctx.org))
      assert Enum.map(s.rows, & &1.slug) == ["oberon-elementary"]
      assert s.average.participants == 1
      assert Decimal.equal?(s.average.counts.systems.value, 9)
    end

    test "a building-only member gets the participant row without its figures", ctx do
      member = user!(ctx.org, :school_leader)
      membership!(member, school!(ctx.org, "drayton-elementary"), :viewer, ctx.org)

      s = Portfolio.summary(scope(member, ctx.org))

      assert [
               %{
                 slug: "drayton-public-school-district",
                 status: :no_access,
                 href: "drayton-elementary"
               } = r
             ] =
               s.rows

      refute Map.has_key?(r, :columns)
      assert s.average.participants == 0
    end

    test "another organization's admin sees none of these rows", ctx do
      other = organization!("Other org")
      other_admin = user!(other, :emo_admin)
      s = Portfolio.summary(scope(other_admin, other))

      assert s.rows == []
      assert s.average.participants == 0
      _ = ctx
    end
  end

  defp record_review!(ctx, metric, period, score) do
    Ash.create!(
      ImplementationRating,
      %{metric_id: metric.id, reporting_period_id: period.id, rating_state: :rated, score: score},
      action: :record_review,
      tenant: ctx.org.id,
      actor: ctx.admin
    )
  end
end
