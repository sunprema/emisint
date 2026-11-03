defmodule Emisint.NdInsightsFixtures do
  @moduledoc """
  Imports ND Insights fixture files for tests and fails at the import when
  any file reports an error. `Importer.import_files/2` returns `{:ok, reports}`
  even when a file fails (the error is in that file's report), so a setup that
  only matched `{:ok, _}` let a failed import surface later as an unrelated
  assertion.
  """
  import ExUnit.Assertions

  alias Emisint.NdInsights.Importer

  def import_insights!(files, opts) do
    assert {:ok, reports} = Importer.import_files(files, opts)

    for %{error: error, file: file} <- reports do
      flunk("ND Insights fixture import failed for #{file}: #{error}")
    end

    reports
  end
end
