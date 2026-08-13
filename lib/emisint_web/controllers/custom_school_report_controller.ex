defmodule EmisintWeb.CustomSchoolReportController do
  use EmisintWeb, :controller

  require Logger

  alias Emisint.Reports.School.{
    CustomSchoolReportPdf,
    ReportSectionRegistry,
    ReportTemplateRegistry
  }

  def show(conn, %{"building" => building_code, "year" => year} = params) do
    with {:ok, template_key} <- resolve_template(params),
         {:ok, sections} <- ReportSectionRegistry.normalize(Map.get(params, "sections")),
         {:ok, pdf_binary} <-
           CustomSchoolReportPdf.generate_report(building_code, year, template_key,
             sections: sections
           ) do
      filename = "school_report_#{building_code}_#{template_key}_#{year}.pdf"

      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
      |> send_resp(200, pdf_binary)
    else
      {:error, :unknown_template} ->
        conn |> put_status(:bad_request) |> text("Unknown school report template")

      {:error, :unknown_section} ->
        conn |> put_status(:bad_request) |> text("Unknown school report section")

      {:error, reason} ->
        Logger.error("Custom school report PDF generation failed: #{inspect(reason)}")
        conn |> put_status(:internal_server_error) |> text("Report generation failed")
    end
  rescue
    error ->
      Logger.error("Custom school report error: #{Exception.message(error)}")
      conn |> put_status(:internal_server_error) |> text("Report generation failed")
  end

  def show(conn, _params),
    do: conn |> put_status(:bad_request) |> text("Building and year are required")

  defp resolve_template(%{"template" => template_key}) do
    with {:ok, template} <- ReportTemplateRegistry.fetch(template_key), do: {:ok, template.key}
  end

  defp resolve_template(_params), do: {:ok, ReportTemplateRegistry.default_key()}
end
