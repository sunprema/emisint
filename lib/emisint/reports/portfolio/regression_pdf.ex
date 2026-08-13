defmodule Emisint.Reports.Portfolio.RegressionPdf do
  @moduledoc """
  A focused, single-purpose PDF for the ESP Portfolio "Regression" tab —
  the same `Emisint.Assessments.EdRegression` least-squares ED%-vs-performance
  analysis used by the full Portfolio Overview PDF (`EspPortfolioPdf`), but
  rendered on its own with bigger charts and a full supporting-data table,
  instead of being one small section buried in a longer combined report.
  """

  @template_path "priv/typst/portfolio/regression_report.typ"

  alias Emisint.Assessments.EdRegression
  alias Emisint.Assessments.EmoPortfolio

  def generate_report(management_organization, year, _opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = build_data(management_organization, year)

    config =
      Imprintor.Config.new(template, data,
        root_directory: Application.app_dir(:emisint, "priv/typst")
      )

    Imprintor.compile_to_pdf(config)
  end

  defp build_data(management_organization, year) do
    {schools, _contact_map} = EmoPortfolio.resolve_schools(management_organization)

    mstep_task = Task.async(fn -> EdRegression.mstep_analysis(management_organization, year) end)
    sat_task = Task.async(fn -> EdRegression.sat_analysis(management_organization, year) end)

    mstep = EdRegression.for_display(Task.await(mstep_task, :infinity), "percent")
    sat = EdRegression.for_display(Task.await(sat_task, :infinity), "score")

    %{
      agency_name: management_organization,
      school_year: year,
      report_date: Date.utc_today() |> Calendar.strftime("%B %d, %Y"),
      school_count: length(schools),
      mstep: mstep,
      sat: sat
    }
  end
end
