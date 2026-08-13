defmodule Emisint.Reports.School.ReportSectionRegistry do
  @moduledoc """
  Complete section catalog for customizable school reports.

  Selections are request-scoped and are not persisted. Availability describes
  the current normalized data contract; unavailable sections remain selectable
  and render an honest unavailable state instead of legacy sample values.
  """

  @sections [
    %{
      key: :school_profile,
      name: "School profile",
      description: "Address, grades served, year opened, ISD, and authorizer.",
      availability: :real
    },
    %{
      key: :mission_statement,
      name: "Mission statement",
      description: "The school's published mission statement.",
      availability: :unavailable
    },
    %{
      key: :charter_contract,
      name: "Charter contract and ESP",
      description: "Contract term, expiration, and educational service provider.",
      availability: :unavailable
    },
    %{
      key: :board_roster,
      name: "Board roster",
      description: "Board members, roles, appointment dates, and term end dates.",
      availability: :unavailable
    },
    %{
      key: :performance_overview,
      name: "Performance overview",
      description:
        "Academic achievement and growth status; compliance and financial status when available.",
      availability: :partial
    },
    %{
      key: :enrollment_demographics,
      name: "Enrollment and demographics",
      description: "Total enrollment and current demographic subgroup percentages.",
      availability: :real
    },
    %{
      key: :resident_districts,
      name: "Resident districts",
      description: "Student distribution across resident school districts.",
      availability: :real
    },
    %{
      key: :sss_peer_roster,
      name: "Statistically similar schools",
      description: "SSS peer roster and distance information when normalized.",
      availability: :unavailable
    },
    %{
      key: :accountability,
      name: "Accountability indicators",
      description: "School Index, assessment participation, and support category.",
      availability: :real
    },
    %{
      key: :academic_trends,
      name: "Achievement and growth trends",
      description: "Multi-year peer-relative achievement and growth trends.",
      availability: :unavailable
    },
    %{
      key: :proficiency_trends,
      name: "Proficiency trends",
      description: "Multi-year ELA and mathematics proficiency trends.",
      availability: :unavailable
    },
    %{
      key: :academic_compliance_appendix,
      name: "Academic and compliance appendix",
      description: "Measure definitions and performance-condition guidance.",
      availability: :reference
    },
    %{
      key: :financial_testing_appendix,
      name: "Financial and testing appendix",
      description: "Financial-condition definitions and Michigan tests by grade.",
      availability: :reference
    }
  ]

  def list, do: @sections
  def default_keys, do: Enum.map(@sections, & &1.key)

  def normalize(nil), do: {:ok, default_keys()}

  def normalize(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> normalize()
  end

  def normalize(values) when is_list(values) do
    requested = MapSet.new(values, &to_key/1)
    known = MapSet.new(default_keys())

    if MapSet.subset?(requested, known) and not MapSet.member?(requested, :unknown) do
      {:ok, Enum.filter(default_keys(), &MapSet.member?(requested, &1))}
    else
      {:error, :unknown_section}
    end
  end

  def normalize(_value), do: {:error, :unknown_section}

  def flags(keys) do
    selected = MapSet.new(keys)
    Map.new(default_keys(), &{&1, MapSet.member?(selected, &1)})
  end

  defp to_key(value) when is_atom(value) do
    if value in default_keys(), do: value, else: :unknown
  end

  defp to_key(value) when is_binary(value) do
    Enum.find(default_keys(), :unknown, &(Atom.to_string(&1) == value))
  end

  defp to_key(_value), do: :unknown
end
