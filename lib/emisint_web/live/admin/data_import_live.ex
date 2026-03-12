defmodule EmisintWeb.Admin.DataImportLive do
  use EmisintWeb, :live_view

  require Ash.Query

  @providers [
    {"NWEA MAP", "nwea_map"},
    {"i-Ready", "i_ready"}
  ]

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    scope = socket.assigns.scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Emisint.PubSub, "data_sync:#{oid}")

      # System admins receive real-time MDE import status updates
      if user.role == :system_admin do
        Phoenix.PubSub.subscribe(Emisint.PubSub, "mde_import")
        Phoenix.PubSub.subscribe(Emisint.PubSub, "entity_master_import")
        Phoenix.PubSub.subscribe(Emisint.PubSub, "enrollment_import")
        Phoenix.PubSub.subscribe(Emisint.PubSub, "sat_import")
      end
    end

    schools = if oid, do: Ash.read!(Emisint.Accounts.School, scope: scope), else: []
    academic_years = if oid, do: Emisint.Registry.list_academic_years!(scope: scope), else: []
    recent_logs = load_recent_logs(oid, user)

    socket =
      socket
      |> assign(:page_title, "Data Import")
      |> assign(:schools, schools)
      |> assign(:academic_years, academic_years)
      |> assign(:recent_logs, recent_logs)
      |> assign(:selected_school_id, nil)
      |> assign(:selected_year_id, nil)
      |> assign(:selected_provider, "nwea_map")
      |> assign(:importing, false)
      |> assign(:providers, @providers)
      |> assign(:import_result, nil)
      |> assign(:mde_importing, false)
      |> assign(:mde_import_result, nil)
      |> assign(:entity_master_importing, false)
      |> assign(:entity_master_import_result, nil)
      |> assign(:enrollment_importing, false)
      |> assign(:enrollment_import_result, nil)
      |> assign(:sat_importing, false)
      |> assign(:sat_import_result, nil)
      |> allow_upload(:csv_file,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 10_000_000
      )
      |> assign(:mde_upload, nil)
      |> assign(:mde_upload_progress, nil)
      |> assign(:entity_master_upload, nil)
      |> assign(:entity_master_upload_progress, nil)
      |> assign(:enrollment_upload, nil)
      |> assign(:enrollment_upload_progress, nil)
      |> assign(:sat_upload, nil)
      |> assign(:sat_upload_progress, nil)
      |> assign(:import_history, if(user.role == :system_admin, do: load_import_history(), else: []))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub — tenant CSV worker status update
  # ---------------------------------------------------------------------------

  def handle_info({:data_sync_updated, _org_id}, socket) do
    user = socket.assigns.current_user
    oid = user.organization_id
    logs = load_recent_logs(oid, user)

    {:noreply,
     socket
     |> assign(:recent_logs, logs)
     |> assign(:importing, false)}
  end

  # ---------------------------------------------------------------------------
  # PubSub — MDE import status updates
  # ---------------------------------------------------------------------------

  def handle_info({:mde_import_completed, stats}, socket) do
    {:noreply,
     socket
     |> assign(:mde_importing, false)
     |> assign(:mde_import_result, {:ok, stats})
     |> assign(:import_history, load_import_history())
     |> put_flash(
       :info,
       "MDE import complete — #{format_number(stats.results)} results loaded across #{stats.buildings} buildings."
     )}
  end

  def handle_info({:mde_import_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:mde_importing, false)
     |> assign(:mde_import_result, {:error, reason})
     |> assign(:import_history, load_import_history())
     |> put_flash(:error, "MDE import failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # PubSub — EntityMaster import status updates
  # ---------------------------------------------------------------------------

  def handle_info({:entity_master_import_completed, stats}, socket) do
    {:noreply,
     socket
     |> assign(:entity_master_importing, false)
     |> assign(:entity_master_import_result, {:ok, stats})
     |> assign(:import_history, load_import_history())
     |> put_flash(
       :info,
       "EntityMaster import complete — #{format_number(stats.records)} entities loaded."
     )}
  end

  def handle_info({:entity_master_import_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:entity_master_importing, false)
     |> assign(:entity_master_import_result, {:error, reason})
     |> assign(:import_history, load_import_history())
     |> put_flash(:error, "EntityMaster import failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # PubSub — Enrollment import status updates
  # ---------------------------------------------------------------------------

  def handle_info({:enrollment_import_completed, stats}, socket) do
    {:noreply,
     socket
     |> assign(:enrollment_importing, false)
     |> assign(:enrollment_import_result, {:ok, stats})
     |> assign(:import_history, load_import_history())
     |> put_flash(
       :info,
       "Enrollment import complete — #{format_number(stats.records)} records loaded."
     )}
  end

  def handle_info({:enrollment_import_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:enrollment_importing, false)
     |> assign(:enrollment_import_result, {:error, reason})
     |> assign(:import_history, load_import_history())
     |> put_flash(:error, "Enrollment import failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # PubSub — SAT import status updates
  # ---------------------------------------------------------------------------

  def handle_info({:sat_import_completed, stats}, socket) do
    {:noreply,
     socket
     |> assign(:sat_importing, false)
     |> assign(:sat_import_result, {:ok, stats})
     |> assign(:import_history, load_import_history())
     |> put_flash(
       :info,
       "SAT import complete — #{format_number(stats.records)} records loaded."
     )}
  end

  def handle_info({:sat_import_failed, reason}, socket) do
    {:noreply,
     socket
     |> assign(:sat_importing, false)
     |> assign(:sat_import_result, {:error, reason})
     |> assign(:import_history, load_import_history())
     |> put_flash(:error, "SAT import failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # Events — tenant CSV upload
  # ---------------------------------------------------------------------------

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_field", %{"_target" => [field]} = params, socket) do
    key = String.to_existing_atom("selected_#{field}")
    {:noreply, assign(socket, key, params[field])}
  end

  def handle_event(
        "import",
        %{
          "school_id" => school_id,
          "year_id" => year_id,
          "provider" => provider
        },
        socket
      ) do
    if school_id == "" or year_id == "" do
      {:noreply, put_flash(socket, :error, "Please select a school and academic year.")}
    else
      user = socket.assigns.current_user
      oid = user.organization_id

      case consume_uploaded_entries(socket, :csv_file, fn %{path: path}, entry ->
             content = File.read!(path)
             rows = parse_csv(content)
             {:ok, %{rows: rows, filename: entry.client_name, row_count: length(rows)}}
           end) do
        [] ->
          {:noreply, put_flash(socket, :error, "Please select a CSV file to upload.")}

        [%{rows: rows, filename: filename, row_count: row_count}] ->
          %{
            "organization_id" => oid,
            "school_id" => school_id,
            "academic_year_id" => year_id,
            "provider_code" => provider,
            "rows" => rows
          }
          |> Emisint.Workers.CsvImportWorker.new()
          |> Oban.insert!()

          {:noreply,
           socket
           |> assign(:importing, true)
           |> assign(:import_result, %{filename: filename, row_count: row_count})
           |> put_flash(
             :info,
             "Import queued: #{filename} (#{row_count} rows). Processing in background…"
           )}
      end
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  # ---------------------------------------------------------------------------
  # Tigris direct-upload events — shared across all MDE import types
  # ---------------------------------------------------------------------------

  def handle_event("file_selected", %{"upload_type" => type, "name" => name, "size" => size}, socket) do
    upload_key = String.to_existing_atom("#{type}_upload")
    progress_key = String.to_existing_atom("#{type}_upload_progress")

    {:noreply,
     socket
     |> assign(upload_key, %{name: name, size: size})
     |> assign(progress_key, nil)}
  end

  def handle_event("file_cleared", %{"upload_type" => type}, socket) do
    upload_key = String.to_existing_atom("#{type}_upload")
    progress_key = String.to_existing_atom("#{type}_upload_progress")

    {:noreply,
     socket
     |> assign(upload_key, nil)
     |> assign(progress_key, nil)}
  end

  def handle_event("request_upload_url", %{"upload_type" => type, "filename" => filename}, socket) do
    key = Emisint.Storage.import_key(type, filename)

    case Emisint.Storage.presigned_upload_url(key) do
      {:ok, url} ->
        {:noreply, push_event(socket, "presigned_url:#{type}", %{url: url, key: key})}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not prepare upload: #{inspect(reason)}")}
    end
  end

  def handle_event("upload_progress", %{"upload_type" => type, "progress" => pct}, socket) do
    progress_key = String.to_existing_atom("#{type}_upload_progress")
    {:noreply, assign(socket, progress_key, pct)}
  end

  def handle_event("upload_complete", %{"upload_type" => "mde", "key" => key, "filename" => filename}, socket) do
    user = socket.assigns.current_user
    log_id = create_import_log(:mde, filename, socket.assigns.mde_upload, key, user)

    %{"bucket" => Emisint.Storage.bucket(), "key" => key, "log_id" => log_id}
    |> Emisint.Workers.MdeImportWorker.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:mde_importing, true)
     |> assign(:mde_import_result, nil)
     |> assign(:mde_upload, nil)
     |> assign(:mde_upload_progress, nil)
     |> assign(:import_history, load_import_history())
     |> put_flash(:info, "MDE import queued: #{filename}. Processing in background…")}
  end

  def handle_event("upload_complete", %{"upload_type" => "entity_master", "key" => key, "filename" => filename}, socket) do
    user = socket.assigns.current_user
    log_id = create_import_log(:entity_master, filename, socket.assigns.entity_master_upload, key, user)

    %{"bucket" => Emisint.Storage.bucket(), "key" => key, "log_id" => log_id}
    |> Emisint.Workers.EntityMasterImportWorker.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:entity_master_importing, true)
     |> assign(:entity_master_import_result, nil)
     |> assign(:entity_master_upload, nil)
     |> assign(:entity_master_upload_progress, nil)
     |> assign(:import_history, load_import_history())
     |> put_flash(:info, "EntityMaster import queued: #{filename}. Processing in background…")}
  end

  def handle_event("upload_complete", %{"upload_type" => "enrollment", "key" => key, "filename" => filename}, socket) do
    user = socket.assigns.current_user
    log_id = create_import_log(:enrollment, filename, socket.assigns.enrollment_upload, key, user)

    %{"bucket" => Emisint.Storage.bucket(), "key" => key, "log_id" => log_id}
    |> Emisint.Workers.MdeEnrollmentImportWorker.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:enrollment_importing, true)
     |> assign(:enrollment_import_result, nil)
     |> assign(:enrollment_upload, nil)
     |> assign(:enrollment_upload_progress, nil)
     |> assign(:import_history, load_import_history())
     |> put_flash(:info, "Enrollment import queued: #{filename}. Processing in background…")}
  end

  def handle_event("upload_complete", %{"upload_type" => "sat", "key" => key, "filename" => filename}, socket) do
    user = socket.assigns.current_user
    log_id = create_import_log(:sat, filename, socket.assigns.sat_upload, key, user)

    %{"bucket" => Emisint.Storage.bucket(), "key" => key, "log_id" => log_id}
    |> Emisint.Workers.MdeSatImportWorker.new()
    |> Oban.insert!()

    {:noreply,
     socket
     |> assign(:sat_importing, true)
     |> assign(:sat_import_result, nil)
     |> assign(:sat_upload, nil)
     |> assign(:sat_upload_progress, nil)
     |> assign(:import_history, load_import_history())
     |> put_flash(:info, "SAT import queued: #{filename}. Processing in background…")}
  end

  def handle_event("upload_failed", %{"upload_type" => type, "reason" => reason}, socket) do
    upload_key = String.to_existing_atom("#{type}_upload")
    progress_key = String.to_existing_atom("#{type}_upload_progress")

    {:noreply,
     socket
     |> assign(upload_key, nil)
     |> assign(progress_key, nil)
     |> put_flash(:error, "Upload failed: #{reason}")}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    assigns = assign(assigns, :providers, @providers)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-6xl mx-auto space-y-10">
        <%!-- Page header --%>
        <div class="flex items-center gap-4">
          <div class="p-2.5 bg-primary/10 border border-primary/20">
            <.icon name="hero-arrow-up-tray" class="size-6 text-primary" />
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight">Data Import</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Upload CSV exports to populate assessment data.
            </p>
          </div>
        </div>

        <%!-- ── Section 1: Tenant assessment CSV (NWEA / i-Ready) ─────────────── --%>
        <div class="space-y-4">
          <div class="flex items-center gap-2">
            <h2 class="text-base font-semibold">Interim Assessment Data</h2>
            <span class="badge badge-ghost badge-sm">NWEA MAP · i-Ready</span>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
            <%!-- Upload form — 3 cols --%>
            <div class="lg:col-span-3 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200">
                <h3 class="font-semibold">Upload Assessment CSV</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  All fields are required before submitting
                </p>
              </div>

              <form phx-submit="import" phx-change="validate" class="p-6 space-y-6">
                <%!-- School + Year row --%>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div class="space-y-1.5">
                    <label class="text-sm font-medium">
                      School <span class="text-error text-xs">*</span>
                    </label>
                    <select
                      name="school_id"
                      class="w-full border border-base-300 bg-base-100 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary transition-all"
                      phx-change="update_field"
                      phx-value-field="school_id"
                    >
                      <option value="">Select a school…</option>
                      <option
                        :for={school <- @schools}
                        value={school.id}
                        selected={school.id == @selected_school_id}
                      >
                        {school.name}
                      </option>
                    </select>
                  </div>

                  <div class="space-y-1.5">
                    <label class="text-sm font-medium">
                      Academic Year <span class="text-error text-xs">*</span>
                    </label>
                    <select
                      name="year_id"
                      class="w-full border border-base-300 bg-base-100 px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary transition-all"
                      phx-change="update_field"
                      phx-value-field="year_id"
                    >
                      <option value="">Select a year…</option>
                      <option
                        :for={year <- @academic_years}
                        value={year.id}
                        selected={year.id == @selected_year_id}
                      >
                        {year.label}
                      </option>
                    </select>
                  </div>
                </div>

                <%!-- Provider selector --%>
                <div class="space-y-1.5">
                  <label class="text-sm font-medium">Assessment Provider</label>
                  <div class="flex gap-3">
                    <label
                      :for={{label, value} <- @providers}
                      class={[
                        "flex-1 flex items-center gap-3 px-4 py-3 border-2 cursor-pointer transition-all select-none",
                        @selected_provider == value &&
                          "border-primary bg-primary/5",
                        @selected_provider != value &&
                          "border-base-200 hover:border-base-300 bg-base-50/50"
                      ]}
                    >
                      <div class={[
                        "size-4 rounded-full border-2 flex items-center justify-center shrink-0 transition-all",
                        @selected_provider == value && "border-primary",
                        @selected_provider != value && "border-base-300"
                      ]}>
                        <div
                          :if={@selected_provider == value}
                          class="size-1.5 rounded-full bg-primary"
                        >
                        </div>
                      </div>
                      <input
                        type="radio"
                        name="provider"
                        value={value}
                        checked={@selected_provider == value}
                        class="hidden"
                        phx-change="update_field"
                        phx-value-field="provider"
                      />
                      <span class="text-sm font-medium">{label}</span>
                    </label>
                  </div>
                </div>

                <%!-- File upload drop zone --%>
                <div class="space-y-2">
                  <label class="text-sm font-medium">
                    CSV File <span class="text-error text-xs">*</span>
                  </label>

                  <div
                    class="relative border-2 border-dashed border-base-300 hover:border-primary/40 bg-base-50/50 transition-colors group cursor-pointer"
                    phx-drop-target={@uploads.csv_file.ref}
                  >
                    <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                      <div class="p-3 bg-base-200 group-hover:bg-primary/10 transition-colors mb-3">
                        <.icon
                          name="hero-document-text"
                          class="size-7 text-base-content/30 group-hover:text-primary transition-colors"
                        />
                      </div>
                      <p class="text-sm text-base-content/50">
                        Drag & drop your CSV here, or{" "}
                        <span class="text-primary font-medium hover:underline">browse</span>
                      </p>
                      <p class="text-xs text-base-content/30 mt-1">CSV files up to 10 MB</p>
                      <.live_file_input upload={@uploads.csv_file} class="hidden" />
                    </label>
                  </div>

                  <%!-- File entry preview --%>
                  <div
                    :for={entry <- @uploads.csv_file.entries}
                    class="flex items-center gap-3 p-3 border border-base-200 bg-base-50"
                  >
                    <div class="p-2 bg-primary/10 shrink-0">
                      <.icon name="hero-document-text" class="size-4 text-primary" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium truncate">{entry.client_name}</div>
                      <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                        <div
                          class="bg-primary h-1 rounded-full transition-all duration-300"
                          style={"width: #{entry.progress}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/40 shrink-0">
                      {format_bytes(entry.client_size)}
                    </span>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="p-1.5 hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>

                  <%!-- Upload errors --%>
                  <div
                    :for={err <- upload_errors(@uploads.csv_file)}
                    class="flex items-center gap-2 text-sm text-error bg-error/5 border border-error/10 px-3 py-2.5"
                  >
                    <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
                    {upload_error_msg(err)}
                  </div>
                </div>

                <%!-- Submit button --%>
                <button
                  type="submit"
                  class={[
                    "w-full flex items-center justify-center gap-2 py-3 font-medium text-sm transition-all",
                    !@importing &&
                      "bg-primary text-primary-content hover:opacity-90 active:scale-[0.99]",
                    @importing && "bg-primary/50 text-primary-content/70 cursor-not-allowed"
                  ]}
                  disabled={@importing}
                >
                  <span :if={@importing} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@importing} name="hero-arrow-up-tray" class="size-4" />
                  {if @importing, do: "Processing…", else: "Start Import"}
                </button>
              </form>
            </div>

            <%!-- Recent imports — 2 cols --%>
            <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                <div>
                  <h3 class="font-semibold">Recent Imports</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">Last 20 jobs</p>
                </div>
                <div :if={@importing} class="flex items-center gap-1.5 text-xs text-base-content/40">
                  <span class="loading loading-spinner loading-xs"></span> Processing…
                </div>
              </div>

              <div
                :if={@recent_logs == []}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-base-200 mb-3">
                  <.icon name="hero-inbox" class="size-6 text-base-content/25" />
                </div>
                <p class="text-sm font-medium text-base-content/40">No imports yet</p>
                <p class="text-xs text-base-content/30 mt-1">Upload a CSV file to get started.</p>
              </div>

              <div :if={@recent_logs != []} class="divide-y divide-base-200">
                <div
                  :for={log <- @recent_logs}
                  class="px-5 py-3.5 hover:bg-base-50 transition-colors"
                >
                  <div class="flex items-start justify-between gap-2">
                    <div class="flex items-center gap-2 min-w-0">
                      <.sync_status_dot status={log.status} />
                      <span class="text-sm font-medium capitalize truncate">
                        {log.job_type |> to_string() |> String.replace("_", " ")}
                      </span>
                    </div>
                    <span class="text-xs text-base-content/35 shrink-0 mt-0.5">
                      {format_datetime(log.inserted_at)}
                    </span>
                  </div>

                  <div class="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-1 ml-4 text-xs text-base-content/45">
                    <span :if={log.records_processed}>
                      <span class="text-success">✓</span> {log.records_processed} rows
                    </span>
                    <span :if={log.records_failed && log.records_failed > 0} class="text-error">
                      <span>✗</span> {log.records_failed} failed
                    </span>
                    <span
                      :if={log.metadata["provider_code"]}
                      class="uppercase tracking-wide font-medium"
                    >
                      {log.metadata["provider_code"] |> to_string() |> String.replace("_", " ")}
                    </span>
                  </div>

                  <p :if={log.error_message} class="ml-4 mt-1 text-xs text-error/70 truncate">
                    {log.error_message}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- ── Section 2: MDE State Assessment Data (system_admin only) ─────────── --%>
        <div class="divider"></div>
        <div :if={@current_user.role == :system_admin} class="space-y-4 p-8 shadow-xl">
          <div class="flex items-center gap-3">
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-base font-semibold">MDE State Assessment Data</h2>
                <span class="badge badge-warning badge-sm">System Admin</span>
              </div>
              <p class="text-xs text-base-content/50 mt-0.5">
                Import statewide M-STEP, PSAT, and SAT results from the MDE public CSV export.
                Loads into shared reference tables — all tenants benefit from a single import.
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
            <%!-- MDE Upload form — 3 cols --%>
            <div class="lg:col-span-3 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200">
                <h3 class="font-semibold">Upload MDE Export CSV</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  Large files are processed as a background job. No school or year selection needed.
                </p>
              </div>

              <div id="tigris-mde" phx-hook="TigrisUpload" data-upload-type="mde" class="p-6 space-y-6">
                <%!-- File upload drop zone --%>
                <div class="space-y-2">
                  <label class="text-sm font-medium">
                    MDE CSV File <span class="text-error text-xs">*</span>
                  </label>

                  <div
                    class="relative border-2 border-dashed border-base-300 hover:border-warning/40 bg-base-50/50 transition-colors group cursor-pointer"
                    data-drop-zone
                  >
                    <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                      <div class="p-3 bg-base-200 group-hover:bg-warning/10 transition-colors mb-3">
                        <.icon
                          name="hero-chart-bar"
                          class="size-7 text-base-content/30 group-hover:text-warning transition-colors"
                        />
                      </div>
                      <p class="text-sm text-base-content/50">
                        Drag & drop the MDE export here, or{" "}
                        <span class="text-warning font-medium hover:underline">browse</span>
                      </p>
                      <p class="text-xs text-base-content/30 mt-1">CSV files up to 300 MB</p>
                      <input type="file" accept=".csv" class="hidden" data-file-input />
                    </label>
                  </div>

                  <%!-- File entry preview --%>
                  <div
                    :if={@mde_upload}
                    class="flex items-center gap-3 p-3 border border-base-200 bg-base-50"
                  >
                    <div class="p-2 bg-warning/10 shrink-0">
                      <.icon name="hero-document-text" class="size-4 text-warning" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium truncate">{@mde_upload.name}</div>
                      <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                        <div
                          class="bg-warning h-1 rounded-full transition-all duration-300"
                          style={"width: #{@mde_upload_progress || 0}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/40 shrink-0">
                      {format_bytes(@mde_upload.size)}
                    </span>
                    <button
                      type="button"
                      data-cancel-btn
                      class="p-1.5 hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <%!-- Expected format hint --%>
                <div class="flex gap-3 p-4 bg-base-200/60 border border-base-300/50 text-xs text-base-content/50">
                  <.icon
                    name="hero-information-circle"
                    class="size-4 shrink-0 mt-0.5 text-base-content/35"
                  />
                  <div>
                    <p class="font-medium text-base-content/60 mb-1">Expected column headers</p>
                    <p class="font-mono leading-relaxed">
                      SchoolYear, TestType, TestPopulation, ISDCode, DistrictCode,
                      BuildingCode, GradeContentTested, Subject, ReportCategory,
                      TotalAdvanced … ScaleScore75
                    </p>
                  </div>
                </div>

                <%!-- Submit button --%>
                <button
                  type="button"
                  data-import-btn
                  class={[
                    "w-full flex items-center justify-center gap-2 py-3 font-medium text-sm transition-all",
                    !@mde_importing && !is_nil(@mde_upload) &&
                      "bg-warning text-warning-content hover:opacity-90 active:scale-[0.99]",
                    (@mde_importing || is_nil(@mde_upload)) &&
                      "bg-warning/50 text-warning-content/70 cursor-not-allowed"
                  ]}
                  disabled={@mde_importing || is_nil(@mde_upload)}
                >
                  <span :if={@mde_importing} class="loading loading-spinner loading-sm"></span>
                  <.icon :if={!@mde_importing} name="hero-arrow-up-tray" class="size-4" />
                  {if @mde_importing, do: "Processing…", else: "Import MDE Data"}
                </button>
              </div>
            </div>

            <%!-- MDE import result / status — 2 cols --%>
            <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                <div>
                  <h3 class="font-semibold">Import Status</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">Last job result</p>
                </div>
                <div
                  :if={@mde_importing}
                  class="flex items-center gap-1.5 text-xs text-base-content/40"
                >
                  <span class="loading loading-spinner loading-xs"></span> Running…
                </div>
              </div>

              <%!-- Idle / no result yet --%>
              <div
                :if={!@mde_importing && is_nil(@mde_import_result)}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-base-200 mb-3">
                  <.icon name="hero-chart-bar" class="size-6 text-base-content/25" />
                </div>
                <p class="text-sm font-medium text-base-content/40">No import yet</p>
                <p class="text-xs text-base-content/30 mt-1">
                  Upload an MDE export CSV to populate the reference tables.
                </p>
              </div>

              <%!-- In-progress pulse --%>
              <div
                :if={@mde_importing}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-warning/10 mb-3">
                  <span class="loading loading-spinner loading-md text-warning"></span>
                </div>
                <p class="text-sm font-medium">Processing MDE data…</p>
                <p class="text-xs text-base-content/40 mt-1">
                  Upserting ISDs, districts, buildings, and results in the background.
                </p>
              </div>

              <%!-- Success result --%>
              <div
                :if={match?({:ok, _}, @mde_import_result)}
                class="p-6 space-y-4"
              >
                <div class="flex items-center gap-2 text-success">
                  <.icon name="hero-check-circle" class="size-5" />
                  <span class="font-semibold text-sm">Import completed</span>
                </div>
                <dl class="grid grid-cols-2 gap-3">
                  <.mde_stat
                    label="ISDs"
                    value={elem(@mde_import_result, 1).isds}
                    icon="hero-building-office"
                  />
                  <.mde_stat
                    label="Districts"
                    value={elem(@mde_import_result, 1).districts}
                    icon="hero-map"
                  />
                  <.mde_stat
                    label="Buildings"
                    value={elem(@mde_import_result, 1).buildings}
                    icon="hero-academic-cap"
                  />
                  <.mde_stat
                    label="Results"
                    value={format_number(elem(@mde_import_result, 1).results)}
                    icon="hero-chart-bar"
                  />
                </dl>
                <div
                  :if={elem(@mde_import_result, 1).errors > 0}
                  class="flex items-center gap-2 text-xs text-warning bg-warning/5 border border-warning/15 px-3 py-2"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                  {elem(@mde_import_result, 1).errors} rows had errors and were skipped.
                </div>
                <a
                  :if={elem(@mde_import_result, 1).error_file}
                  href={~p"/admin/import/errors/download?#{%{path: elem(@mde_import_result, 1).error_file}}"}
                  class="flex items-center gap-2 text-xs text-warning hover:text-warning/80 bg-warning/5 border border-warning/15 px-3 py-2 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4 shrink-0" />
                  Download error rows — {Path.basename(elem(@mde_import_result, 1).error_file)}
                </a>
              </div>

              <%!-- Error result --%>
              <div
                :if={match?({:error, _}, @mde_import_result)}
                class="p-6"
              >
                <div class="flex items-start gap-3 p-4 bg-error/5 border border-error/15">
                  <.icon name="hero-x-circle" class="size-5 text-error shrink-0 mt-0.5" />
                  <div>
                    <p class="text-sm font-semibold text-error">Import failed</p>
                    <p class="text-xs text-base-content/50 mt-1 break-all">
                      {elem(@mde_import_result, 1)}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- ── Section 3: MDE EntityMaster (system_admin only) ─────────────────── --%>
        <div class="divider"></div>
        <div :if={@current_user.role == :system_admin} class="space-y-4 p-8 shadow-xl">
          <div class="flex items-center gap-3">
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-base font-semibold">MDE EntityMaster</h2>
                <span class="badge badge-warning badge-sm">System Admin</span>
              </div>
              <p class="text-xs text-base-content/50 mt-0.5">
                Import the MDE daily EntityMaster CSV — the complete registry of Michigan
                school entities. Upserts into a shared reference table on entity code.
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
            <%!-- EntityMaster Upload form — 3 cols --%>
            <div class="lg:col-span-3 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200">
                <h3 class="font-semibold">Upload EntityMaster CSV</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  Daily MDE feed. No school or year selection needed.
                </p>
              </div>

              <div id="tigris-entity-master" phx-hook="TigrisUpload" data-upload-type="entity_master" class="p-6 space-y-6">
                <%!-- File upload drop zone --%>
                <div class="space-y-2">
                  <label class="text-sm font-medium">
                    EntityMaster CSV File <span class="text-error text-xs">*</span>
                  </label>

                  <div
                    class="relative border-2 border-dashed border-base-300 hover:border-info/40 bg-base-50/50 transition-colors group cursor-pointer"
                    data-drop-zone
                  >
                    <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                      <div class="p-3 bg-base-200 group-hover:bg-info/10 transition-colors mb-3">
                        <.icon
                          name="hero-building-office-2"
                          class="size-7 text-base-content/30 group-hover:text-info transition-colors"
                        />
                      </div>
                      <p class="text-sm text-base-content/50">
                        Drag & drop the EntityMaster CSV here, or{" "}
                        <span class="text-info font-medium hover:underline">browse</span>
                      </p>
                      <p class="text-xs text-base-content/30 mt-1">CSV files up to 250 MB</p>
                      <input type="file" accept=".csv" class="hidden" data-file-input />
                    </label>
                  </div>

                  <%!-- File entry preview --%>
                  <div
                    :if={@entity_master_upload}
                    class="flex items-center gap-3 p-3 border border-base-200 bg-base-50"
                  >
                    <div class="p-2 bg-info/10 shrink-0">
                      <.icon name="hero-document-text" class="size-4 text-info" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium truncate">{@entity_master_upload.name}</div>
                      <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                        <div
                          class="bg-info h-1 rounded-full transition-all duration-300"
                          style={"width: #{@entity_master_upload_progress || 0}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/40 shrink-0">
                      {format_bytes(@entity_master_upload.size)}
                    </span>
                    <button
                      type="button"
                      data-cancel-btn
                      class="p-1.5 hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <%!-- Expected format hint --%>
                <div class="flex gap-3 p-4 bg-base-200/60 border border-base-300/50 text-xs text-base-content/50">
                  <.icon
                    name="hero-information-circle"
                    class="size-4 shrink-0 mt-0.5 text-base-content/35"
                  />
                  <div>
                    <p class="font-medium text-base-content/60 mb-1">Expected column headers</p>
                    <p class="font-mono leading-relaxed">
                      ISD Code, District Code, Entity Code, Entity Official Name,
                      Entity Type, Entity Status, Entity Open Date,
                      Entity Physical City … ESSA Support Category Status
                    </p>
                  </div>
                </div>

                <%!-- Submit button --%>
                <button
                  type="button"
                  data-import-btn
                  class={[
                    "w-full flex items-center justify-center gap-2 py-3 font-medium text-sm transition-all",
                    !@entity_master_importing && !is_nil(@entity_master_upload) &&
                      "bg-info text-info-content hover:opacity-90 active:scale-[0.99]",
                    (@entity_master_importing || is_nil(@entity_master_upload)) &&
                      "bg-info/50 text-info-content/70 cursor-not-allowed"
                  ]}
                  disabled={@entity_master_importing || is_nil(@entity_master_upload)}
                >
                  <span
                    :if={@entity_master_importing}
                    class="loading loading-spinner loading-sm"
                  >
                  </span>
                  <.icon
                    :if={!@entity_master_importing}
                    name="hero-arrow-up-tray"
                    class="size-4"
                  />
                  {if @entity_master_importing, do: "Processing…", else: "Import EntityMaster"}
                </button>
              </div>
            </div>

            <%!-- EntityMaster import result / status — 2 cols --%>
            <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                <div>
                  <h3 class="font-semibold">Import Status</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">Last job result</p>
                </div>
                <div
                  :if={@entity_master_importing}
                  class="flex items-center gap-1.5 text-xs text-base-content/40"
                >
                  <span class="loading loading-spinner loading-xs"></span> Running…
                </div>
              </div>

              <%!-- Idle / no result yet --%>
              <div
                :if={!@entity_master_importing && is_nil(@entity_master_import_result)}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-base-200 mb-3">
                  <.icon name="hero-building-office-2" class="size-6 text-base-content/25" />
                </div>
                <p class="text-sm font-medium text-base-content/40">No import yet</p>
                <p class="text-xs text-base-content/30 mt-1">
                  Upload an EntityMaster CSV to populate the reference table.
                </p>
              </div>

              <%!-- In-progress pulse --%>
              <div
                :if={@entity_master_importing}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-info/10 mb-3">
                  <span class="loading loading-spinner loading-md text-info"></span>
                </div>
                <p class="text-sm font-medium">Processing EntityMaster data…</p>
                <p class="text-xs text-base-content/40 mt-1">
                  Upserting entity records in the background.
                </p>
              </div>

              <%!-- Success result --%>
              <div
                :if={match?({:ok, _}, @entity_master_import_result)}
                class="p-6 space-y-4"
              >
                <div class="flex items-center gap-2 text-success">
                  <.icon name="hero-check-circle" class="size-5" />
                  <span class="font-semibold text-sm">Import completed</span>
                </div>
                <dl class="grid grid-cols-2 gap-3">
                  <.mde_stat
                    label="Entities"
                    value={format_number(elem(@entity_master_import_result, 1).records)}
                    icon="hero-building-office-2"
                  />
                  <.mde_stat
                    label="Errors"
                    value={elem(@entity_master_import_result, 1).errors}
                    icon="hero-exclamation-circle"
                  />
                </dl>
                <div
                  :if={elem(@entity_master_import_result, 1).errors > 0}
                  class="flex items-center gap-2 text-xs text-warning bg-warning/5 border border-warning/15 px-3 py-2"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                  {elem(@entity_master_import_result, 1).errors} rows had errors and were skipped.
                </div>
                <a
                  :if={elem(@entity_master_import_result, 1).error_file}
                  href={~p"/admin/import/errors/download?#{%{path: elem(@entity_master_import_result, 1).error_file}}"}
                  class="flex items-center gap-2 text-xs text-warning hover:text-warning/80 bg-warning/5 border border-warning/15 px-3 py-2 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4 shrink-0" />
                  Download error rows — {Path.basename(elem(@entity_master_import_result, 1).error_file)}
                </a>
              </div>

              <%!-- Error result --%>
              <div
                :if={match?({:error, _}, @entity_master_import_result)}
                class="p-6"
              >
                <div class="flex items-start gap-3 p-4 bg-error/5 border border-error/15">
                  <.icon name="hero-x-circle" class="size-5 text-error shrink-0 mt-0.5" />
                  <div>
                    <p class="text-sm font-semibold text-error">Import failed</p>
                    <p class="text-xs text-base-content/50 mt-1 break-all">
                      {elem(@entity_master_import_result, 1)}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- ── Section 4: MDE Enrollment (system_admin only) ──────────────────────── --%>
        <div class="divider"></div>
        <div :if={@current_user.role == :system_admin} class="space-y-4 p-8 shadow-xl">
          <div class="flex items-center gap-3">
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-base font-semibold">MDE Student Enrollment</h2>
                <span class="badge badge-success badge-sm">System Admin</span>
              </div>
              <p class="text-xs text-base-content/50 mt-0.5">
                Import the MDE annual enrollment CSV — building, district, and ISD-level
                counts by grade, race/ethnicity, and subgroup. Upserts one row per entity
                per school year.
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
            <%!-- Enrollment upload form — 3 cols --%>
            <div class="lg:col-span-3 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200">
                <h3 class="font-semibold">Upload Enrollment CSV</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  Annual MDE enrollment export. No school or year selection needed.
                </p>
              </div>

              <div id="tigris-enrollment" phx-hook="TigrisUpload" data-upload-type="enrollment" class="p-6 space-y-6">
                <%!-- File upload drop zone --%>
                <div class="space-y-2">
                  <label class="text-sm font-medium">
                    Enrollment CSV File <span class="text-error text-xs">*</span>
                  </label>

                  <div
                    class="relative border-2 border-dashed border-base-300 hover:border-success/40 bg-base-50/50 transition-colors group cursor-pointer"
                    data-drop-zone
                  >
                    <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                      <div class="p-3 bg-base-200 group-hover:bg-success/10 transition-colors mb-3">
                        <.icon
                          name="hero-users"
                          class="size-7 text-base-content/30 group-hover:text-success transition-colors"
                        />
                      </div>
                      <p class="text-sm text-base-content/50">
                        Drag & drop the Enrollment CSV here, or{" "}
                        <span class="text-success font-medium hover:underline">browse</span>
                      </p>
                      <p class="text-xs text-base-content/30 mt-1">CSV files up to 250 MB</p>
                      <input type="file" accept=".csv" class="hidden" data-file-input />
                    </label>
                  </div>

                  <%!-- File entry preview --%>
                  <div
                    :if={@enrollment_upload}
                    class="flex items-center gap-3 p-3 border border-base-200 bg-base-50"
                  >
                    <div class="p-2 bg-success/10 shrink-0">
                      <.icon name="hero-document-text" class="size-4 text-success" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium truncate">{@enrollment_upload.name}</div>
                      <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                        <div
                          class="bg-success h-1 rounded-full transition-all duration-300"
                          style={"width: #{@enrollment_upload_progress || 0}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/40 shrink-0">
                      {format_bytes(@enrollment_upload.size)}
                    </span>
                    <button
                      type="button"
                      data-cancel-btn
                      class="p-1.5 hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <%!-- Expected format hint --%>
                <div class="flex gap-3 p-4 bg-base-200/60 border border-base-300/50 text-xs text-base-content/50">
                  <.icon
                    name="hero-information-circle"
                    class="size-4 shrink-0 mt-0.5 text-base-content/35"
                  />
                  <div>
                    <p class="font-medium text-base-content/60 mb-1">Expected column headers</p>
                    <p class="font-mono leading-relaxed">
                      SchoolYear, ISDCode, ISDName, DistrictCode, DistrictName,
                      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
                      SchoolLevel, LOCALE_NAME, MISTEM_NAME, MISTEM_CODE,
                      TOTAL_ENROLLMENT, MALE_ENROLLMENT, FEMALE_ENROLLMENT,
                      AMERICAN_INDIAN_ENROLLMENT, ASIAN_ENROLLMENT,
                      AFRICAN_AMERICAN_ENROLLMENT, HISPANIC_ENROLLMENT,
                      HAWAIIAN_ENROLLMENT, WHITE_ENROLLMENT,
                      TWO_OR_MORE_RACES_ENROLLMENT, EARLY_MIDDLE_COLLEGE_ENROLLMENT,
                      PREKINDERGARTEN_ENROLLMENT, KINDERGARTEN_ENROLLMENT,
                      GRADE_1_ENROLLMENT … GRADE_12_ENROLLMENT, UNGRADED_ENROLLMENT,
                      ECONOMIC_DISADVANTAGED_ENROLLMENT, SPECIAL_EDUCATION_ENROLLMENT,
                      ENGLISH_LANGUAGE_LEARNERS_ENROLLMENT
                    </p>
                  </div>
                </div>

                <%!-- Submit button --%>
                <button
                  type="button"
                  data-import-btn
                  class={[
                    "w-full flex items-center justify-center gap-2 py-3 font-medium text-sm transition-all",
                    !@enrollment_importing && !is_nil(@enrollment_upload) &&
                      "bg-success text-success-content hover:opacity-90 active:scale-[0.99]",
                    (@enrollment_importing || is_nil(@enrollment_upload)) &&
                      "bg-success/50 text-success-content/70 cursor-not-allowed"
                  ]}
                  disabled={@enrollment_importing || is_nil(@enrollment_upload)}
                >
                  <span
                    :if={@enrollment_importing}
                    class="loading loading-spinner loading-sm"
                  >
                  </span>
                  <.icon
                    :if={!@enrollment_importing}
                    name="hero-arrow-up-tray"
                    class="size-4"
                  />
                  {if @enrollment_importing, do: "Processing…", else: "Import Enrollment"}
                </button>
              </div>
            </div>

            <%!-- Enrollment import result / status — 2 cols --%>
            <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                <div>
                  <h3 class="font-semibold">Import Status</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">Last job result</p>
                </div>
                <div
                  :if={@enrollment_importing}
                  class="flex items-center gap-1.5 text-xs text-base-content/40"
                >
                  <span class="loading loading-spinner loading-xs"></span> Running…
                </div>
              </div>

              <%!-- Idle / no result yet --%>
              <div
                :if={!@enrollment_importing && is_nil(@enrollment_import_result)}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-base-200 mb-3">
                  <.icon name="hero-users" class="size-6 text-base-content/25" />
                </div>
                <p class="text-sm font-medium text-base-content/40">No import yet</p>
                <p class="text-xs text-base-content/30 mt-1">
                  Upload an enrollment CSV to populate the enrollment table.
                </p>
              </div>

              <%!-- In-progress pulse --%>
              <div
                :if={@enrollment_importing}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-success/10 mb-3">
                  <span class="loading loading-spinner loading-md text-success"></span>
                </div>
                <p class="text-sm font-medium">Processing enrollment data…</p>
                <p class="text-xs text-base-content/40 mt-1">
                  Upserting enrollment records in the background.
                </p>
              </div>

              <%!-- Success result --%>
              <div
                :if={match?({:ok, _}, @enrollment_import_result)}
                class="p-6 space-y-4"
              >
                <div class="flex items-center gap-2 text-success">
                  <.icon name="hero-check-circle" class="size-5" />
                  <span class="font-semibold text-sm">Import completed</span>
                </div>
                <dl class="grid grid-cols-2 gap-3">
                  <.mde_stat
                    label="Records"
                    value={format_number(elem(@enrollment_import_result, 1).records)}
                    icon="hero-users"
                  />
                  <.mde_stat
                    label="Errors"
                    value={elem(@enrollment_import_result, 1).errors}
                    icon="hero-exclamation-circle"
                  />
                </dl>
                <div
                  :if={elem(@enrollment_import_result, 1).errors > 0}
                  class="flex items-center gap-2 text-xs text-warning bg-warning/5 border border-warning/15 px-3 py-2"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                  {elem(@enrollment_import_result, 1).errors} rows had errors and were skipped.
                </div>
                <a
                  :if={elem(@enrollment_import_result, 1).error_file}
                  href={~p"/admin/import/errors/download?#{%{path: elem(@enrollment_import_result, 1).error_file}}"}
                  class="flex items-center gap-2 text-xs text-warning hover:text-warning/80 bg-warning/5 border border-warning/15 px-3 py-2 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4 shrink-0" />
                  Download error rows — {Path.basename(elem(@enrollment_import_result, 1).error_file)}
                </a>
              </div>

              <%!-- Error result --%>
              <div
                :if={match?({:error, _}, @enrollment_import_result)}
                class="p-6"
              >
                <div class="flex items-start gap-3 p-4 bg-error/5 border border-error/15">
                  <.icon name="hero-x-circle" class="size-5 text-error shrink-0 mt-0.5" />
                  <div>
                    <p class="text-sm font-semibold text-error">Import failed</p>
                    <p class="text-xs text-base-content/50 mt-1 break-all">
                      {elem(@enrollment_import_result, 1)}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- ── Section 5: SAT Assessment Data (system_admin only) ──────────────── --%>
        <div class="divider"></div>
        <div :if={@current_user.role == :system_admin} class="space-y-4 p-8 shadow-xl">
          <div class="flex items-center gap-3">
            <div>
              <div class="flex items-center gap-2">
                <h2 class="text-base font-semibold">SAT Assessment Data</h2>
                <span class="badge badge-secondary badge-sm">System Admin</span>
              </div>
              <p class="text-xs text-base-content/50 mt-0.5">
                Import the MDE SAT college-readiness aggregate CSV — building, district, and
                ISD-level results by subgroup. Upserts one row per entity per school year per
                subgroup.
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-5 gap-6 items-start">
            <%!-- SAT upload form — 3 cols --%>
            <div class="lg:col-span-3 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200">
                <h3 class="font-semibold">Upload SAT CSV</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  MDE SAT aggregate export. No school or year selection needed.
                </p>
              </div>

              <div id="tigris-sat" phx-hook="TigrisUpload" data-upload-type="sat" class="p-6 space-y-6">
                <%!-- File upload drop zone --%>
                <div class="space-y-2">
                  <label class="text-sm font-medium">
                    SAT CSV File <span class="text-error text-xs">*</span>
                  </label>

                  <div
                    class="relative border-2 border-dashed border-base-300 hover:border-secondary/40 bg-base-50/50 transition-colors group cursor-pointer"
                    data-drop-zone
                  >
                    <label class="flex flex-col items-center justify-center py-10 px-6 text-center cursor-pointer">
                      <div class="p-3 bg-base-200 group-hover:bg-secondary/10 transition-colors mb-3">
                        <.icon
                          name="hero-academic-cap"
                          class="size-7 text-base-content/30 group-hover:text-secondary transition-colors"
                        />
                      </div>
                      <p class="text-sm text-base-content/50">
                        Drag & drop the SAT CSV here, or{" "}
                        <span class="text-secondary font-medium hover:underline">browse</span>
                      </p>
                      <p class="text-xs text-base-content/30 mt-1">CSV files up to 250 MB</p>
                      <input type="file" accept=".csv" class="hidden" data-file-input />
                    </label>
                  </div>

                  <%!-- File entry preview --%>
                  <div
                    :if={@sat_upload}
                    class="flex items-center gap-3 p-3 border border-base-200 bg-base-50"
                  >
                    <div class="p-2 bg-secondary/10 shrink-0">
                      <.icon name="hero-document-text" class="size-4 text-secondary" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium truncate">{@sat_upload.name}</div>
                      <div class="w-full bg-base-200 rounded-full h-1 mt-1.5">
                        <div
                          class="bg-secondary h-1 rounded-full transition-all duration-300"
                          style={"width: #{@sat_upload_progress || 0}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <span class="text-xs text-base-content/40 shrink-0">
                      {format_bytes(@sat_upload.size)}
                    </span>
                    <button
                      type="button"
                      data-cancel-btn
                      class="p-1.5 hover:bg-error/10 text-base-content/30 hover:text-error transition-colors"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <%!-- Expected format hint --%>
                <div class="flex gap-3 p-4 bg-base-200/60 border border-base-300/50 text-xs text-base-content/50">
                  <.icon
                    name="hero-information-circle"
                    class="size-4 shrink-0 mt-0.5 text-base-content/35"
                  />
                  <div>
                    <p class="font-medium text-base-content/60 mb-1">Expected column headers</p>
                    <p class="font-mono leading-relaxed">
                      SchoolYear, ISDCode, ISDName, DistrictCode, DistrictName,
                      BuildingCode, BuildingName, CountyCode, CountyName, EntityType,
                      SchoolLevel, Locale, MISTEM_NAME, MISTEM_CODE, Subgroup,
                      MathPercentReady, MathNumAssessed, MathScoreAverage, MathCountReady,
                      ReadingPercentReady … EBRWCountReady
                    </p>
                  </div>
                </div>

                <%!-- Submit button --%>
                <button
                  type="button"
                  data-import-btn
                  class={[
                    "w-full flex items-center justify-center gap-2 py-3 font-medium text-sm transition-all",
                    !@sat_importing && !is_nil(@sat_upload) &&
                      "bg-secondary text-secondary-content hover:opacity-90 active:scale-[0.99]",
                    (@sat_importing || is_nil(@sat_upload)) &&
                      "bg-secondary/50 text-secondary-content/70 cursor-not-allowed"
                  ]}
                  disabled={@sat_importing || is_nil(@sat_upload)}
                >
                  <span
                    :if={@sat_importing}
                    class="loading loading-spinner loading-sm"
                  >
                  </span>
                  <.icon
                    :if={!@sat_importing}
                    name="hero-arrow-up-tray"
                    class="size-4"
                  />
                  {if @sat_importing, do: "Processing…", else: "Import SAT Data"}
                </button>
              </div>
            </div>

            <%!-- SAT import result / status — 2 cols --%>
            <div class="lg:col-span-2 bg-base-100 border border-base-200 overflow-hidden">
              <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                <div>
                  <h3 class="font-semibold">Import Status</h3>
                  <p class="text-xs text-base-content/40 mt-0.5">Last job result</p>
                </div>
                <div
                  :if={@sat_importing}
                  class="flex items-center gap-1.5 text-xs text-base-content/40"
                >
                  <span class="loading loading-spinner loading-xs"></span> Running…
                </div>
              </div>

              <%!-- Idle / no result yet --%>
              <div
                :if={!@sat_importing && is_nil(@sat_import_result)}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-base-200 mb-3">
                  <.icon name="hero-academic-cap" class="size-6 text-base-content/25" />
                </div>
                <p class="text-sm font-medium text-base-content/40">No import yet</p>
                <p class="text-xs text-base-content/30 mt-1">
                  Upload a SAT CSV to populate the results table.
                </p>
              </div>

              <%!-- In-progress pulse --%>
              <div
                :if={@sat_importing}
                class="flex flex-col items-center justify-center py-16 px-6 text-center"
              >
                <div class="p-3 bg-secondary/10 mb-3">
                  <span class="loading loading-spinner loading-md text-secondary"></span>
                </div>
                <p class="text-sm font-medium">Processing SAT data…</p>
                <p class="text-xs text-base-content/40 mt-1">
                  Upserting SAT results in the background.
                </p>
              </div>

              <%!-- Success result --%>
              <div
                :if={match?({:ok, _}, @sat_import_result)}
                class="p-6 space-y-4"
              >
                <div class="flex items-center gap-2 text-success">
                  <.icon name="hero-check-circle" class="size-5" />
                  <span class="font-semibold text-sm">Import completed</span>
                </div>
                <dl class="grid grid-cols-2 gap-3">
                  <.mde_stat
                    label="Records"
                    value={format_number(elem(@sat_import_result, 1).records)}
                    icon="hero-academic-cap"
                  />
                  <.mde_stat
                    label="Errors"
                    value={elem(@sat_import_result, 1).errors}
                    icon="hero-exclamation-circle"
                  />
                </dl>
                <div
                  :if={elem(@sat_import_result, 1).errors > 0}
                  class="flex items-center gap-2 text-xs text-warning bg-warning/5 border border-warning/15 px-3 py-2"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                  {elem(@sat_import_result, 1).errors} rows had errors and were skipped.
                </div>
                <a
                  :if={elem(@sat_import_result, 1).error_file}
                  href={~p"/admin/import/errors/download?#{%{path: elem(@sat_import_result, 1).error_file}}"}
                  class="flex items-center gap-2 text-xs text-warning hover:text-warning/80 bg-warning/5 border border-warning/15 px-3 py-2 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="size-4 shrink-0" />
                  Download error rows — {Path.basename(elem(@sat_import_result, 1).error_file)}
                </a>
              </div>

              <%!-- Error result --%>
              <div
                :if={match?({:error, _}, @sat_import_result)}
                class="p-6"
              >
                <div class="flex items-start gap-3 p-4 bg-error/5 border border-error/15">
                  <.icon name="hero-x-circle" class="size-5 text-error shrink-0 mt-0.5" />
                  <div>
                    <p class="text-sm font-semibold text-error">Import failed</p>
                    <p class="text-xs text-base-content/50 mt-1 break-all">
                      {elem(@sat_import_result, 1)}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <%!-- ── Section 6: MDE Import History (system_admin only) ──────────────── --%>
        <div :if={@current_user.role == :system_admin} class="space-y-4">
          <div class="divider"></div>
          <div class="flex items-center gap-2">
            <h2 class="text-base font-semibold">Import History</h2>
            <span class="badge badge-ghost badge-sm">MDE Imports</span>
          </div>

          <div class="bg-base-100 border border-base-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-base-200">
              <h3 class="font-semibold">Recent MDE Uploads</h3>
              <p class="text-xs text-base-content/40 mt-0.5">Last 50 imports across all MDE data types</p>
            </div>

            <div
              :if={@import_history == []}
              class="flex flex-col items-center justify-center py-16 px-6 text-center"
            >
              <div class="p-3 bg-base-200 mb-3">
                <.icon name="hero-inbox" class="size-6 text-base-content/25" />
              </div>
              <p class="text-sm font-medium text-base-content/40">No import history yet</p>
              <p class="text-xs text-base-content/30 mt-1">MDE uploads will appear here once submitted.</p>
            </div>

            <div :if={@import_history != []} class="overflow-x-auto">
              <table class="table table-sm w-full">
                <thead>
                  <tr class="text-xs text-base-content/50 border-b border-base-200">
                    <th class="px-4 py-3 font-medium">Type</th>
                    <th class="px-4 py-3 font-medium">File</th>
                    <th class="px-4 py-3 font-medium">Size</th>
                    <th class="px-4 py-3 font-medium">Status</th>
                    <th class="px-4 py-3 font-medium">Records</th>
                    <th class="px-4 py-3 font-medium">Errors</th>
                    <th class="px-4 py-3 font-medium">School Year</th>
                    <th class="px-4 py-3 font-medium">Uploaded By</th>
                    <th class="px-4 py-3 font-medium">Date</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200">
                  <tr
                    :for={log <- @import_history}
                    class="hover:bg-base-50 transition-colors text-sm"
                  >
                    <td class="px-4 py-3">
                      <span class={[
                        "badge badge-sm font-medium",
                        log.import_type == :mde && "badge-warning",
                        log.import_type == :entity_master && "badge-info",
                        log.import_type == :enrollment && "badge-success",
                        log.import_type == :sat && "badge-secondary"
                      ]}>
                        {log.import_type |> to_string() |> String.replace("_", " ") |> String.upcase()}
                      </span>
                    </td>
                    <td class="px-4 py-3 max-w-[200px] truncate font-mono text-xs">
                      {log.original_filename}
                    </td>
                    <td class="px-4 py-3 text-base-content/60">
                      {format_bytes(log.file_size_bytes)}
                    </td>
                    <td class="px-4 py-3">
                      <.import_status_badge status={log.status} />
                    </td>
                    <td class="px-4 py-3 tabular-nums">
                      {if log.records_processed, do: format_number(log.records_processed), else: "—"}
                    </td>
                    <td class={["px-4 py-3 tabular-nums", log.error_count && log.error_count > 0 && "text-error"]}>
                      {if log.error_count, do: log.error_count, else: "—"}
                    </td>
                    <td class="px-4 py-3 text-base-content/60">
                      {log.school_year || "—"}
                    </td>
                    <td class="px-4 py-3 text-base-content/60 text-xs">
                      {if log.uploaded_by, do: log.uploaded_by.email, else: "—"}
                    </td>
                    <td class="px-4 py-3 text-base-content/50 text-xs whitespace-nowrap">
                      {format_datetime(log.inserted_at)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  def sync_status_dot(assigns) do
    ~H"""
    <span
      :if={@status == :pending}
      class="inline-block size-2 rounded-full bg-base-300 shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :running}
      class="inline-block size-2 rounded-full bg-info animate-pulse shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :completed}
      class="inline-block size-2 rounded-full bg-success shrink-0 mt-0.5"
    >
    </span>
    <span
      :if={@status == :failed}
      class="inline-block size-2 rounded-full bg-error shrink-0 mt-0.5"
    >
    </span>
    """
  end

  def sync_status_badge(assigns) do
    ~H"""
    <span :if={@status == :pending} class="badge badge-ghost badge-sm">Pending</span>
    <span :if={@status == :running} class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span> Running
    </span>
    <span :if={@status == :completed} class="badge badge-success badge-sm">Completed</span>
    <span :if={@status == :failed} class="badge badge-error badge-sm">Failed</span>
    """
  end

  def mde_stat(assigns) do
    ~H"""
    <div class="flex flex-col gap-0.5 p-3 bg-base-50 border border-base-200">
      <span class="text-xs text-base-content/40 flex items-center gap-1">
        <.icon name={@icon} class="size-3" /> {@label}
      </span>
      <span class="text-lg font-bold tabular-nums">{@value}</span>
    </div>
    """
  end

  def import_status_badge(assigns) do
    ~H"""
    <span :if={@status == :uploading} class="badge badge-ghost badge-sm">Uploading</span>
    <span :if={@status == :processing} class="badge badge-info badge-sm gap-1">
      <span class="loading loading-spinner loading-xs"></span> Processing
    </span>
    <span :if={@status == :completed} class="badge badge-success badge-sm">Completed</span>
    <span :if={@status == :failed} class="badge badge-error badge-sm">Failed</span>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp load_recent_logs(nil, _user), do: []

  defp load_recent_logs(oid, user) do
    Emisint.Analytics.DataSyncLog
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.Query.limit(20)
    |> Ash.read!(tenant: oid, actor: user)
  end

  defp parse_csv(content) do
    lines = String.split(content, ~r/\r?\n/, trim: true)

    case lines do
      [] ->
        []

      [_header] ->
        []

      [header_line | data_lines] ->
        headers =
          header_line
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        Enum.map(data_lines, fn line ->
          values = String.split(line, ",") |> Enum.map(&String.trim/1)
          headers |> Enum.zip(values) |> Map.new()
        end)
    end
  end

  defp format_bytes(nil), do: ""

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end

  defp format_number(n), do: to_string(n)

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end

  defp upload_error_msg(:too_large), do: "File is too large (max 300MB for MDE / 10MB for other)"
  defp upload_error_msg(:not_accepted), do: "Only CSV files are accepted"
  defp upload_error_msg(:too_many_files), do: "Only one file allowed"
  defp upload_error_msg(err), do: inspect(err)

  defp load_import_history do
    Emisint.Assessments.MdeImportLog
    |> Ash.Query.for_read(:list_recent)
    |> Ash.read!(authorize?: false, load: [:uploaded_by])
  rescue
    _ -> []
  end

  defp create_import_log(import_type, filename, upload_assign, s3_key, user) do
    attrs = %{
      import_type: import_type,
      original_filename: filename,
      file_size_bytes: upload_assign && upload_assign.size,
      s3_key: s3_key,
      status: :processing,
      uploaded_by_id: user.id
    }

    case Ash.create(Emisint.Assessments.MdeImportLog, attrs, authorize?: false) do
      {:ok, log} -> log.id
      _ -> nil
    end
  end
end
