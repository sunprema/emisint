defmodule Emisint.Improvement.Changes.SetActor do
  @moduledoc """
  Sets an attribute to the actor's ID on the server side. The attribute is
  never accepted as input, so clients cannot claim another author.

  Options:

    * `:attribute` — attribute to set (e.g. `:author_id`)
    * `:required?` — add an error when there is no actor (default `false`)
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    attribute = Keyword.fetch!(opts, :attribute)

    case context.actor do
      %{id: id} ->
        Ash.Changeset.force_change_attribute(changeset, attribute, id)

      _ ->
        if opts[:required?] do
          Ash.Changeset.add_error(changeset,
            field: attribute,
            message: "requires a signed-in user"
          )
        else
          changeset
        end
    end
  end
end
