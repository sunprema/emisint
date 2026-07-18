defmodule Emisint.Assessments.EmoPortfolio do
  @moduledoc """
  Resolves the school list for a management organization (ESP Portfolio),
  combining the MdeEmoContact-derived base list with manual
  `EmoSchoolOverride` add/remove decisions. Shared by the ESP Portfolio
  LiveView and its PDF export so the two can't drift out of sync with each
  other.
  """

  require Ash.Query

  alias Emisint.Assessments
  alias Emisint.Assessments.{MdeEmoContact, MdeEntityMaster}

  @school_select [
    :entity_code,
    :entity_official_name,
    :district_code,
    :entity_county_name,
    :entity_actual_grades,
    :entity_authorized_grades
  ]

  @doc """
  Returns `{schools, contact_map}` for `management_organization`: the
  MdeEmoContact-derived base school list with any EmoSchoolOverride
  add/remove rows applied on top.
  """
  def resolve_schools(management_organization) do
    contacts =
      MdeEmoContact
      |> Ash.Query.filter(management_organization == ^management_organization)
      |> Ash.read!(authorize?: false)

    district_codes = contacts |> Enum.map(& &1.district_code) |> Enum.reject(&is_nil/1)

    contact_map =
      Map.new(contacts, fn c ->
        {c.district_code,
         %{
           contact_name: c.contact_name,
           contact_email: c.contact_email,
           contact_phone: c.contact_phone
         }}
      end)

    base_schools = load_entities_by_district(district_codes)

    overrides =
      Assessments.list_emo_school_overrides_for_org!(management_organization, authorize?: false)

    remove_codes =
      overrides
      |> Enum.filter(&(&1.action == :remove))
      |> Enum.map(& &1.entity_code)
      |> MapSet.new()

    add_codes =
      overrides |> Enum.filter(&(&1.action == :add)) |> Enum.map(& &1.entity_code) |> MapSet.new()

    kept_base = Enum.reject(base_schools, &MapSet.member?(remove_codes, &1.entity_code))

    already_present = kept_base |> Enum.map(& &1.entity_code) |> MapSet.new()
    codes_to_fetch = add_codes |> MapSet.difference(already_present) |> MapSet.to_list()

    added_schools = load_entities_by_code(codes_to_fetch)

    schools =
      (kept_base ++ added_schools)
      |> Enum.uniq_by(& &1.entity_code)
      |> Enum.sort_by(& &1.entity_official_name)

    {schools, contact_map}
  rescue
    _ -> {[], %{}}
  end

  @doc """
  Current EmoSchoolOverride rows for `management_organization`, as a map of
  `entity_code => :add | :remove`, for UI display.
  """
  def overrides_map(management_organization) do
    management_organization
    |> Assessments.list_emo_school_overrides_for_org!(authorize?: false)
    |> Map.new(&{&1.entity_code, &1.action})
  rescue
    _ -> %{}
  end

  @doc """
  Search Open-Active entities by name or code, for the "add a school" picker.
  Excludes entities already in `exclude_codes`.
  """
  def search_entities(search, exclude_codes \\ [])

  def search_entities("", _exclude_codes), do: []

  def search_entities(search, exclude_codes) do
    like = "%#{search}%"

    MdeEntityMaster
    |> Ash.Query.filter(
      entity_status == "Open-Active" and
        (ilike(entity_official_name, ^like) or ilike(entity_code, ^like)) and
        entity_code not in ^exclude_codes
    )
    |> Ash.Query.select(@school_select)
    |> Ash.Query.sort(entity_official_name: :asc)
    |> Ash.Query.limit(20)
    |> Ash.read!(authorize?: false)
  rescue
    _ -> []
  end

  @doc """
  Marks `entity_code` as manually added to `management_organization`'s
  portfolio. Authorization is enforced by `EmoSchoolOverride`'s own
  policies (system_admin only) via `actor`.
  """
  def add_school(management_organization, entity_code, actor) do
    Assessments.upsert_emo_school_override(
      %{management_organization: management_organization, entity_code: entity_code, action: :add},
      actor: actor
    )
  end

  @doc """
  Marks `entity_code` as manually removed from `management_organization`'s
  portfolio (excluded even though district-code matching would include it).
  """
  def remove_school(management_organization, entity_code, actor) do
    Assessments.upsert_emo_school_override(
      %{
        management_organization: management_organization,
        entity_code: entity_code,
        action: :remove
      },
      actor: actor
    )
  end

  @doc """
  Clears a manual override for `entity_code`, reverting it to whatever the
  default MdeEmoContact-derived membership would be.
  """
  def revert_override(management_organization, entity_code, actor) do
    management_organization
    |> Assessments.list_emo_school_overrides_for_org!(authorize?: false)
    |> Enum.find(&(&1.entity_code == entity_code))
    |> case do
      nil -> :ok
      override -> Assessments.destroy_emo_school_override(override, actor: actor)
    end
  end

  defp load_entities_by_district([]), do: []

  defp load_entities_by_district(district_codes) do
    MdeEntityMaster
    |> Ash.Query.filter(district_code in ^district_codes and entity_status == "Open-Active")
    |> Ash.Query.select(@school_select)
    |> Ash.read!(authorize?: false)
  end

  defp load_entities_by_code([]), do: []

  defp load_entities_by_code(entity_codes) do
    MdeEntityMaster
    |> Ash.Query.filter(entity_code in ^entity_codes and entity_status == "Open-Active")
    |> Ash.Query.select(@school_select)
    |> Ash.read!(authorize?: false)
  end
end
