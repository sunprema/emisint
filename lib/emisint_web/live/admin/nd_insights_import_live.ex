defmodule EmisintWeb.Admin.NdInsightsImportLive do
  @moduledoc """
  Drag-and-drop upload of official ND Insights CSVs (Assessment Performance,
  Assessment Participation, Growth Rate, Engagement Survey).

  Flow: upload → validated preview (dataset, years, version, schools found by
  verified InstitutionID, errors, revision check) → explicit school selection
  → import. Statewide data is shared by every organization, so like the other
  state-data imports this page is for system admins only; the role is checked
  on mount and again on every event.

  Two entry points share this page:

    * `/admin/import/nd-insights` offers every ND First pilot school
      (`Emisint.Improvement.Pilot`).
    * `/school-goals/:slug/import`, opened from the "Import ND Insights data"
      button on any supported ND First dashboard (every participant, district
      and building record), is locked to that record: only rows published
      under its own InstitutionID are previewed, it is selected
      automatically, and the server ignores any other submitted
      InstitutionID. District and building records have different
      InstitutionIDs, so importing one never imports or changes the other.

  Either way the import is limited to pilot schools on the server; the
  underlying preview and importer accept any verified InstitutionID. A file's
  "State of North Dakota" rows (`Emisint.NdInsights.Benchmark`) are imported
  with the selected school as a comparison benchmark: the server adds them
  only when the preview found them, and never without a selected school.
  """
  use EmisintWeb, :live_view

  alias Emisint.Improvement.{Access, Dashboard, Pilot}
  alias Emisint.NdInsights.{Benchmark, Importer, UploadPreview}

  @max_bytes 40_000_000

  @dataset_labels %{
    assessment_performance: "Assessment Performance (achievement)",
    assessment_participation: "Assessment Participation",
    growth_rate: "Growth Rate",
    engagement_overall: "Engagement Survey — Overall",
    engagement_behavioral: "Engagement Survey — Behavioral",
    engagement_cognitive: "Engagement Survey — Cognitive",
    engagement_emotional: "Engagement Survey — Emotional",
    engagement_participation: "Engagement Survey — Participation"
  }

  @impl true
  def mount(params, session, socket) do
    with true <- system_admin?(socket),
         {:ok, school} <- locked_school(socket, params) do
      socket =
        assign(socket,
          school: school,
          institution: school && Pilot.import_scope(school),
          topic: Importer.topic(session)
        )

      {:ok,
       socket
       |> assign(page_title: page_title(school), staged: nil, preview: nil, preview_error: nil)
       |> assign(selected: MapSet.new(), confirm_revision: false, importing: false, result: nil)
       |> assign(runs: load_runs(socket))
       |> allow_upload(:csv,
         accept: ~w(.csv),
         max_entries: 1,
         max_file_size: @max_bytes,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      false ->
        {:ok,
         socket
         |> put_flash(:error, "Only system admins can import statewide ND Insights data.")
         |> push_navigate(to: ~p"/school-goals")}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "ND Insights data can't be imported for that school.")
         |> push_navigate(to: ~p"/school-goals")}
    end
  end

  # A school's import page is locked to that record, which must be readable
  # and pass the same check as the dashboard's import button.
  defp locked_school(socket, %{"slug" => slug}) do
    with {:ok, school} <- Dashboard.fetch_school(socket.assigns.scope, slug) do
      if Access.can_import_state_results?(socket.assigns.current_user, school),
        do: {:ok, school},
        else: {:error, :not_supported}
    end
  end

  defp locked_school(_socket, _params), do: {:ok, nil}

  defp page_title(nil), do: "ND Insights Import"
  defp page_title(school), do: "ND Insights Import · #{school.name}"

  # InstitutionIDs this page may preview and import.
  defp allowed_ids(%{assigns: %{school: %{state_entity_id: id}}}),
    do: Enum.filter([id], &Pilot.pilot?/1)

  defp allowed_ids(_socket), do: Pilot.institution_ids()

  @impl true
  def terminate(_reason, socket), do: cleanup(socket.assigns[:staged])

  defp system_admin?(socket), do: match?(%{role: :system_admin}, socket.assigns[:current_user])

  # On a school's page, the query keeps only that InstitutionID's runs before
  # taking the 25 most recent, so other schools' newer runs can't crowd them out.
  defp load_runs(%{assigns: %{school: nil, current_user: user}}),
    do: Emisint.NdInsights.list_recent_import_runs!(actor: user)

  defp load_runs(%{assigns: %{school: school, current_user: user}}),
    do: Emisint.NdInsights.list_recent_import_runs_for!(school.state_entity_id, actor: user)

  # Copy the finished upload to a staging file and build the preview.
  defp handle_progress(:csv, entry, socket) do
    if entry.done? and system_admin?(socket) do
      cleanup(socket.assigns.staged)
      ids = allowed_ids(socket)

      staged =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          dir = Path.join(System.tmp_dir!(), "nd-insights-uploads")
          File.mkdir_p!(dir)
          dest = Path.join(dir, "#{Ecto.UUID.generate()}.csv")
          File.cp!(path, dest)
          {:ok, %{path: dest, file_name: entry.client_name}}
        end)

      {:noreply,
       socket
       |> assign(staged: staged, preview: nil, preview_error: nil, result: nil)
       |> assign(selected: MapSet.new(), confirm_revision: false)
       |> start_async(:preview, fn ->
         UploadPreview.build(staged.path, staged.file_name,
           institution_ids: ids,
           benchmark?: true
         )
       end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:preview, {:ok, {:ok, preview}}, socket),
    do: {:noreply, assign(socket, preview: preview, selected: initial_selection(socket, preview))}

  def handle_async(:preview, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, preview_error: reason)}

  def handle_async(:preview, {:exit, reason}, socket),
    do:
      {:noreply,
       assign(socket, preview_error: "The file could not be read (#{inspect(reason)}).")}

  def handle_async(:import, {:ok, {:ok, [report]}}, socket) do
    cleanup(socket.assigns.staged)

    {:noreply,
     socket
     |> assign(
       importing: false,
       result: report,
       staged: nil,
       preview: nil,
       runs: load_runs(socket)
     )
     |> put_flash(flash_kind(report), flash_text(report))}
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket),
    do: {:noreply, socket |> assign(importing: false) |> put_flash(:error, reason)}

  def handle_async(:import, {:exit, reason}, socket),
    do:
      {:noreply,
       socket
       |> assign(importing: false, runs: load_runs(socket))
       |> put_flash(:error, "Import failed: #{inspect(reason)}")}

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("select", params, socket) do
    {:noreply,
     assign(socket,
       selected: selection(socket, params),
       confirm_revision: params["confirm_revision"] == "true"
     )}
  end

  def handle_event("import", _params, socket) do
    %{staged: staged, preview: preview, selected: selected} = socket.assigns

    cond do
      not system_admin?(socket) ->
        {:noreply,
         put_flash(socket, :error, "Only system admins can import statewide ND Insights data.")}

      is_nil(staged) or is_nil(preview) ->
        {:noreply, put_flash(socket, :error, "Upload and preview a file first.")}

      MapSet.size(selected) == 0 ->
        {:noreply, put_flash(socket, :error, "Select at least one school to import.")}

      preview.prior_versions != [] and not socket.assigns.confirm_revision ->
        {:noreply, put_flash(socket, :error, "Confirm the revised publication before importing.")}

      true ->
        allowed = allowed_ids(socket)

        ids =
          Enum.filter(
            MapSet.to_list(selected),
            &(&1 in preview_ids(socket) and &1 in allowed and Pilot.pilot?(&1))
          )

        ids =
          if ids != [] and benchmark_usable?(preview),
            do: ids ++ [Benchmark.state_id()],
            else: ids

        actor = socket.assigns.current_user
        accept = socket.assigns.confirm_revision
        topic = socket.assigns.topic

        {:noreply,
         socket
         |> assign(importing: true)
         |> start_async(:import, fn ->
           Importer.import_files([{staged.path, staged.file_name}],
             institution_ids: ids,
             actor: actor,
             accept_revisions: accept,
             topic: topic
           )
         end)}
    end
  end

  def handle_event("cancel", _params, socket) do
    cleanup(socket.assigns.staged)

    {:noreply,
     assign(socket,
       staged: nil,
       preview: nil,
       preview_error: nil,
       selected: MapSet.new(),
       confirm_revision: false
     )}
  end

  defp preview_ids(%{assigns: %{preview: %{schools: schools}}}),
    do: Enum.map(schools, & &1.institution_id)

  defp preview_ids(_socket), do: []

  defp benchmark_usable?(%{benchmark: %{usable?: true}}), do: true
  defp benchmark_usable?(_preview), do: false

  # A locked school is selected as soon as the preview shows it has records.
  defp initial_selection(%{assigns: %{school: %{}}} = socket, preview) do
    allowed = allowed_ids(socket)

    preview.schools
    |> Enum.map(& &1.institution_id)
    |> Enum.filter(&(&1 in allowed))
    |> MapSet.new()
  end

  defp initial_selection(_socket, _preview), do: MapSet.new()

  # On a locked page the selection can't be changed; submitted IDs are ignored.
  defp selection(%{assigns: %{school: %{}, selected: selected}}, _params), do: selected

  defp selection(socket, params) do
    allowed = preview_ids(socket)

    params
    |> Map.get("institution_ids", [])
    |> List.wrap()
    |> Enum.filter(&(&1 in allowed))
    |> MapSet.new()
  end

  defp cleanup(%{path: path}), do: File.rm(path)
  defp cleanup(_), do: :ok

  defp flash_kind(%{error: _}), do: :error
  defp flash_kind(_), do: :info

  defp flash_text(%{error: error}), do: error

  defp flash_text(report),
    do:
      "Imported #{report.file}: #{report.created} new, #{report.unchanged} already stored, " <>
        "#{report.conflict_count} conflicts."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, labels: @dataset_labels, max_mb: div(@max_bytes, 1_000_000))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="p-4 md:p-6 max-w-5xl mx-auto space-y-6">
        <div>
          <.link
            :if={@school}
            navigate={~p"/school-goals/#{@school.slug}"}
            class="text-sm text-base-content/50 hover:text-base-content flex items-center gap-1 mb-3"
            id="nd-back-to-school"
          >
            <.icon name="hero-arrow-left" class="size-4" />
            Back to {@school.short_name ||
              @school.name}
          </.link>
          <.link
            :if={!@school}
            navigate={~p"/school-goals"}
            class="text-sm text-base-content/50 hover:text-base-content flex items-center gap-1 mb-3"
          >
            <.icon name="hero-arrow-left" class="size-4" /> ND First
          </.link>
          <h1 class="text-2xl font-bold">ND Insights data import</h1>
          <div
            :if={@school}
            class="mt-3 rounded-xl border border-primary/30 bg-primary/5 px-4 py-3"
            id="nd-locked-school"
          >
            <div class="text-xs uppercase tracking-wide text-base-content/60">Importing for</div>
            <div class="text-lg font-semibold leading-snug" id="nd-locked-school-name">
              {@school.name}
            </div>
            <div class="text-sm text-base-content/70">
              <span id="nd-locked-school-kind">{@institution.kind_label}</span><span :if={
                @institution.participant
              }> of {@institution.participant.name}</span>
              · InstitutionID
              <span class="font-mono" id="nd-locked-school-id">{@school.state_entity_id}</span>
            </div>
            <p class="text-xs text-base-content/60 mt-2" id="nd-locked-scope-note">
              {scope_note(@school, @institution)}
            </p>
          </div>
          <p class="text-sm text-base-content/60 mt-1">
            Upload an official CSV from
            <a
              href="https://insights.nd.gov/Data"
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary"
            >
              insights.nd.gov/Data
            </a>
            — Assessment Performance, Assessment Participation, Growth Rate or an Engagement Survey
            file — with its original name and headers. Statewide files are fine; {if @school,
              do: "only #{@school.name}'s own rows are previewed and imported.",
              else: "only the schools you select are imported."} Nothing is saved until you confirm.
          </p>
        </div>

        <div
          class="space-y-4 p-6 shadow-xl rounded-xl bg-base-100 border border-base-200"
          id="nd-upload"
        >
          <h2 class="font-semibold">1. Upload</h2>
          <form id="nd-upload-form" phx-change="validate" phx-submit="validate">
            <label
              for={@uploads.csv.ref}
              phx-drop-target={@uploads.csv.ref}
              class="flex flex-col items-center justify-center gap-2 border-2 border-dashed border-base-300 rounded-xl p-8 text-center cursor-pointer hover:border-primary transition-colors"
              id="nd-drop-zone"
            >
              <.icon name="hero-arrow-up-tray" class="size-8 text-base-content/50" />
              <span class="font-medium">Drop an Insights CSV here, or click to choose</span>
              <span class="text-xs text-base-content/50">One .csv file, up to {@max_mb} MB</span>
              <.live_file_input upload={@uploads.csv} class="sr-only" />
            </label>
          </form>

          <div :for={entry <- @uploads.csv.entries} class="text-sm" id="nd-upload-progress">
            {entry.client_name} — {entry.progress}%
            <progress class="progress progress-primary w-full" value={entry.progress} max="100">
            </progress>
            <p :for={err <- upload_errors(@uploads.csv, entry)} class="text-error text-xs">
              {upload_error(err)}
            </p>
          </div>
          <p :for={err <- upload_errors(@uploads.csv)} class="text-error text-sm">
            {upload_error(err)}
          </p>

          <div
            :if={@staged && !@preview && !@preview_error}
            class="text-sm text-base-content/60"
            id="nd-previewing"
          >
            <span class="loading loading-spinner loading-xs"></span> Reading {@staged.file_name}…
          </div>

          <div
            :if={@preview_error}
            class="alert alert-error text-sm"
            role="alert"
            id="nd-preview-error"
          >
            <div>
              <div class="font-medium">This file can't be imported</div>
              <div>{@preview_error}</div>
            </div>
          </div>
        </div>

        <.preview_panel
          :if={@preview}
          preview={@preview}
          labels={@labels}
          selected={@selected}
          confirm_revision={@confirm_revision}
          importing={@importing}
          school={@school}
        />

        <.result_panel :if={@result} result={@result} school={@school} />

        <div class="space-y-2" id="nd-import-runs">
          <h2 class="font-semibold">
            Recent imports<span :if={@school}> for {@school.short_name || @school.name}</span>
          </h2>
          <div class="overflow-x-auto bg-base-100 border border-base-200 rounded-xl">
            <table class="table table-sm w-full">
              <thead>
                <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                  <th>When (UTC)</th>
                  <th>File</th>
                  <th>Schools</th>
                  <th>Outcome</th>
                  <th>By</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@runs == []}>
                  <td colspan="5" class="text-center text-base-content/50 italic">No imports yet.</td>
                </tr>
                <tr :for={run <- @runs} id={"run-#{run.id}"}>
                  <td class="whitespace-nowrap">
                    {Calendar.strftime(run.ran_at, "%b %-d, %Y %H:%M")}
                  </td>
                  <td class="font-mono text-xs break-all">{run.file_name}</td>
                  <td class="font-mono text-xs">
                    {Enum.map_join(run.institution_ids, ", ", &institution_label/1)}
                  </td>
                  <td>
                    <span class={["badge badge-sm", outcome_badge(run.outcome)]}>
                      {outcome_label(run.outcome)}
                    </span>
                    <div
                      :if={run.outcome in [:imported, :no_changes]}
                      class="text-xs text-base-content/60"
                    >
                      {run.report["created"]} new · {run.report["unchanged"]} unchanged · {run.report[
                        "conflict_count"
                      ]} conflicts
                    </div>
                    <div :if={run.error} class="text-xs text-base-content/60">{run.error}</div>
                  </td>
                  <td class="text-xs">{run.imported_by && to_string(run.imported_by.email)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :preview, :map, required: true
  attr :labels, :map, required: true
  attr :selected, :any, required: true
  attr :confirm_revision, :boolean, required: true
  attr :importing, :boolean, required: true
  attr :school, :any, default: nil

  defp preview_panel(assigns) do
    ~H"""
    <div class="space-y-4 p-6 shadow-xl rounded-xl bg-base-100 border border-base-200" id="nd-preview">
      <h2 class="font-semibold">2. Review</h2>
      <dl class="grid grid-cols-1 sm:grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
        <dt class="text-base-content/60">File</dt>
        <dd class="font-mono text-xs break-all">{@preview.file_name}</dd>
        <dt class="text-base-content/60">Dataset</dt>
        <dd id="nd-preview-dataset">{@labels[@preview.dataset]}</dd>
        <dt class="text-base-content/60">Academic years</dt>
        <dd id="nd-preview-years">{Enum.join(@preview.years, ", ")}</dd>
        <dt class="text-base-content/60">Publication version</dt>
        <dd>
          {@preview.publication_version}
          <span :if={!@preview.version_from_file_name?} class="text-warning text-xs block">
            The file name has no -vYYYYMMDD stamp, so a version was derived from the file's
            contents. Keep the original Insights file name if possible.
          </span>
        </dd>
        <dt class="text-base-content/60">Rows / institutions</dt>
        <dd>{@preview.rows_read} rows · {@preview.institution_count} institutions statewide</dd>
      </dl>

      <div :if={@preview.already_imported?} class="alert alert-info text-sm" id="nd-already-imported">
        This exact file has been imported before. Importing again creates no duplicates; already stored
        measures are reported as unchanged.
      </div>

      <div
        :if={@preview.totals.errors > 0}
        class="alert alert-warning text-sm block"
        id="nd-preview-errors"
      >
        <div class="font-medium">
          {@preview.totals.errors} values for the selected schools can't be read and will be skipped:
        </div>
        <ul class="list-disc list-inside text-xs mt-1">
          <li :for={e <- @preview.totals.error_sample}>Line {e.line}, {e.measure}: {e.message}</li>
        </ul>
      </div>

      <form id="nd-select-form" phx-change="select" phx-submit="import" class="space-y-3">
        <p :if={!@school} class="text-xs text-base-content/60" id="nd-pilot-scope">
          This release imports only the ND First pilot schools; other schools in the file are not
          listed or imported.
        </p>
        <p :if={@school} class="text-xs text-base-content/60" id="nd-pilot-scope">
          Locked to {@school.name}; other schools in the file are not listed or imported.
        </p>

        <div :if={@preview.schools == [] and !@school} class="alert text-sm" id="nd-no-schools">
          None of the ND First pilot schools appear in this file, so there is nothing to import.
        </div>
        <div :if={@preview.schools == [] and @school} class="alert text-sm" id="nd-no-schools">
          This file has no records for {@school.name} ({@school.state_entity_id}). Nothing will be
          imported or changed.
        </div>

        <div :if={@preview.schools != []} class="overflow-x-auto">
          <table class="table table-sm w-full" id="nd-preview-schools">
            <thead>
              <tr class="bg-base-200/60 text-base-content/70 text-xs uppercase tracking-wide">
                <th>Import</th>
                <th>School (Emisint)</th>
                <th>InstitutionID</th>
                <th>Name in file</th>
                <th>Measures</th>
                <th>Already stored</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={s <- @preview.schools} id={"nd-school-#{s.institution_id}"}>
                <td>
                  <input
                    type="checkbox"
                    name="institution_ids[]"
                    value={s.institution_id}
                    checked={MapSet.member?(@selected, s.institution_id)}
                    disabled={@school != nil}
                    class="checkbox checkbox-sm"
                    aria-label={"Import #{hd(s.emisint_names)}"}
                  />
                </td>
                <td>
                  <div class="font-medium">{Enum.join(s.emisint_names, " / ")}</div>
                  <div class="text-xs text-base-content/50">{Enum.join(s.organizations, ", ")}</div>
                </td>
                <td class="font-mono text-xs">{s.institution_id}</td>
                <td>
                  {Enum.join(s.published_names, " / ")}
                  <div :if={!s.name_matches?} class="text-xs text-warning">
                    Name differs from Emisint; matched by InstitutionID only.
                  </div>
                </td>
                <td>{Map.get(s, :measures, 0)}</td>
                <td>{Map.get(s, :already_stored, 0)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <.benchmark_summary benchmark={@preview.benchmark} />

        <div
          :if={@preview.prior_versions != []}
          class="alert alert-warning text-sm block"
          id="nd-revision"
        >
          <div class="font-medium">This is a revised publication.</div>
          <div>
            Data for these schools and years is already stored as version {Enum.join(
              @preview.prior_versions,
              ", "
            )}. Importing stores version {@preview.publication_version} alongside it (the earlier publication is kept, and any
            changed values are reported). The dashboard uses the latest version.
          </div>
          <label class="flex items-center gap-2 mt-2">
            <input
              type="checkbox"
              name="confirm_revision"
              value="true"
              checked={@confirm_revision}
              class="checkbox checkbox-sm"
            /> I confirm this revised publication should be imported.
          </label>
        </div>

        <div
          :if={!@school and @preview.registered_not_in_file != []}
          class="text-xs text-base-content/60"
        >
          Pilot schools not in this file: {Enum.map_join(
            @preview.registered_not_in_file,
            ", ",
            &"#{hd(&1.emisint_names)} (#{&1.institution_id})"
          )}
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            type="submit"
            class="btn btn-primary btn-sm"
            id="nd-import-button"
            disabled={
              @importing or MapSet.size(@selected) == 0 or
                (@preview.prior_versions != [] and not @confirm_revision)
            }
          >
            <span :if={@importing} class="loading loading-spinner loading-xs"></span>
            {if @school, do: "Import", else: "Import #{MapSet.size(@selected)} school(s)"}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel">Cancel</button>
          <span class="text-xs text-base-content/60">
            {@preview.totals.new} of {@preview.totals.measures} measures for the schools found are new.
          </span>
        </div>
      </form>
    </div>
    """
  end

  attr :benchmark, :map, default: nil

  defp benchmark_summary(%{benchmark: nil} = assigns), do: ~H""

  defp benchmark_summary(%{benchmark: %{usable?: true}} = assigns) do
    ~H"""
    <div class="rounded-lg border border-base-200 p-3 text-sm" id="nd-benchmark">
      <div class="font-medium">North Dakota state benchmark</div>
      <div class="text-xs text-base-content/70">
        InstitutionID {@benchmark.institution_id} “State of North Dakota” · {@benchmark.measures} measures · {@benchmark.measures -
          @benchmark.already_stored} new · {@benchmark.already_stored} already stored
      </div>
      <div class="text-xs text-base-content/60 mt-1">
        Imported with the selected school as a comparison benchmark only; it is not a school and
        gets no dashboard of its own.
      </div>
    </div>
    """
  end

  defp benchmark_summary(%{benchmark: %{present?: true}} = assigns) do
    ~H"""
    <div class="alert alert-warning text-sm" id="nd-benchmark">
      InstitutionID {@benchmark.institution_id} appears as “{Enum.join(
        @benchmark.published_names,
        " / "
      )}”, not “State of North Dakota”, so it is not imported as the state benchmark.
    </div>
    """
  end

  defp benchmark_summary(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-200 p-3 text-xs text-base-content/70" id="nd-benchmark">
      This file has no North Dakota statewide rows. The school's results import normally; the
      dashboard shows “No North Dakota benchmark” for this data until a file with state rows is
      imported.
    </div>
    """
  end

  attr :result, :map, required: true
  attr :school, :any, default: nil

  defp result_panel(%{result: %{error: _}} = assigns) do
    ~H"""
    <div class="alert alert-error text-sm" id="nd-result">{@result.error}</div>
    """
  end

  defp result_panel(assigns) do
    ~H"""
    <div
      class={["alert text-sm block", if(@result.created > 0, do: "alert-success", else: "alert-info")]}
      id="nd-result"
    >
      <div class="font-medium">
        {if @result.created > 0, do: "Imported", else: "No changes from"} {@result.file}
      </div>
      <div>
        {@result.created} new · {@result.unchanged} already stored · {@result.duplicate_count} duplicates · {@result.conflict_count} conflicts · {@result.changed_from_previous_count} changed from the previous publication
      </div>
      <ul
        :if={Map.get(@result, :by_institution, %{}) != %{}}
        class="text-xs mt-1"
        id="nd-result-split"
      >
        <li :for={
          {id, counts} <- Enum.sort_by(@result.by_institution, &Benchmark.state?(elem(&1, 0)))
        }>
          {if Benchmark.state?(id),
            do: "North Dakota state benchmark (#{id})",
            else: "School #{id}"}: {counts.created} new · {counts.unchanged} already stored
        </li>
      </ul>
      <div :for={c <- @result.conflicts} class="text-xs">Conflict: {c.key} — {c.reason}</div>
      <div :if={@result.created > 0} class="text-xs mt-1">
        Open ND First dashboards for these schools refresh automatically.
      </div>
      <.link
        :if={@school}
        navigate={~p"/school-goals/#{@school.slug}"}
        class="btn btn-sm btn-primary mt-2"
        id="nd-view-dashboard"
      >
        {if @result.created > 0, do: "View updated dashboard", else: "Back to dashboard"}
      </.link>
    </div>
    """
  end

  # The locked page's scope sentence: built here so the punctuation stays
  # attached to the text (no template whitespace before the periods).
  defp scope_note(school, %{separate: []}),
    do: "Only rows published under InstitutionID #{school.state_entity_id} are imported."

  defp scope_note(school, %{separate: separate}) do
    related = Enum.map_join(separate, "; ", &"#{&1.name} (#{&1.state_entity_id})")

    "Only rows published under InstitutionID #{school.state_entity_id} are imported. " <>
      "These related records have their own InstitutionIDs and are imported only from " <>
      "their own pages: #{related}."
  end

  defp institution_label(id) do
    if Benchmark.state?(id), do: "#{id} (ND state benchmark)", else: id
  end

  defp upload_error(:too_large), do: "The file is larger than the upload limit."
  defp upload_error(:not_accepted), do: "Only .csv files are accepted."
  defp upload_error(:too_many_files), do: "Upload one file at a time."
  defp upload_error(other), do: "Upload failed: #{inspect(other)}"

  defp outcome_label(:imported), do: "Imported"
  defp outcome_label(:no_changes), do: "No changes"
  defp outcome_label(:rejected), do: "Rejected"
  defp outcome_label(:failed), do: "Failed"

  defp outcome_badge(:imported), do: "badge-success"
  defp outcome_badge(:no_changes), do: "badge-ghost"
  defp outcome_badge(:rejected), do: "badge-warning"
  defp outcome_badge(:failed), do: "badge-error"
end
