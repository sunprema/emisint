defmodule Emisint.NdInsights do
  @moduledoc """
  Official North Dakota state data from Insights of North Dakota
  (https://insights.nd.gov/Data), kept separate from the Michigan `Mde*`
  datasets in `Emisint.Assessments` and from school-entered goal entries in
  `Emisint.Improvement`.

    * `SourceFile`  — one row per official download (publication version,
      SHA-256, last import report)
    * `StateResult` — one row per published measure, with every source
      dimension and the value exactly as published (exact, range or
      suppressed)

  The data is public and global (not tenant-scoped). Imports never write to
  `Improvement` entries.
  """
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.NdInsights.SourceFile do
      define :list_source_files, action: :read
    end

    resource Emisint.NdInsights.StateResult do
      define :list_state_results, action: :read
    end
  end
end
