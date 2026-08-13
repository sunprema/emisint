defmodule EmisintWeb.MdeBoardSummaryReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"building" => building_code, "year" => year}) do
    case Emisint.Reports.School.BoardSummaryPdf.generate_report(building_code, year) do
      {:ok, pdf_binary} ->
        filename = "board_summary_#{building_code}_#{year}.pdf"

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("Board summary PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate report: #{inspect(reason)}")
        |> redirect(to: ~p"/mde")
    end
  rescue
    e ->
      Logger.error("Board summary report error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(to: ~p"/mde")
  end
end
