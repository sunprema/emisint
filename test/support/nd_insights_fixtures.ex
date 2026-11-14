defmodule Emisint.NdInsightsFixtures do
  @moduledoc """
  Imports ND Insights fixture files for tests and fails at the import when
  any file reports an error. `Importer.import_files/2` returns `{:ok, reports}`
  even when a file fails (the error is in that file's report), so a setup that
  only matched `{:ok, _}` let a failed import surface later as an unrelated
  assertion.

  ## Tests that import run in one group

  Every test module that imports (this helper, `Importer.import_files/2`, or
  an import from a page) declares

      use EmisintWeb.ConnCase, async: true, group: :nd_insights_import

  (or `Emisint.DataCase`). Tests in the group never run at the same time as
  each other; they still run alongside every other async test.

  Why: the ND Insights tables are global (not per organization), and an
  import takes a transaction-scoped advisory lock (`Importer.import_lock_key/0`)
  and writes rows under unique indexes (`source_files.sha256`,
  `state_results` natural key + version). Under the SQL sandbox a test is
  one transaction that is only rolled back when the test ends, so the lock
  and those index entries are held for the rest of the test, not just the
  import. A second test importing at the same time waited for the whole of
  the first test; in the full run these waits chained past DBConnection's
  15-second limit (disconnect, then `DBConnection.OwnershipError`) and
  `render_async`'s 10 seconds. `NdInsightsTestGroupTest` checks the group is
  declared. Tests that only `Ash.Seed` uniquely keyed synthetic rows take no
  lock and stay outside it.
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
