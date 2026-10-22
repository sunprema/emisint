defmodule Emisint.Improvement.Percent do
  @moduledoc """
  Converts between the familiar 0–100 percentages people type and the
  normalized 0–1 proportions stored on percent metrics.

      iex> Emisint.Improvement.Percent.parse("24.5")
      {:ok, Decimal.new("0.245")}

      iex> Emisint.Improvement.Percent.format(Decimal.new("0.245"))
      "24.5%"
  """

  @hundred Decimal.new(100)

  @doc """
  Parses a 0–100 percentage (an optional trailing `%` is allowed) into a 0–1
  proportion. Blank input is `{:ok, nil}`.
  """
  @spec parse(String.t() | nil) :: {:ok, Decimal.t() | nil} | {:error, String.t()}
  def parse(nil), do: {:ok, nil}

  def parse(input) when is_binary(input) do
    trimmed = input |> String.trim() |> String.trim_trailing("%") |> String.trim()

    cond do
      trimmed == "" ->
        {:ok, nil}

      true ->
        case Decimal.parse(trimmed) do
          {number, ""} -> in_range(number)
          _ -> {:error, "must be a number between 0 and 100"}
        end
    end
  end

  defp in_range(number) do
    if Decimal.compare(number, 0) == :lt or Decimal.compare(number, @hundred) == :gt,
      do: {:error, "must be between 0 and 100"},
      else: {:ok, number |> Decimal.div(@hundred) |> Decimal.normalize()}
  end

  @doc "Formats a 0–1 proportion as a percentage with at most one decimal place."
  @spec format(Decimal.t() | nil) :: String.t() | nil
  def format(nil), do: nil
  def format(%Decimal{} = value), do: number(value) <> "%"

  @doc "Formats a 0–1 proportion as a 0–100 number without the `%` sign (for form inputs)."
  @spec number(Decimal.t() | nil) :: String.t() | nil
  def number(nil), do: nil

  def number(%Decimal{} = value) do
    value
    |> Decimal.mult(@hundred)
    |> Decimal.round(1)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
