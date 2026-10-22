defmodule Emisint.Improvement.EntriesTest do
  use Emisint.DataCase, async: true

  import Emisint.ImprovementFixtures

  alias Emisint.Improvement.{ActualResult, ImplementationRating}

  setup do
    org = seeded_organization!()

    %{
      org: org,
      contributor: contributor!(org),
      metric: metric!(org, "G2-M1"),
      period: period!(org, "fal_26")
    }
  end

  defp record_actual(ctx, attrs) do
    base = %{
      metric_id: ctx.metric.id,
      reporting_period_id: ctx.period.id,
      value_state: :exact,
      value: Decimal.new("0.24"),
      measurement_date: ~D[2026-10-15]
    }

    Ash.create(ActualResult, Map.merge(base, attrs),
      action: :record,
      tenant: ctx.org.id,
      actor: ctx.contributor
    )
  end

  defp record_rating(ctx, attrs) do
    base = %{
      metric_id: ctx.metric.id,
      reporting_period_id: ctx.period.id,
      rating_state: :rated,
      score: 2
    }

    Ash.create(ImplementationRating, Map.merge(base, attrs),
      action: :record,
      tenant: ctx.org.id,
      actor: ctx.contributor
    )
  end

  defp correct(resource, ctx, corrected, attrs) do
    Ash.create(
      resource,
      Map.merge(%{corrects_id: corrected.id, correction_reason: "Data entry error"}, attrs),
      action: :correct,
      tenant: ctx.org.id,
      actor: ctx.contributor
    )
  end

  defp current(resource, ctx) do
    Ash.read!(resource, action: :current, tenant: ctx.org.id, authorize?: false)
  end

  describe "server-side provenance" do
    test "author, recorder and timestamp come from the server", ctx do
      before = DateTime.utc_now()
      assert {:ok, result} = record_actual(ctx, %{})

      assert result.kind == :observation
      assert result.source == :manual
      assert result.author_id == ctx.contributor.id
      assert result.recorded_by_id == ctx.contributor.id
      assert result.school_id == ctx.metric.school_id
      assert DateTime.compare(result.recorded_at, before) != :lt
    end

    test "clients cannot supply author, recorder, timestamp, kind or school", ctx do
      for {field, value} <- [
            author_id: Ash.UUID.generate(),
            recorded_by_id: Ash.UUID.generate(),
            recorded_at: ~U[2020-01-01 00:00:00Z],
            kind: :correction,
            school_id: Ash.UUID.generate()
          ] do
        assert {:error, error} = record_actual(ctx, %{field => value})
        assert Enum.any?(error.errors, &match?(%Ash.Error.Invalid.NoSuchInput{input: ^field}, &1))
      end
    end

    test "an actor is required for manual entries", ctx do
      assert {:error, error} =
               Ash.create(
                 ActualResult,
                 %{
                   metric_id: ctx.metric.id,
                   reporting_period_id: ctx.period.id,
                   value_state: :exact,
                   value: Decimal.new("0.2"),
                   measurement_date: ~D[2026-10-01]
                 },
                 action: :record,
                 tenant: ctx.org.id,
                 authorize?: false
               )

      assert :author_id in error_fields(error)
    end
  end

  describe "actual result states" do
    test "exact results are normalized to 0–1", ctx do
      assert {:error, error} = record_actual(ctx, %{value: Decimal.new("24")})
      assert :value in error_fields(error)
    end

    test "exact results require a measurement date", ctx do
      assert {:error, error} = record_actual(ctx, %{measurement_date: nil})
      assert :measurement_date in error_fields(error)
    end

    test "ranged results keep low and high, in order", ctx do
      assert {:ok, result} =
               record_actual(ctx, %{
                 value_state: :range,
                 value: nil,
                 range_low: Decimal.new("0.20"),
                 range_high: Decimal.new("0.29")
               })

      assert result.value == nil
      assert Decimal.equal?(result.range_low, "0.20")

      other = period!(ctx.org, "win_27")

      assert {:error, error} =
               record_actual(ctx, %{
                 reporting_period_id: other.id,
                 value_state: :range,
                 value: nil,
                 range_low: Decimal.new("0.4"),
                 range_high: Decimal.new("0.3")
               })

      assert :range_low in error_fields(error)
    end

    test "suppressed results carry no value and keep the source's reason verbatim", ctx do
      assert {:error, _} = record_actual(ctx, %{value_state: :suppressed})

      assert {:ok, result} =
               record_actual(ctx, %{
                 value_state: :suppressed,
                 value: nil,
                 measurement_date: nil,
                 suppression_reason: "Fewer than 10 students tested"
               })

      assert result.suppression_reason == "Fewer than 10 students tested"
    end

    test "unavailable results need an explanation but no made-up value", ctx do
      assert {:error, error} =
               record_actual(ctx, %{value_state: :unavailable, value: nil, measurement_date: nil})

      assert :notes in error_fields(error)

      assert {:ok, result} =
               record_actual(ctx, %{
                 value_state: :unavailable,
                 value: nil,
                 measurement_date: nil,
                 notes: "State results not yet published"
               })

      assert result.value == nil
    end

    test "suppression reasons are rejected on non-suppressed results", ctx do
      assert {:error, error} = record_actual(ctx, %{suppression_reason: "n<10"})
      assert :suppression_reason in error_fields(error)
    end

    test "review periods are not accepted for seasonal entries", ctx do
      review = period!(ctx.org, "review_18m")
      assert {:error, error} = record_actual(ctx, %{reporting_period_id: review.id})
      assert :reporting_period_id in error_fields(error)

      assert {:error, error} = record_rating(ctx, %{reporting_period_id: review.id})
      assert :reporting_period_id in error_fields(error)
    end
  end

  describe "evidence links" do
    test "accepts http(s) links and rejects other schemes", ctx do
      assert {:ok, result} =
               record_actual(ctx, %{
                 evidence_links: [
                   %{url: "https://docs.google.com/document/d/abc", label: "PD notes"}
                 ]
               })

      assert [%{url: "https://docs.google.com/document/d/abc", label: "PD notes"}] =
               result.evidence_links

      for url <- ["javascript:alert(1)", "ftp://example.com/file", "not a url"] do
        assert {:error, _} = record_rating(ctx, %{evidence_links: [%{url: url}]})
      end
    end
  end

  describe "implementation ratings" do
    test "scores are 0–3; N/A and unavailable carry no score", ctx do
      assert {:error, _} = record_rating(ctx, %{score: 4})
      assert {:error, error} = record_rating(ctx, %{score: nil})
      assert :score in error_fields(error)
      assert {:error, _} = record_rating(ctx, %{rating_state: :not_applicable, score: 2})
      assert {:error, error} = record_rating(ctx, %{rating_state: :unavailable, score: nil})
      assert :notes in error_fields(error)

      assert {:ok, rating} = record_rating(ctx, %{rating_state: :not_applicable, score: nil})
      assert rating.score == nil
    end

    test "only org admins may run the workbook import action", ctx do
      attrs = %{
        metric_id: ctx.metric.id,
        reporting_period_id: ctx.period.id,
        rating_state: :rated,
        score: 1,
        source_ref: "Ft Yates Goals!G13",
        source_last_updated_on: ~D[2026-08-18]
      }

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(ImplementationRating, attrs,
                 action: :import_workbook,
                 tenant: ctx.org.id,
                 actor: ctx.contributor
               )

      admin = user!(ctx.org, :emo_admin)

      assert {:ok, rating} =
               Ash.create(ImplementationRating, attrs,
                 action: :import_workbook,
                 tenant: ctx.org.id,
                 actor: admin
               )

      assert rating.author_id == nil
      assert rating.recorded_by_id == admin.id
    end
  end

  describe "observations and corrections" do
    test "a second observation for the same metric and period is rejected", ctx do
      assert {:ok, _} = record_actual(ctx, %{})
      assert {:error, error} = record_actual(ctx, %{value: Decimal.new("0.3")})
      assert Exception.message(error) =~ "submit a correction"
    end

    test "a correction replaces the current entry and preserves the original", ctx do
      {:ok, original} = record_actual(ctx, %{})

      assert {:ok, fixed} =
               correct(ActualResult, ctx, original, %{
                 value_state: :exact,
                 value: Decimal.new("0.26"),
                 measurement_date: ~D[2026-10-15]
               })

      assert fixed.kind == :correction
      assert fixed.corrects_id == original.id
      assert fixed.metric_id == original.metric_id
      assert fixed.reporting_period_id == original.reporting_period_id

      assert [current] = current(ActualResult, ctx)
      assert current.id == fixed.id

      history =
        ActualResult
        |> Ash.Query.for_read(:history, %{metric_id: ctx.metric.id})
        |> Ash.read!(tenant: ctx.org.id, authorize?: false)

      assert Enum.map(history, & &1.id) |> Enum.sort() == Enum.sort([original.id, fixed.id])

      reloaded = Ash.get!(ActualResult, original.id, tenant: ctx.org.id, authorize?: false)
      assert Decimal.equal?(reloaded.value, "0.24")
    end

    test "corrections require a reason", ctx do
      {:ok, original} = record_actual(ctx, %{})

      assert {:error, error} =
               correct(ActualResult, ctx, original, %{
                 correction_reason: nil,
                 value_state: :exact,
                 value: Decimal.new("0.3"),
                 measurement_date: ~D[2026-10-15]
               })

      assert :correction_reason in error_fields(error)
    end

    test "a superseded entry cannot be corrected again (no timestamp winner)", ctx do
      {:ok, original} = record_actual(ctx, %{})
      fields = %{value_state: :exact, value: Decimal.new("0.3"), measurement_date: ~D[2026-10-15]}
      assert {:ok, _first} = correct(ActualResult, ctx, original, fields)

      assert {:error, error} =
               correct(ActualResult, ctx, original, %{fields | value: Decimal.new("0.31")})

      assert :corrects_id in error_fields(error)
      assert length(current(ActualResult, ctx)) == 1
    end

    test "the database rejects two corrections of the same entry", ctx do
      {:ok, original} = record_rating(ctx, %{})

      row = %{
        organization_id: ctx.org.id,
        school_id: original.school_id,
        metric_id: original.metric_id,
        reporting_period_id: original.reporting_period_id,
        kind: :correction,
        corrects_id: original.id,
        rating_state: :rated,
        score: 3,
        source: :manual,
        evidence_links: []
      }

      Ash.Seed.seed!(ImplementationRating, row)
      assert_raise Ash.Error.Invalid, fn -> Ash.Seed.seed!(ImplementationRating, row) end
    end

    test "a correction must match the corrected entry's metric and period", ctx do
      {:ok, original} = record_actual(ctx, %{})
      other_metric = metric!(ctx.org, "G3-M1")

      assert {:error, error} =
               correct(ActualResult, ctx, original, %{
                 metric_id: other_metric.id,
                 value_state: :exact,
                 value: Decimal.new("0.3"),
                 measurement_date: ~D[2026-10-15]
               })

      assert :metric_id in error_fields(error)
    end
  end

  describe "independence of actual results and ratings" do
    test "updating one never hides the other; each keeps its own provenance", ctx do
      other_user = contributor!(ctx.org)

      {:ok, actual} = record_actual(ctx, %{})

      {:ok, rating} =
        Ash.create(
          ImplementationRating,
          %{
            metric_id: ctx.metric.id,
            reporting_period_id: ctx.period.id,
            rating_state: :rated,
            score: 2
          },
          action: :record,
          tenant: ctx.org.id,
          actor: other_user
        )

      # Actual-only correction: rating stays current and unchanged.
      {:ok, fixed_actual} =
        correct(ActualResult, ctx, actual, %{
          value_state: :exact,
          value: Decimal.new("0.25"),
          measurement_date: ~D[2026-10-20]
        })

      assert [%{id: rating_id, score: 2, author_id: rating_author}] =
               current(ImplementationRating, ctx)

      assert rating_id == rating.id
      assert rating_author == other_user.id

      # Rating-only correction: actual stays current and unchanged.
      {:ok, _fixed_rating} =
        correct(ImplementationRating, ctx, rating, %{rating_state: :rated, score: 3})

      assert [current_actual] = current(ActualResult, ctx)
      assert current_actual.id == fixed_actual.id
      assert Decimal.equal?(current_actual.value, "0.25")
      assert current_actual.measurement_date == ~D[2026-10-20]
      assert current_actual.author_id == ctx.contributor.id
    end
  end
end
