defmodule Emisint.Reports.School.ComprehensivePdf do
  @template_path "priv/typst/school/comprehensive.typ"

  @doc """
  Generates a PDF binary for the given school id.

  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  def generate_report(school_id, scope, opts \\ []) do
    template = File.read!(Application.app_dir(:emisint, @template_path))
    data = %{}
    config = Imprintor.Config.new(template, data)
    Imprintor.compile_to_pdf(config)
  end
end
