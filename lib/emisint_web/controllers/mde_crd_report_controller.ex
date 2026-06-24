defmodule EmisintWeb.MdeCrdReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"district_code" => district_code, "year" => year}) do
    case Emisint.Reports.School.CrdComparisonPdf.generate_report(district_code, year) do
      {:ok, pdf_binary} ->
        filename = "crd_comparison_#{district_code}_#{year}.pdf"

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("CRD comparison PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate report: #{inspect(reason)}")
        |> redirect(to: ~p"/mde/districts/#{district_code}?tab=crd_comparison")
    end
  rescue
    e ->
      Logger.error("CRD comparison report error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(to: ~p"/mde/districts/#{district_code}?tab=crd_comparison")
  end
end
