defmodule EmisintWeb.Improvement.PaymentPreviewLiveTest do
  @moduledoc """
  The "Current ratings preview" on `/school-goals`: default period, both
  checkpoints, no fallback to another period, partial coverage, missing
  terms, read-only behavior, the unchanged formal-review view, and access.
  Values come from the workbook's Sum '26 ratings (Goals Dashboard!G:H).
  """
  use EmisintWeb.ConnCase, async: true

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.Improvement.{ImplementationRating, PaymentEstimate, Seeds}

  @participants ~w(fort-yates-ms cannon-ball-elementary oberon-elementary warwick-public-school-district mandaree-public-school-district dunseith-public-school-district drayton-public-school-district valley-middle-school)

  setup do
    org =
      seeded_organization!(
        name: "ND First preview",
        schools: Seeds.available_schools(),
        workbook_ratings?: true
      )

    %{org: org, admin: user!(org, :emo_admin)}
  end

  defp counts(org) do
    for resource <- [ImplementationRating, PaymentEstimate],
        do: length(Ash.read!(resource, tenant: org.id, authorize?: false))
  end

  test "default: Sum '26, 18-month weights, one row per participant", %{conn: conn, admin: admin} do
    {:ok, view, html} = live(log_in(conn, admin), "/school-goals")

    assert has_element?(view, "#portfolio-preview", "Estimated payment based on current ratings.")

    assert has_element?(
             view,
             "#preview-disclaimer",
             "Preview only. Final payment depends on formal review."
           )

    assert has_element?(
             view,
             ~s(#payment-view-preview[aria-selected="true"]),
             "Current ratings preview"
           )

    assert has_element?(view, "#payment-view-formal", "Formal review")
    assert has_element?(view, ~s(#preview-period option[selected][value="sum_26"]))
    assert has_element?(view, "#preview-weights", "Systems 70% · Student Outcomes 30%")

    # Eight participants, each once; no building or Solen High School row.
    rows = Regex.scan(~r/id="preview-row-([a-z0-9-]+)"/, html) |> Enum.map(&List.last/1)
    assert Enum.sort(rows) == Enum.sort(@participants)
    refute html =~ "preview-row-solen-high-school"
    refute html =~ "preview-row-drayton-elementary"

    # Fort Yates: 1.375 × 70% + 1.6 × 30% = 1.4425; the workbook's $70,000 × 1.4425 ÷ 3.
    assert has_element?(view, "#preview-fort-yates-ms-systems", "1.38")
    assert has_element?(view, "#preview-fort-yates-ms-outcomes", "1.6")

    assert has_element?(
             view,
             "#preview-fort-yates-ms-coverage",
             "18 of 18 applicable metrics rated"
           )

    assert has_element?(view, "#preview-fort-yates-ms-weighted", "1.44")
    assert has_element?(view, "#preview-fort-yates-ms-payment", "$33,658.33")

    # Every participant uses the workbook's 18-month $70,000 (Performance-Based
    # Payment rows 4–11; "Solen" is Cannon Ball). Weighted ÷ 3 × $70,000:
    for {slug, amount} <- [
          {"cannon-ball-elementary", "$36,328.21"},
          {"oberon-elementary", "$40,638.89"},
          {"warwick-public-school-district", "$45,500.00"},
          {"mandaree-public-school-district", "$53,666.67"},
          {"drayton-public-school-district", "$42,222.22"},
          {"valley-middle-school", "$47,308.33"}
        ] do
      assert has_element?(view, "#preview-#{slug}-payment", amount), slug
    end

    for slug <- @participants do
      assert has_element?(view, "#preview-#{slug}-provisional", "Provisional payment terms")
      refute has_element?(view, "#preview-#{slug}-payment", "Payment terms not configured")
    end

    # Dunseith: G5-M3 (Systems) is explicitly N/A in the workbook (Dunseith
    # Goals!F27). It is left out of the average and the count, so all 15
    # applicable metrics are rated and the estimate calculates:
    # Systems 13 ÷ 6, Outcomes 17 ÷ 9; 2.1667 × 0.7 + 1.8889 × 0.3 = 2.0833;
    # $70,000 × 2.0833 ÷ 3 = $48,611.11.
    assert has_element?(
             view,
             "#preview-dunseith-public-school-district-payment",
             "$48,611.11"
           )

    assert has_element?(view, "#preview-dunseith-public-school-district-systems", "2.17")
    assert has_element?(view, "#preview-row-dunseith-public-school-district", "1 N/A")
    refute has_element?(view, "#preview-row-dunseith-public-school-district", "6/7")

    assert has_element?(
             view,
             "#preview-dunseith-public-school-district-coverage",
             "15 of 15 applicable metrics rated"
           )

    assert has_element?(
             view,
             "#preview-dunseith-public-school-district-coverage",
             "1 N/A excluded"
           )

    refute has_element?(view, "#preview-dunseith-public-school-district-weighted", "partial")
  end

  test "36-month weights through the selector", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in(conn, admin), "/school-goals")

    view |> form("#preview-form", %{pay_period: "sum_26", pay_ref: "36m"}) |> render_change()
    assert_patch(view, "/school-goals?pay=preview&pay_period=sum_26&pay_ref=36m")

    assert has_element?(view, "#preview-weights", "Systems 30% · Student Outcomes 70%")
    # 1.375 × 30% + 1.6 × 70% = 1.5325: the score is shown; no source sets a
    # 36-month allocation, so no amount (the $35,000 split is withdrawn).
    assert has_element?(view, "#preview-fort-yates-ms-weighted", "1.53")

    for slug <- @participants -- ["dunseith-public-school-district"] do
      assert has_element?(
               view,
               "#preview-#{slug}-payment",
               "Payment allocation needs confirmation"
             )

      refute has_element?(view, "#preview-#{slug}-payment", "$")
      refute has_element?(view, "#preview-#{slug}-provisional")
    end
  end

  test "a period without ratings never falls back to another period", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in(conn, admin), "/school-goals?pay_period=fal_26")

    assert has_element?(
             view,
             ~s(#preview-period option[selected][value="fal_26"]),
             "no ratings yet"
           )

    for slug <- @participants do
      assert has_element?(view, "#preview-#{slug}-coverage", "No ratings recorded for Fal '26")
      assert has_element?(view, "#preview-#{slug}-systems[data-missing]", "No scored ratings")
      assert has_element?(view, "#preview-#{slug}-weighted", "Needs both averages")
    end

    assert has_element?(
             view,
             "#preview-fort-yates-ms-payment",
             "Withheld: 18 of 18 applicable ratings not recorded"
           )
  end

  test "read-only, and the formal review view is unchanged", %{conn: conn, admin: admin, org: org} do
    before = counts(org)

    {:ok, view, _html} = live(log_in(conn, admin), "/school-goals")
    view |> form("#preview-form", %{pay_period: "spr_26", pay_ref: "36m"}) |> render_change()
    view |> form("#preview-form", %{pay_period: "sum_26", pay_ref: "18m"}) |> render_change()

    view |> element("#payment-view-formal") |> render_click()
    assert_patch(view, "/school-goals?pay=formal&pay_period=sum_26&pay_ref=18m")

    # The formal table still uses formal review ratings only: none are recorded,
    # so the preview's amount doesn't appear there.
    refute has_element?(view, "#portfolio-preview")

    assert has_element?(
             view,
             "#portfolio-payment",
             "Performance Based Payments (18-month review)"
           )

    assert has_element?(view, "#fort-yates-ms-estimate", "Awaiting review")
    refute render(view) =~ "$33,658.33"

    assert counts(org) == before
  end

  test "access: a single-school viewer sees only that participant; another org sees none", %{
    conn: conn,
    org: org
  } do
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org, "fort-yates-ms"), :viewer, org)

    {:ok, view, html} = live(log_in(conn, viewer), "/school-goals")

    assert Regex.scan(~r/id="preview-row-([a-z0-9-]+)"/, html) |> Enum.map(&List.last/1) == [
             "fort-yates-ms"
           ]

    assert has_element?(view, "#preview-fort-yates-ms-payment", "$33,658.33")

    other = organization!("Other org")
    {:ok, other_view, _html} = live(log_in(conn, user!(other, :emo_admin)), "/school-goals")
    refute has_element?(other_view, "#portfolio-preview")
    assert has_element?(other_view, "#no-schools")
  end
end
