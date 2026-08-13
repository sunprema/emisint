defmodule Emisint.Reports.School.ReportTemplateRegistry do
  @moduledoc """
  Code-owned registry of supported school-report presentation presets.

  Keys are part of the report-generation URL, so they remain stable even
  though template choices are intentionally not persisted. Templates consume
  the same payload from `SchoolReportData`.
  """

  @default_key :compact_portrait
  @templates [
    %{
      key: :compact_portrait,
      name: "Compact Portrait",
      description: "A condensed portrait layout for quick review and printed packets.",
      page_description: "US Letter portrait / section-driven length",
      template_path: "priv/typst/school/custom_compact_report.typ"
    },
    %{
      key: :detailed_landscape,
      name: "Detailed Landscape",
      description: "A spacious landscape layout for deeper performance conversations.",
      page_description: "US Letter landscape / section-driven length",
      template_path: "priv/typst/school/detailed_school_report.typ"
    }
  ]

  def list, do: @templates
  def default_key, do: @default_key

  def fetch(key) when is_binary(key) do
    @templates |> Enum.find(&(Atom.to_string(&1.key) == key)) |> result()
  end

  def fetch(key) when is_atom(key), do: @templates |> Enum.find(&(&1.key == key)) |> result()
  def fetch(_key), do: {:error, :unknown_template}

  defp result(nil), do: {:error, :unknown_template}
  defp result(template), do: {:ok, template}
end
