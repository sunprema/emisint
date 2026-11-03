defmodule Emisint.Improvement.Pilot do
  @moduledoc """
  The ND First schools included in the current release, configured by verified
  ND InstitutionID:

      config :emisint, :nd_first, pilot_institution_ids: ["4300429212"]

  Only these schools are listed on the ND First landing page and offered by
  the ND Insights import UI. Other schools' records are kept for later
  expansion. Without the setting, no school is included.
  """

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
end
