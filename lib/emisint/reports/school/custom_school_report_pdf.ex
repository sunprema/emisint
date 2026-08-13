defmodule Emisint.Reports.School.CustomSchoolReportPdf do
  @moduledoc "Generates a real-data-only school report using a registered visual preset."

  alias Emisint.Reports.School.{
    ReportSectionRegistry,
    ReportTemplateRegistry,
    SchoolReportData
  }

  def generate_report(building_code, year, template_key, opts \\ []) do
    with {:ok, template} <- ReportTemplateRegistry.fetch(template_key),
         {:ok, sections} <- ReportSectionRegistry.normalize(Keyword.get(opts, :sections)) do
      source = File.read!(Application.app_dir(:emisint, template.template_path))

      data =
        building_code
        |> SchoolReportData.load(year)
        |> Map.put(:sections, ReportSectionRegistry.flags(sections))

      config =
        Imprintor.Config.new(source, data,
          root_directory: Application.app_dir(:emisint, "priv/typst")
        )

      Imprintor.compile_to_pdf(config)
    end
  end
end
