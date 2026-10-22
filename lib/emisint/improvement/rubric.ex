defmodule Emisint.Improvement.Rubric do
  @moduledoc """
  The 0–3 implementation rubric, quoted from the ND First workbook
  (`Goals Dashboard!A15:A18`).

  A 3 means "Demonstrated Progress", not "target met".
  """

  @levels [
    {3, "Demonstrated Progress",
     "Direct, measure-specific evidence shows progress consistent with the current phase or target."},
    {2, "Implementation on Track",
     "Substantial implementation is documented; direct, measure-specific evidence is pending."},
    {1, "Some Progress",
     "Relevant work has begun, but the school has not reached the implementation level planned."},
    {0, "Not Started",
     "No meaningful work toward the target or its necessary implementation pathway."}
  ]

  @doc "Rubric levels, highest first, as `{score, label, description}`."
  def levels, do: @levels

  @doc "The short label for a score, e.g. `label(3) #=> \"Demonstrated Progress\"`."
  def label(score) do
    case List.keyfind(@levels, score, 0) do
      {_, label, _} -> label
      nil -> nil
    end
  end
end
