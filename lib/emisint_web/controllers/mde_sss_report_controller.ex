defmodule EmisintWeb.MdeSssReportController do
  use EmisintWeb, :controller

  require Logger

  def show(conn, %{"school_code" => school_code, "year" => year, "district_code" => district_code}) do
    case Emisint.Reports.School.SssComparisonPdf.generate_report(school_code, year) do
      {:ok, pdf_binary} ->
        filename = "sss_comparison_#{school_code}_#{year}.pdf"

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        Logger.error("SSS comparison PDF generation failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to generate report: #{inspect(reason)}")
        |> redirect(
          to: ~p"/mde/districts/#{district_code}?tab=sss_comparison&building=#{school_code}"
        )
    end
  rescue
    e ->
      Logger.error("SSS comparison report error: #{Exception.message(e)}")

      conn
      |> put_flash(:error, "Report error: #{Exception.message(e)}")
      |> redirect(
        to: ~p"/mde/districts/#{district_code}?tab=sss_comparison&building=#{school_code}"
      )
  end
end
