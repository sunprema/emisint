defmodule EmisintWeb.Admin.NdInsightsImportLiveTest do
  use EmisintWeb.ConnCase, async: true

  import Emisint.NdInsightsFixtures

  import Emisint.ImprovementFixtures
  import Phoenix.LiveViewTest

  alias Emisint.NdInsights.StateResult

  @fixtures Path.expand("../../../fixtures/nd_insights", __DIR__)
  @performance "Insights-AssessmentPerformance-CSV-2024-2025-v20251113.csv"
  @page "/admin/import/nd-insights"

  setup do
    org = seeded_organization!(name: "ND Import Org")
    %{org: org, admin: user!(org, :system_admin)}
  end

  defp upload(view, name, content) do
    input =
      file_input(view, "#nd-upload-form", :csv, [
        %{name: name, content: content, type: "text/csv"}
      ])

    render_upload(input, name)
    render_async(view, 10_000)
  end

  defp upload_fixture(view, name \\ @performance),
    do: upload(view, name, File.read!(Path.join(@fixtures, @performance)))

  # The Fort Yates fixture rows copied as a synthetic school (TEST000099), a
  # registered school that is not in the pilot.
  defp non_pilot_rows do
    @fixtures
    |> Path.join(@performance)
    |> File.read!()
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.filter(&(&1 =~ "4300429212"))
    |> Enum.map(
      &String.replace(
        &1,
        "Fort Yates Middle School,4300429212",
        "Synthetic Non-Pilot School,TEST000099"
      )
    )
  end

  defp fixture_header,
    do: @fixtures |> Path.join(@performance) |> File.read!() |> String.split(~r/\r?\n/) |> hd()

  # A statewide-style file with Fort Yates and synthetic non-pilot rows.
  defp mixed_content do
    String.trim_trailing(File.read!(Path.join(@fixtures, @performance))) <>
      "\n" <> Enum.join(non_pilot_rows(), "\n") <> "\n"
  end

  # A file with no Fort Yates rows.
  defp non_pilot_only_content, do: Enum.join([fixture_header() | non_pilot_rows()], "\n") <> "\n"

  test "only system admins can open the page", %{conn: conn, org: org} do
    for role <- [:emo_admin, :school_leader] do
      assert {:error, {:live_redirect, %{to: "/school-goals", flash: flash}}} =
               live(log_in(conn, user!(org, role)), @page)

      assert flash["error"] =~ "Only system admins"
    end
  end

  test "upload → preview → explicit selection → import, recorded and refreshed", %{
    conn: conn,
    org: org,
    admin: admin
  } do
    # A viewer has the dashboard open before the import.
    viewer = user!(org, :school_leader)
    membership!(viewer, school!(org), :viewer, org)
    {:ok, dashboard, _} = live(log_in(conn, viewer), "/school-goals/fort-yates-ms")
    assert has_element?(dashboard, "#state-results-empty")

    {:ok, view, _html} = live(log_in(conn, admin), @page)
    assert has_element?(view, "#nd-drop-zone[phx-drop-target]")

    upload_fixture(view)

    assert has_element?(view, "#nd-preview-dataset", "Assessment Performance")
    assert has_element?(view, "#nd-preview-years", "2024-2025")
    assert has_element?(view, "#nd-school-4300429212", "Fort Yates Middle School")
    assert has_element?(view, "#nd-school-4300429212", "144")
    # Nothing is selected or written until the admin chooses.
    assert has_element?(view, "#nd-import-button[disabled]")
    assert Ash.read!(StateResult, authorize?: false) == []

    view |> form("#nd-select-form", %{institution_ids: ["4300429212"]}) |> render_change()
    view |> form("#nd-select-form") |> render_submit()
    render_async(view, 10_000)

    assert has_element?(view, "#nd-result", "144 new")
    assert length(Ash.read!(StateResult, authorize?: false)) == 144
    assert has_element?(view, "#nd-import-runs", @performance)
    assert has_element?(view, "#nd-import-runs", "Imported")
    assert has_element?(view, "#nd-import-runs", to_string(admin.email))

    # The open dashboard refreshed without a reload.
    assert render(dashboard) =~ "Official state results were updated"
    refute has_element?(dashboard, "#state-results-empty")
    assert has_element?(dashboard, "#achievement-reading-all-grades", "30%–39%")
  end

  test "only pilot schools are offered and imported, even when others are registered", %{
    conn: conn,
    admin: admin
  } do
    # A synthetic school is registered but is not
    # a pilot school; this file carries rows for both schools.
    "Expansion Org" |> organization!() |> non_pilot_school!()
    content = mixed_content()

    # The reusable preview sees both registered schools when not restricted.
    path = Path.join(System.tmp_dir!(), "nd-pilot-#{System.unique_integer([:positive])}.csv")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    {:ok, unrestricted} = Emisint.NdInsights.UploadPreview.build(path, @performance)

    assert unrestricted.schools |> Enum.map(& &1.institution_id) |> Enum.sort() ==
             ~w(4300429212 TEST000099)

    {:ok, view, _html} = live(log_in(conn, admin), @page)
    upload(view, @performance, content)

    assert has_element?(view, "#nd-pilot-scope", "only the ND First pilot schools")
    assert has_element?(view, "#nd-school-4300429212")
    refute has_element?(view, "#nd-school-TEST000099")

    # A forged selection including the non-pilot school imports Fort Yates only.
    render_change(view, "select", %{"institution_ids" => ["4300429212", "TEST000099"]})
    render_submit(view, "import", %{})
    render_async(view, 10_000)

    assert has_element?(view, "#nd-result", "144 new")

    assert StateResult
           |> Ash.read!(authorize?: false)
           |> Enum.map(& &1.institution_id)
           |> Enum.uniq() ==
             ["4300429212"]
  end

  test "school IDs not in the server-side preview are ignored", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in(conn, admin), @page)
    upload_fixture(view)

    render_change(view, "select", %{"institution_ids" => ["9999999999"]})
    assert has_element?(view, "#nd-import-button[disabled]")

    render_submit(view, "import", %{})
    assert render(view) =~ "Select at least one school"
    assert Ash.read!(StateResult, authorize?: false) == []
  end

  test "a repeated upload creates nothing", %{conn: conn, admin: admin} do
    import_insights!([Path.join(@fixtures, @performance)],
      institution_ids: ["4300429212"]
    )

    {:ok, view, _html} = live(log_in(conn, admin), @page)
    upload_fixture(view)

    assert has_element?(view, "#nd-already-imported")
    assert has_element?(view, "#nd-school-4300429212 td:last-child", "144")
    assert has_element?(view, "#nd-preview", "0 of 144 measures for the schools found are new")

    view |> form("#nd-select-form", %{institution_ids: ["4300429212"]}) |> render_change()
    view |> form("#nd-select-form") |> render_submit()
    render_async(view, 10_000)

    assert has_element?(view, "#nd-result", "No changes from #{@performance}")
    assert has_element?(view, "#nd-result", "0 new · 144 already stored")
    assert has_element?(view, "#nd-import-runs", "No changes")
    assert length(Ash.read!(StateResult, authorize?: false)) == 144
  end

  test "a revised publication must be confirmed before importing", %{conn: conn, admin: admin} do
    import_insights!([Path.join(@fixtures, @performance)],
      institution_ids: ["4300429212"]
    )

    revised = String.replace(@performance, "v20251113", "v20260101")
    {:ok, view, _html} = live(log_in(conn, admin), @page)
    upload_fixture(view, revised)

    assert has_element?(view, "#nd-revision", "20251113")

    view |> form("#nd-select-form", %{institution_ids: ["4300429212"]}) |> render_change()
    assert has_element?(view, "#nd-import-button[disabled]")
    render_submit(view, "import", %{})
    assert render(view) =~ "Confirm the revised publication"
    assert length(Ash.read!(StateResult, authorize?: false)) == 144

    view
    |> form("#nd-select-form", %{institution_ids: ["4300429212"], confirm_revision: "true"})
    |> render_change()

    view |> form("#nd-select-form") |> render_submit()
    render_async(view, 10_000)

    assert has_element?(view, "#nd-result", "144 new")
    assert length(Ash.read!(StateResult, authorize?: false)) == 288
  end

  test "unreadable or renamed files show an actionable error", %{conn: conn, admin: admin} do
    {:ok, view, _html} = live(log_in(conn, admin), @page)

    upload(view, "notes.csv", "A,B\n1,2\n")
    assert has_element?(view, "#nd-preview-error", "Expected an ND Insights")

    engagement =
      File.read!(Path.join(@fixtures, "Insights-Engagement-Emotional-All-CSV-v20251202.csv"))

    upload(view, "engagement.csv", engagement)
    assert has_element?(view, "#nd-preview-error", "keep the original name")
  end

  describe "from the Fort Yates dashboard (/school-goals/fort-yates-ms/import)" do
    @school_page "/school-goals/fort-yates-ms/import"

    test "is for system admins only", %{conn: conn, org: org} do
      leader = user!(org, :school_leader)
      membership!(leader, school!(org), :contributor, org)

      for user <- [user!(org, :emo_admin), leader] do
        assert {:error, {:live_redirect, %{to: "/school-goals", flash: flash}}} =
                 live(log_in(conn, user), @school_page)

        assert flash["error"] =~ "Only system admins"
      end
    end

    test "only opens for a pilot school the admin can read", %{conn: conn, admin: admin} do
      "Other Org" |> organization!() |> non_pilot_school!()

      for page <-
            ~w(/school-goals/synthetic-non-pilot-school/import /school-goals/no-such-school/import) do
        assert {:error, {:live_redirect, %{to: "/school-goals", flash: flash}}} =
                 live(log_in(conn, admin), page)

        assert flash["error"] =~ "can't be imported for that school"
      end
    end

    test "locks the school, ignores other IDs and links back to the refreshed dashboard", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      "Other Org" |> organization!() |> non_pilot_school!()
      viewer = user!(org, :school_leader)
      membership!(viewer, school!(org), :viewer, org)
      {:ok, dashboard, _} = live(log_in(conn, viewer), "/school-goals/fort-yates-ms")
      assert has_element?(dashboard, "#state-results-empty")

      {:ok, view, _html} = live(log_in(conn, admin), @school_page)

      assert has_element?(
               view,
               ~s(#nd-back-to-school[href="/school-goals/fort-yates-ms"]),
               "Back to Fort Yates"
             )

      assert has_element?(view, "#nd-locked-school", "4300429212")

      upload(view, @performance, mixed_content())

      # Fort Yates is selected and locked; the non-pilot school's rows are not offered.
      assert has_element?(view, "#nd-pilot-scope", "Locked to Fort Yates Middle School")
      assert has_element?(view, "#nd-school-4300429212 input[checked][disabled]")
      refute has_element?(view, "#nd-school-TEST000099")
      refute has_element?(view, "#nd-import-button[disabled]")

      # Forged selections can neither drop nor swap the locked school.
      render_change(view, "select", %{"institution_ids" => ["TEST000099"]})
      assert has_element?(view, "#nd-school-4300429212 input[checked]")
      render_submit(view, "import", %{"institution_ids" => ["TEST000099"]})
      render_async(view, 10_000)

      assert has_element?(view, "#nd-result", "144 new")

      assert has_element?(
               view,
               ~s(#nd-view-dashboard[href="/school-goals/fort-yates-ms"]),
               "View updated dashboard"
             )

      assert has_element?(view, "#nd-import-runs", "Recent imports for Fort Yates")

      assert StateResult
             |> Ash.read!(authorize?: false)
             |> Enum.map(& &1.institution_id)
             |> Enum.uniq() ==
               ["4300429212"]

      # The open dashboard shows the imported results.
      assert render(dashboard) =~ "Official state results were updated"
      assert has_element?(dashboard, "#achievement-reading-all-grades", "30%–39%")

      # Re-uploading the same file creates nothing.
      upload(view, @performance, mixed_content())
      assert has_element?(view, "#nd-already-imported")
      render_submit(view, "import", %{})
      render_async(view, 10_000)
      assert has_element?(view, "#nd-result", "No changes from")
      assert has_element?(view, "#nd-result", "0 new · 144 already stored")
      assert length(Ash.read!(StateResult, authorize?: false)) == 144
    end

    test "a file without the school's records says so and changes nothing", %{
      conn: conn,
      admin: admin
    } do
      "Other Org" |> organization!() |> non_pilot_school!()
      {:ok, view, _html} = live(log_in(conn, admin), @school_page)
      upload(view, @performance, non_pilot_only_content())

      assert has_element?(
               view,
               "#nd-no-schools",
               "This file has no records for Fort Yates Middle School"
             )

      assert has_element?(view, "#nd-import-button[disabled]")

      render_change(view, "select", %{"institution_ids" => ["TEST000099", "4300429212"]})
      render_submit(view, "import", %{"institution_ids" => ["TEST000099", "4300429212"]})
      render_async(view, 10_000)

      assert render(view) =~ "Select at least one school"
      refute has_element?(view, "#nd-result")
      assert Ash.read!(StateResult, authorize?: false) == []
    end
  end

  describe "North Dakota benchmark rows" do
    @with_state Path.join("with_state", @performance)

    defp with_state_content, do: File.read!(Path.join(@fixtures, @with_state))

    test "import with the locked school, are summarized separately and never duplicated", %{
      conn: conn,
      org: org,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in(conn, admin), "/school-goals/fort-yates-ms/import")
      upload(view, @performance, with_state_content())

      assert has_element?(view, "#nd-benchmark", "North Dakota state benchmark")
      assert has_element?(view, "#nd-benchmark", "160 measures · 160 new")
      # The state is not offered as a school.
      refute has_element?(view, "#nd-school-99999")

      render_submit(view, "import", %{})
      render_async(view, 10_000)

      assert has_element?(view, "#nd-result-split", "School 4300429212: 144 new")

      assert has_element?(
               view,
               "#nd-result-split",
               "North Dakota state benchmark (99999): 160 new"
             )

      assert has_element?(view, "#nd-import-runs", "99999 (ND state benchmark)")

      # Repeat: nothing new for either.
      upload(view, @performance, with_state_content())
      assert has_element?(view, "#nd-benchmark", "160 measures · 0 new · 160 already stored")
      render_submit(view, "import", %{})
      render_async(view, 10_000)

      assert has_element?(
               view,
               "#nd-result-split",
               "North Dakota state benchmark (99999): 0 new · 160 already stored"
             )

      assert length(Ash.read!(StateResult, authorize?: false)) == 304

      # No school record (in any organization) or ND First tile exists for the state.
      assert %{rows: [[0]]} =
               Emisint.Repo.query!("select count(*) from schools where state_entity_id = $1", [
                 "99999"
               ])

      viewer = user!(org, :school_leader)
      membership!(viewer, school!(org), :viewer, org)
      {:ok, landing, _} = live(log_in(conn, viewer), "/school-goals")
      assert has_element?(landing, "#school-fort-yates-ms")
      refute has_element?(landing, "[id^=school-]:not(#school-fort-yates-ms)")
    end

    test "can be added from a file already imported for the school", %{conn: conn, admin: admin} do
      import_insights!([Path.join(@fixtures, @performance)],
        institution_ids: ["4300429212"]
      )

      {:ok, view, _html} = live(log_in(conn, admin), "/school-goals/fort-yates-ms/import")
      upload(view, @performance, with_state_content())
      render_submit(view, "import", %{})
      render_async(view, 10_000)

      assert has_element?(
               view,
               "#nd-result-split",
               "School 4300429212: 0 new · 144 already stored"
             )

      assert has_element?(
               view,
               "#nd-result-split",
               "North Dakota state benchmark (99999): 160 new"
             )
    end

    test "a school-only file still imports and explains the missing benchmark", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in(conn, admin), "/school-goals/fort-yates-ms/import")
      upload_fixture(view)

      assert has_element?(view, "#nd-benchmark", "no North Dakota statewide rows")
      render_submit(view, "import", %{})
      render_async(view, 10_000)

      assert has_element?(view, "#nd-result", "144 new")

      assert StateResult
             |> Ash.read!(authorize?: false)
             |> Enum.map(& &1.institution_id)
             |> Enum.uniq() == ["4300429212"]
    end

    test "the state rows can't be imported on their own or selected as a school", %{
      conn: conn,
      admin: admin
    } do
      {:ok, view, _html} = live(log_in(conn, admin), @page)
      upload(view, @performance, with_state_content())

      render_change(view, "select", %{"institution_ids" => ["99999"]})
      assert has_element?(view, "#nd-import-button[disabled]")
      render_submit(view, "import", %{"institution_ids" => ["99999"]})

      assert render(view) =~ "Select at least one school"
      assert Ash.read!(StateResult, authorize?: false) == []
    end
  end
end
