defmodule Emisint.NdInsights.NdInsightsTestGroupTest do
  @moduledoc """
  Every test module that runs an ND Insights import declares
  `group: :nd_insights_import`, so no two of them run at once (see
  `Emisint.NdInsightsFixtures` for why: under the SQL sandbox an import's
  advisory lock and unique-index rows are held until the test ends).
  """
  use ExUnit.Case, async: true

  @imports ~r/import_insights!\(|Importer\.import_files|import_now\(/
  @group ~r/^\s*use \S+, async: true, group: :nd_insights_import$/m

  test "test modules that import ND Insights files are in the import group" do
    root = Path.expand("../../..", __DIR__)

    importing =
      root
      |> Path.join("test/**/*_test.exs")
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ @imports))
      |> Enum.reject(&(&1 == __ENV__.file))

    assert length(importing) >= 13

    missing =
      for file <- importing, not (File.read!(file) =~ @group), do: Path.relative_to(file, root)

    assert missing == [],
           "add `group: :nd_insights_import` to: " <> Enum.join(missing, ", ")
  end
end
