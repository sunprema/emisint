defmodule Emisint.Improvement.Changes.InheritScope do
  @moduledoc """
  Loads a parent record **inside the changeset's tenant** and copies scope
  attributes from it, so callers never supply `school_id`/`goal_plan_id`
  directly. A parent ID belonging to another organization is reported as not
  found.

  Options:

    * `:from`     — attribute holding the parent ID (e.g. `:goal_id`)
    * `:resource` — parent resource module
    * `:copy`     — keyword of `target_attribute: parent_field` (may be `[]`
                    to only validate that the parent exists)
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    from = Keyword.fetch!(opts, :from)

    case Ash.Changeset.get_attribute(changeset, from) do
      nil ->
        changeset

      parent_id ->
        case Ash.get(Keyword.fetch!(opts, :resource), parent_id,
               tenant: changeset.tenant,
               authorize?: false
             ) do
          {:ok, parent} ->
            Enum.reduce(Keyword.get(opts, :copy, []), changeset, fn {target, field}, acc ->
              Ash.Changeset.force_change_attribute(acc, target, Map.fetch!(parent, field))
            end)

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: from,
              message: "does not exist in this organization"
            )
        end
    end
  end
end
