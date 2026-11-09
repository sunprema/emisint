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
  the others are labeled "Coming soon" and link nowhere. A district
  participant's tab opens its participant (district) record, which links to
  its buildings' dashboards (`Seeds.Participant`). Cannon Ball (the
  workbook's "Solen" sheet, confirmed by the user) is listed last, after the
  previously confirmed order.
  """

  # One main tab per participant, in this order. `institution_id` is the
  # verified ND Insights ID of the participant's main record: the building for
  # single-building participants, the district (5-digit ID) for district
  # participants. Buildings never get their own main tab.
  @roster [
    %{name: "Fort Yates", institution_id: "4300429212", slug: "fort-yates-ms"},
    %{name: "Oberon", institution_id: "0301662261", slug: "oberon-elementary"},
    %{name: "Valley Middle", institution_id: "1800189752", slug: "valley-middle-school"},
    %{name: "Drayton", institution_id: "34019", slug: "drayton-public-school-district"},
    %{name: "Dunseith", institution_id: "40001", slug: "dunseith-public-school-district"},
    %{name: "Mandaree", institution_id: "27036", slug: "mandaree-public-school-district"},
    %{name: "Warwick", institution_id: "03029", slug: "warwick-public-school-district"},
    # The workbook's "Solen" sheet, confirmed by the user (November 9, 2026).
    %{name: "Cannon Ball", institution_id: "4300312781", slug: "cannon-ball-elementary"}
  ]

  @doc """
  Slugs of the pilot school records `scope` can read (one query, the same
  read policy as each dashboard). Navigation shows only these destinations.
  """
  def readable_slugs(scope) do
    scope
    |> Emisint.Improvement.Dashboard.list_schools(institution_ids: institution_ids())
    |> MapSet.new(& &1.slug)
  end

  @doc """
  The main tabs for a user who can read `readable` (`readable_slugs/1`): one
  per participant, in roster order, each `%{name, slug, href, enabled?}`.
  `slug` identifies the participant (its main record) and `href` is the page
  the tab opens: the participant's main record when readable, otherwise its
  first readable building. A participant with nothing readable is left out.
  Configured participants that aren't enabled stay listed as "Coming soon".
  """
  def tabs(readable) do
    Enum.flat_map(roster(), fn
      %{enabled?: false} = tab ->
        [Map.put(tab, :href, nil)]

      tab ->
        case Enum.find(participant_pages(tab.slug), &MapSet.member?(readable, &1.slug)) do
          nil -> []
          page -> [Map.put(tab, :href, page.slug)]
        end
    end)
  end

  @doc """
  The participant navigation for a district participant or one of its
  buildings, or `nil` for a single-building participant:
  `%{participant, items: [%{label, slug, current?}], provisional?}`. Only
  pages in `readable` are listed; the district comes first as "District
  overview", then its buildings in plan order.
  """
  def participant_nav(school, readable) do
    participant_slug = tab_slug(school)

    case participant_pages(participant_slug) do
      [_only] ->
        nil

      pages ->
        alias Emisint.Improvement.Seeds.Participant

        %{
          participant: hd(pages).name,
          provisional?: Participant.provisional_scope?(Participant.scope(school)),
          items:
            for page <- pages, MapSet.member?(readable, page.slug) do
              Map.put(page, :current?, page.slug == school.slug)
            end
        }
    end
  end

  # The pages of a participant, main record first: `[%{name, label, slug}]`.
  # A district participant's buildings come from its `buildings/0`, labeled
  # by building level (e.g. "Elementary School").
  defp participant_pages(participant_slug) do
    module =
      Enum.find(
        Emisint.Improvement.Seeds.available_schools(),
        &(&1.school().slug == participant_slug)
      )

    cond do
      module == nil ->
        [%{name: participant_slug, label: participant_slug, slug: participant_slug}]

      function_exported?(module, :buildings, 0) ->
        %{name: name, short_name: short} = module.school()

        [%{name: name, label: "District overview", slug: participant_slug}] ++
          Enum.map(module.buildings(), fn b ->
            %{name: bname, slug: bslug} = b.school()
            %{name: bname, label: String.replace_prefix(bname, short <> " ", ""), slug: bslug}
          end)

      true ->
        %{name: name} = module.school()
        [%{name: name, label: name, slug: participant_slug}]
    end
  end

  @doc "The roster entry (tab) a school record belongs to, by slug or participant."
  def tab_slug(school) do
    case Emisint.Improvement.Seeds.Participant.scope(school) do
      %{kind: :building, participant: participant} -> participant.school().slug
      _ -> school.slug
    end
  end

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
