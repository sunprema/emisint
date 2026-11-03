defmodule Emisint.Improvement.Workbook do
  @moduledoc """
  Facts about `ND First School MOU Goal Overview.xlsx` that the dashboard
  cites. Each row of 'Performance-Based Payment' names a school tab in
  column B and averages that tab's column I by the category in column A
  (`AVERAGEIF(INDIRECT("'"&$B<row>&"'!A:A"), …, INDIRECT("'"&$B<row>&"'!I:I"))`).
  """

  # 'Performance-Based Payment'!A3:B11
  @payment_rows %{
    "Example School" => 3,
    "Ft Yates Goals" => 4,
    "Solen Goals" => 5,
    "Oberon Goals" => 6,
    "Warwick Goals" => 7,
    "Mandaree Goals" => 8,
    "Dunseith Goals" => 9,
    "Drayton Goals" => 10,
    "Valley Goals" => 11
  }

  @doc "The 'Performance-Based Payment' row that averages a school tab, if known."
  def payment_row(sheet), do: Map.get(@payment_rows, sheet)

  @doc """
  The sheet and 18-month column heading cell for a metric: from
  `source_values["review_18m_heading"]` when recorded, otherwise derived from
  the metric's baseline cell (the heading is in column I of the row above the
  goal's first metric).
  """
  def review_heading(metrics) when is_list(metrics) do
    first = Enum.min_by(metrics, &row_of/1, fn -> nil end)

    case first && first.source_values["review_18m_heading"] do
      %{"cell" => cell, "raw" => raw} ->
        %{cell: cell, raw: raw, sheet: sheet_of(cell)}

      _ ->
        with %{} <- first,
             cell when is_binary(cell) <- get_in(first.source_values, ["baseline", "cell"]),
             [_, sheet, row] <- Regex.run(~r/^(.+)!D(\d+)$/, cell) do
          %{cell: "#{sheet}!I#{String.to_integer(row) - 1}", raw: nil, sheet: sheet}
        else
          _ -> nil
        end
    end
  end

  defp row_of(metric) do
    with cell when is_binary(cell) <- get_in(metric.source_values, ["baseline", "cell"]),
         [_, row] <- Regex.run(~r/!D(\d+)$/, cell) do
      String.to_integer(row)
    else
      _ -> 0
    end
  end

  defp sheet_of(cell), do: cell |> String.split("!") |> hd()
end
