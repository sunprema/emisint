defmodule Emisint.Repo.Migrations.NormalizeBuildingCodes do
  @moduledoc """
  Strip leading zeros from mde_buildings.building_code values that were imported
  before the normalize_entity_code step was applied.

  For rows where trimming leading zeros creates a conflict (a normalized version
  already exists), child references in mde_state_assessment_results are re-pointed
  to the canonical row before the stale duplicate is deleted.
  """

  use Ecto.Migration

  def up do
    # Step 1: Re-point assessment result rows that reference an un-normalized
    # building to the canonical (already-normalized) building record.
    execute("""
    UPDATE mde_state_assessment_results AS r
    SET mde_building_id = canonical.id
    FROM mde_buildings AS stale
    JOIN mde_buildings AS canonical
      ON ltrim(stale.building_code, '0') = canonical.building_code
      AND stale.building_code != canonical.building_code
    WHERE r.mde_building_id = stale.id;
    """)

    # Step 2: Now that children have been re-pointed, delete un-normalized
    # duplicates that have a canonical counterpart.
    execute("""
    DELETE FROM mde_buildings AS stale
    USING mde_buildings AS canonical
    WHERE
      stale.building_code != canonical.building_code
      AND ltrim(stale.building_code, '0') = canonical.building_code
      AND stale.id != canonical.id;
    """)

    # Step 3: Strip leading zeros from any remaining un-normalized codes that
    # had no canonical counterpart (safe to rename in place).
    execute("""
    UPDATE mde_buildings
    SET building_code = ltrim(building_code, '0')
    WHERE building_code ~ '^0+[1-9]';
    """)
  end

  def down do
    # Not reversible — leading zeros cannot be reliably restored.
    :ok
  end
end
