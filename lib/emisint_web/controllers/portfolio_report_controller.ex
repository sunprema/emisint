defmodule EmisintWeb.PortfolioReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"agency" => agency_code, "year" => year}) do
    case Emisint.Reports.Portfolio.PortfolioPdf.generate_report(agency_code, year) do
      {:ok, pdf_binary} ->
        safe_agency = String.replace(agency_code, ~r/[^a-zA-Z0-9_-]/, "_")
        safe_year = String.replace(year, ~r/[^a-zA-Z0-9_-]/, "_")
        filename = "portfolio_#{safe_agency}_#{safe_year}.pdf"

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("Portfolio PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate PDF report.")
        |> redirect(to: ~p"/dashboard")
    end
  rescue
    e ->
      Logger.error("Portfolio PDF error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(to: ~p"/dashboard")
  end
end
