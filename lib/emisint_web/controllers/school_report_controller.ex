defmodule EmisintWeb.SchoolReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"school_id" => school_id}) do
    scope = conn.assigns[:scope]
    IO.inspect(scope, label: "Scope from School Report Controller")

    case Emisint.Reports.School.ComprehensivePdf.generate_report(school_id, scope) do
      {:ok, pdf_binary} ->
        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header(
          "content-disposition",
          ~s(inline; filename="#{school_id}.pdf")
        )
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("Comprehensive PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate invoice: #{inspect(reason)}")
        |> redirect(to: ~p"/schools/#{school_id}")
    end
  rescue
    e ->
      Logger.error("Report error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(to: ~p"/schools/#{school_id}")
  end
end
