defmodule Emisint.Improvement.Pilot do
  @moduledoc """
  The ND First schools included in the current release, configured by verified
  ND InstitutionID:

      config :emisint, :nd_first, pilot_institution_ids: ["4300429212", "0301662261"]

  Only these schools are listed on the ND First landing page, enabled in the
  school tabs and offered by the ND Insights import UI. Other schools' records
  are kept for later expansion. Without the setting, no school is included.

  `roster/0` lists the ND First participants shown as school tabs, in order.
  A participant's tab is enabled only when its InstitutionID is configured;
  the others are labeled "Coming soon" and link nowhere. Participants whose
  workbook sheet doesn't yet map to one verified building have no
  InstitutionID here (see PLAN_nd_first.md, "Expansion source audit").
  Cannon Ball is deferred and not listed.
  """

  # Tab order: the enabled pilot schools first, then the others
  # alphabetically. `institution_id` is the verified building ID from the
  # ND Insights downloads; `nil` where the building isn't settled yet.
  @roster [
    %{name: "Fort Yates", institution_id: "4300429212", slug: "fort-yates-ms"},
    %{name: "Oberon", institution_id: "0301662261", slug: "oberon-elementary"},
    %{name: "Drayton", institution_id: nil, slug: nil},
    %{name: "Dunseith", institution_id: nil, slug: nil},
    %{name: "Mandaree", institution_id: nil, slug: nil},
    %{name: "Valley Middle School", institution_id: "1800189752", slug: "valley-middle-school"},
    %{name: "Warwick", institution_id: nil, slug: nil}
  ]

  @doc "Verified ND InstitutionIDs of the pilot schools."
  @spec institution_ids() :: [String.t()]
  def institution_ids do
    :emisint
    |> Application.get_env(:nd_first, [])
    |> Keyword.get(:pilot_institution_ids, [])
  end

  @doc "Whether a school (or InstitutionID) is part of the pilot."
  def pilot?(%{state_entity_id: id}), do: pilot?(id)
  def pilot?(id) when is_binary(id), do: id in institution_ids()
  def pilot?(_), do: false

  @doc """
  The school tabs, in order: `%{name, institution_id, slug, enabled?}`. A tab
  is enabled only for a configured pilot school with a slug.
  """
  def roster do
    ids = institution_ids()

    Enum.map(@roster, fn entry ->
      Map.put(entry, :enabled?, entry.slug != nil and entry.institution_id in ids)
    end)
  end
end
