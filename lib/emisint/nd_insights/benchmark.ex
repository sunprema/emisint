defmodule Emisint.NdInsights.Benchmark do
  @moduledoc """
  The official statewide rows ND Insights publishes as InstitutionID `99999`,
  "State of North Dakota". Verified in the 2021-22 to 2024-25 Assessment
  Performance, Assessment Participation and Growth Rate downloads and in the
  Engagement Survey downloads: every file has them, with no parse errors.

  They are imported as a benchmark beside pilot schools, never as a school:
  there is no `schools` record, tile or school import for this ID. Rows are
  accepted as the benchmark only when the file names the institution
  "State of North Dakota".
  """

  @state_id "99999"
  @state_name "State of North Dakota"

  def state_id, do: @state_id
  def state_name, do: @state_name

  def state?(id), do: id == @state_id
end
