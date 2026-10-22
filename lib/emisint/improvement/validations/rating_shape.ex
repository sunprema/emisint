defmodule Emisint.Improvement.Validations.RatingShape do
  @moduledoc """
  Enforces the `ImplementationRating` fields for its `rating_state`:

    * `:rated`          — `score` 0–3 required
    * `:not_applicable` — no score
    * `:unavailable`    — no score; `notes` must explain why
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    score = Ash.Changeset.get_attribute(changeset, :score)
    notes = Ash.Changeset.get_attribute(changeset, :notes)

    case {Ash.Changeset.get_attribute(changeset, :rating_state), score} do
      {:rated, nil} ->
        {:error, field: :score, message: "is required for a rating"}

      {state, score} when state in [:not_applicable, :unavailable] and not is_nil(score) ->
        {:error, field: :score, message: "must be blank when the rating is #{state}"}

      {:unavailable, nil} when notes in [nil, ""] ->
        {:error, field: :notes, message: "must explain why the rating is unavailable"}

      _ ->
        :ok
    end
  end
end
