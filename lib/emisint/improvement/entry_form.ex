defmodule Emisint.Improvement.EntryForm do
  @moduledoc """
  Turns submitted form params into an actual result or implementation rating.

  * Percent inputs are typed as 0–100 and normalized to 0–1 here.
  * With no current entry the submission is an observation (`:record`); with
    one it is a correction (`:correct`) of exactly that entry and needs a
    reason. The corrected entry's id is fixed when the form is opened, so a
    concurrent correction by someone else is rejected instead of overwritten.
  * The author, recorder, timestamp, school and organization are never taken
    from params; the actions set them on the server.

  Returns `{:ok, entry}`, `{:error, :forbidden}` or `{:error, errors}` where
  `errors` is a keyword list of `{form_field, message}`.
  """

  alias Emisint.Improvement.{ActualResult, ImplementationRating, Percent}

  @max_evidence_links 3

  def max_evidence_links, do: @max_evidence_links

  @doc "Submits an actual result for `metric` in `period`, correcting `current` if given."
  def submit_actual(scope, metric, period, current, params) do
    with {:ok, values} <- actual_values(metric, params) do
      submit(ActualResult, scope, metric, period, current, values, params)
    end
  end

  @doc "Submits an implementation rating for `metric` in `period`, correcting `current` if given."
  def submit_rating(scope, metric, period, current, params) do
    with {:ok, values} <- rating_values(params) do
      submit(ImplementationRating, scope, metric, period, current, values, params)
    end
  end

  defp submit(resource, scope, metric, period, current, values, params) do
    {action, attrs} =
      case current do
        nil ->
          {:record, Map.merge(values, %{metric_id: metric.id, reporting_period_id: period.id})}

        %{id: id} ->
          {:correct,
           Map.merge(values, %{
             corrects_id: id,
             correction_reason: blank_to_nil(params["correction_reason"])
           })}
      end

    resource
    |> Ash.Changeset.for_create(action, attrs, scope: scope)
    |> Ash.create()
    |> case do
      {:ok, entry} -> {:ok, entry}
      {:error, %Ash.Error.Forbidden{}} -> {:error, :forbidden}
      {:error, error} -> {:error, field_errors(error)}
    end
  end

  defp actual_values(metric, params) do
    state = params["value_state"]

    with {:ok, value} <- number(metric, :value, params["value"]),
         {:ok, low} <- number(metric, :range_low, params["range_low"]),
         {:ok, high} <- number(metric, :range_high, params["range_high"]),
         {:ok, date} <- date(params["measurement_date"]) do
      {:ok,
       %{
         value_state: state,
         value: if(state == "exact", do: value),
         range_low: if(state == "range", do: low),
         range_high: if(state == "range", do: high),
         suppression_reason:
           if(state == "suppressed", do: blank_to_nil(params["suppression_reason"])),
         measurement_date: date,
         notes: blank_to_nil(params["notes"]),
         evidence_links: evidence_links(params)
       }}
    end
  end

  defp rating_values(params) do
    state = params["rating_state"]

    with {:ok, date} <- date(params["measurement_date"]) do
      {:ok,
       %{
         rating_state: state,
         score: if(state == "rated", do: blank_to_nil(params["score"])),
         measurement_date: date,
         notes: blank_to_nil(params["notes"]),
         evidence_links: evidence_links(params)
       }}
    end
  end

  # Only fields shown for the chosen state are parsed, so a stale value in a
  # hidden input cannot block the submission.
  defp number(%{unit: :percent}, field, input) do
    case Percent.parse(input) do
      {:ok, value} -> {:ok, value}
      {:error, message} -> {:error, [{field, message}]}
    end
  end

  defp number(_metric, field, input) do
    case blank_to_nil(input) do
      nil ->
        {:ok, nil}

      text ->
        case Decimal.parse(String.trim(text)) do
          {number, ""} -> {:ok, number}
          _ -> {:error, [{field, "must be a number"}]}
        end
    end
  end

  defp date(input) do
    case blank_to_nil(input) do
      nil ->
        {:ok, nil}

      text ->
        case Date.from_iso8601(text) do
          {:ok, date} -> {:ok, date}
          _ -> {:error, [measurement_date: "must be a valid date"]}
        end
    end
  end

  defp evidence_links(params) do
    params
    |> Map.get("evidence", %{})
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {_, link} ->
      %{url: blank_to_nil(link["url"]), label: blank_to_nil(link["label"])}
    end)
    |> Enum.reject(&is_nil(&1.url))
    |> Enum.take(@max_evidence_links)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @base_fields [:metric_id, :reporting_period_id, :corrects_id, :school_id, :author_id]

  defp field_errors(%{errors: errors}) do
    Enum.map(errors, fn
      %{field: :corrects_id} ->
        {:base,
         "This entry was already corrected by someone else. Close this panel and reopen it to correct the latest entry."}

      error ->
        field = Map.get(error, :field)

        field =
          if field in @base_fields or is_nil(field), do: :base, else: evidence_field(field, error)

        {field, message(error)}
    end)
  end

  defp field_errors(error), do: [base: Exception.message(error)]

  defp evidence_field(:evidence_links, _error), do: :evidence

  defp evidence_field(field, %{path: [:evidence_links | _]}) when field in [:url, :label],
    do: :evidence

  defp evidence_field(field, _error), do: field

  defp message(%{message: message, vars: vars}) when is_binary(message) do
    Enum.reduce(vars || [], message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", var_to_string(value))
    end)
  end

  defp message(error), do: Exception.message(error)

  defp var_to_string(value) when is_list(value), do: Enum.map_join(value, ", ", &var_to_string/1)

  defp var_to_string(value) when is_binary(value) or is_atom(value) or is_number(value),
    do: to_string(value)

  defp var_to_string(value), do: inspect(value)
end
