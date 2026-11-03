defmodule EmisintWeb.NdFirstSchoolReportController do
  @moduledoc """
  Individual ND First school PDF. Requires a signed-in user; the school is
  loaded as that user inside their tenant (system admins use the org they
  selected), so the school read policy decides access.
  """
  use EmisintWeb, :controller

  require Logger

  alias Emisint.Reports.School.NdFirstSchoolPdf

  def show(conn, %{"slug" => slug} = params) do
    case scope(conn) do
      nil ->
        redirect(conn, to: ~p"/sign-in")

      scope ->
        case NdFirstSchoolPdf.generate(scope, slug, params) do
          {:ok, pdf, filename} ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
            |> send_resp(200, pdf)

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "That school was not found, or you don't have access to it.")
            |> redirect(to: ~p"/school-goals")

          {:error, reason} ->
            Logger.error("ND First school PDF failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Failed to generate the PDF report.")
            |> redirect(to: ~p"/school-goals/#{slug}")
        end
    end
  end

  defp scope(conn) do
    case conn.assigns[:current_user] do
      %{role: :system_admin} = user ->
        tenant = get_session(conn, "admin_org_id") || user.organization_id
        tenant && %Emisint.Scope{current_user: user, current_tenant: tenant}

      %{organization_id: org_id} = user when not is_nil(org_id) ->
        %Emisint.Scope{current_user: user, current_tenant: org_id}

      _ ->
        nil
    end
  end
end
