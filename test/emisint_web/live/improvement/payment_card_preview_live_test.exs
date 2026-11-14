defmodule EmisintWeb.Improvement.PaymentCardPreviewLiveTest do
  @moduledoc """
  The payment summary card on the eight ND First participant pages
  (November 13, 2026): the current-ratings preview (`PaymentPreview`) for the
  page's selected seasonal period at the 18-month checkpoint, matching the
  portfolio preview; formal-review status, the calculation and the
  unresolved 36-month allocation behind "Details", which opens the collapsed
  payment section. Buildings have no payment card. Viewing writes nothing.
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.{
    ImplementationRating,
    PaymentEstimate,
    PaymentPreview,
    Pilot,
    Portfolio,
    Seeds
  }

  setup %{conn: conn} do
    org =
      seeded_organization!(
        name: "Payment card preview",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    admin = user!(org, :emo_admin)

    %{
      org: org,
      conn: log_in(conn, admin),
      scope: %Emisint.Scope{current_user: admin, current_tenant: org.id}
    }
  end

  defp portfolio_preview(scope, period),
    do: scope |> Portfolio.summary() |> PaymentPreview.build(period, :review_18m)

  defp portfolio_row(preview, slug), do: Enum.find(preview.rows, &(&1.slug == slug))

  test "every participant's card matches the portfolio preview for each seasonal period", %{
    conn: conn,
    scope: scope
  } do
    slugs = Enum.map(Pilot.roster(), & &1.slug)
    assert length(slugs) == 8

    for period <- ~w(spr_26 sum_26 fal_26) do
      preview = portfolio_preview(scope, period)

      for slug <- slugs do
        row = portfolio_row(preview, slug)
        assert row.status == :loaded, "#{slug} #{period}"
        {_tone, text} = PaymentPreview.headline(row)

        {:ok, view, _html} = live(conn, "/school-goals/#{slug}?period=#{period}")

        assert has_element?(view, "#payment-card-headline", text), "#{slug} #{period}: #{text}"

        assert has_element?(
                 view,
                 "#payment-card-basis",
                 "#{row.period.label} ratings · 18-month checkpoint (Systems 70% / Student Outcomes 30%)"
               )

        assert has_element?(
                 view,
                 "#payment-card-note",
                 "Preview only; final payment depends on formal review."
               )

        assert has_element?(view, "#payment-card-terms", "Provisional terms")
        assert has_element?(view, "#payment-details-link", "Details")
      end
    end
  end

  test "Dunseith: the workbook N/A is excluded on the card, as on the portfolio", %{
    conn: conn,
    scope: scope
  } do
    row = portfolio_row(portfolio_preview(scope, "sum_26"), "dunseith-public-school-district")
    assert PaymentPreview.payment_text(row) == {:amount, "$48,611.11"}

    {:ok, view, _html} = live(conn, "/school-goals/dunseith-public-school-district?period=sum_26")

    assert has_element?(view, "#payment-card-headline", "Estimated payment: $48,611.11")

    assert has_element?(
             view,
             "#payment-preview-review_18m-payment",
             "15 of 15 applicable metrics rated · 1 N/A excluded"
           )

    # 36-month: the weighted score is shown; its allocation is unresolved.
    assert has_element?(
             view,
             "#payment-preview-review_36m-payment",
             "Payment allocation needs confirmation"
           )
  end

  test "changing the period updates the card and never substitutes another period", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, "/school-goals/fort-yates-ms?period=sum_26")
    sum = portfolio_row(portfolio_preview(scope, "sum_26"), "fort-yates-ms")
    assert has_element?(view, "#payment-card-headline", elem(PaymentPreview.headline(sum), 1))

    # Fal '26 has no ratings: withheld for that period, not Sum '26's figure.
    view |> form("#period-select", %{period: "fal_26"}) |> render_change()
    assert has_element?(view, "#payment-card-basis", "Fal '26 ratings")

    assert has_element?(
             view,
             ~s(#payment-card-headline[data-tone="withheld"]),
             "Withheld: 18 of 18 applicable ratings not recorded"
           )

    # A review period isn't a seasonal rating period: the card says so.
    view |> form("#period-select", %{period: "review_18m"}) |> render_change()

    assert has_element?(
             view,
             "#payment-card-headline",
             "18-Month Review is a formal review period"
           )

    refute has_element?(view, "#payment-card-headline", "$")
  end

  test "Details opens the collapsed payment section, which holds the formal review", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/school-goals/fort-yates-ms?period=sum_26")

    assert has_element?(view, ~s(#payment-toggle[aria-expanded="false"]))
    assert has_element?(view, "#payment-body[hidden]")
    assert has_element?(view, "#payment-summary", "Sum '26 preview")
    assert has_element?(view, "#payment-summary", "Formal review: Awaiting review")

    assert has_element?(
             view,
             "#payment-summary",
             "36-month review payment allocation needs confirmation"
           )

    view |> element("#payment-details-link") |> render_click()
    assert_patch(view, "/school-goals/fort-yates-ms?open=state%2Cpayment&period=sum_26")
    assert_push_event(view, "scroll-to", %{id: "payment"})

    assert has_element?(view, ~s(#payment-toggle[aria-expanded="true"]))
    refute has_element?(view, "#payment-body[hidden]")
    assert has_element?(view, "#payment-body #payment-preview-table")
    assert has_element?(view, "#payment-body #payment-formal-heading", "Formal review estimates")
    assert has_element?(view, "#payment-body #payment-combined-text", "Awaiting review")
    assert has_element?(view, "#payment-body #payment-review_36m", "Needs confirmation")
    # Other sections keep their state.
    assert has_element?(view, ~s(#state-results-toggle[aria-expanded="true"]))
    assert has_element?(view, ~s(#goals-toggle[aria-expanded="false"]))

    # Clicking Details again keeps it open; "Jump to" does the same.
    view |> element("#jump-payment") |> render_click()
    assert has_element?(view, ~s(#payment-toggle[aria-expanded="true"]))
  end

  test "the PDF separates the selected-period preview from formal-review estimates", %{
    scope: scope
  } do
    alias Emisint.Reports.School.NdFirstSchoolPdf

    slug = "dunseith-public-school-district"
    {:ok, data, _name} = NdFirstSchoolPdf.build(scope, slug, %{"period" => "sum_26"})
    p = data.payment.preview

    assert p.title == "Current-ratings preview · Sum '26 ratings"
    assert p.headline == "Estimated payment: $48,611.11"
    assert p.tone == "amount"
    assert p.terms_label == "Provisional terms"
    assert p.note == "Preview only; final payment depends on formal review."
    assert p.reason == ""
    assert [r18, r36] = p.rows
    assert r18.payment == "$48,611.11 (15 of 15 applicable metrics rated · 1 N/A excluded)"
    assert r36.payment =~ "Payment allocation needs confirmation"
    # The formal review is reported separately and unchanged.
    assert data.payment.combined =~ "Awaiting review"

    # The same figure as the page and the portfolio.
    row = portfolio_row(portfolio_preview(scope, "sum_26"), slug)
    assert p.headline == elem(PaymentPreview.headline(row), 1)

    assert {:ok, "%PDF" <> _, _} = NdFirstSchoolPdf.generate(scope, slug, %{"period" => "sum_26"})

    # A review period: no preview figure, the reason instead.
    {:ok, data, _name} = NdFirstSchoolPdf.build(scope, slug, %{"period" => "review_18m"})
    assert data.payment.preview.rows == []
    assert data.payment.preview.reason =~ "is a formal review period"

    assert {:ok, "%PDF" <> _, _} =
             NdFirstSchoolPdf.generate(scope, slug, %{"period" => "review_18m"})
  end

  test "buildings have no payment card or payment section", %{conn: conn} do
    for slug <- ~w(drayton-high-school solen-high-school warwick-middle-school) do
      {:ok, view, _html} = live(conn, "/school-goals/#{slug}")
      refute has_element?(view, "#payment-card"), slug
      refute has_element?(view, "#payment"), slug
      refute has_element?(view, "#jump-payment"), slug
    end
  end

  test "viewing and changing periods writes no rating, review or payment record", %{
    conn: conn,
    org: org
  } do
    counts = fn ->
      for r <- [ImplementationRating, PaymentEstimate],
          do: r |> Ash.read!(tenant: org.id, authorize?: false) |> length()
    end

    before = counts.()

    for slug <- Enum.map(Pilot.roster(), & &1.slug) do
      {:ok, view, _html} = live(conn, "/school-goals/#{slug}?period=sum_26")
      view |> form("#period-select", %{period: "spr_26"}) |> render_change()
      view |> element("#payment-details-link") |> render_click()
    end

    assert counts.() == before
  end
end
