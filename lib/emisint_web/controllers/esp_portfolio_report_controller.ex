defmodule EmisintWeb.EspPortfolioReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"emo" => emo_name, "year" => year}) do
    case Emisint.Reports.Portfolio.EspPortfolioPdf.generate_report(emo_name, year) do
      {:ok, pdf_binary} ->
        safe_emo = String.replace(emo_name, ~r/[^a-zA-Z0-9_-]/, "_")
        safe_year = String.replace(year, ~r/[^a-zA-Z0-9_-]/, "_")
        filename = "esp_portfolio_#{safe_emo}_#{safe_year}.pdf"

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("ESP Portfolio PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate PDF report.")
        |> redirect(to: ~p"/esp-portfolio")
    end
  rescue
    e ->
      Logger.error("ESP Portfolio PDF error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(to: ~p"/esp-portfolio")
  end
end
