defmodule Emisint.Assessments do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain, AshAi]

  admin do
    show? true
  end

  tools do
    tool :list_mde_isds, Emisint.Assessments.MdeIsd, :read do
      description """
      List the MDE isd available.
      Dont pass any inputs.
      """
    end
  end

  resources do
    resource Emisint.Assessments.CompetitorData do
      define :create_competitor_data, action: :create
      define :upsert_competitor_data, action: :upsert
      define :get_competitor_data, action: :read, get_by: [:id]
      define :list_competitor_data, action: :read
      define :update_competitor_data, action: :update
    end

    resource Emisint.Assessments.MdePublicAssessment do
      define :list_mde_public_assessments, action: :read
    end

    resource Emisint.Assessments.MdeIsd do
      define :upsert_mde_isd, action: :upsert
      define :list_mde_isds, action: :read
      define :get_mde_isd_by_code, action: :read, get_by: [:isd_code]
    end

    resource Emisint.Assessments.MdeDistrict do
      define :upsert_mde_district, action: :upsert
      define :list_mde_districts, action: :read
      define :get_mde_district_by_code, action: :read, get_by: [:district_code]
    end

    resource Emisint.Assessments.MdeBuilding do
      define :upsert_mde_building, action: :upsert
      define :list_mde_buildings, action: :read
      define :get_mde_building_by_code, action: :read, get_by: [:building_code]
    end

    resource Emisint.Assessments.MdeStateAssessmentResult do
      define :upsert_mde_state_assessment_result, action: :upsert
      define :list_mde_state_assessment_results, action: :read
    end

    resource Emisint.Assessments.MdeEntityMaster do
      define :upsert_mde_entity_master, action: :upsert
      define :list_mde_entity_masters, action: :read
      define :get_mde_entity_master_by_code, action: :read, get_by: [:entity_code]
    end

    resource Emisint.Assessments.MdeDistrictSnapshot do
      define :list_mde_district_snapshots_by_year, action: :by_year, args: [:school_year]
      define :upsert_mde_district_snapshot, action: :upsert
    end

    resource Emisint.Assessments.MdeSchoolVsLeaSnapshot do
      define :get_mde_school_vs_lea_snapshot,
        action: :by_building_and_year,
        args: [:building_code, :school_year]

      define :upsert_mde_school_vs_lea_snapshot, action: :upsert
    end

    resource Emisint.Assessments.MdeEnrollmentResult do
      define :list_mde_enrollment_results, action: :read
      define :upsert_mde_enrollment_result, action: :upsert
    end

    resource Emisint.Assessments.MdeSatResult do
      define :list_mde_sat_results, action: :read
      define :upsert_mde_sat_result, action: :upsert
    end

    resource Emisint.Assessments.MdeImportLog do
      define :create_mde_import_log, action: :create
      define :update_mde_import_log, action: :update
      define :get_mde_import_log, action: :read, get_by: [:id]
      define :list_recent_mde_import_logs, action: :list_recent
      define :mark_mde_import_log_processing, action: :mark_processing
      define :mark_mde_import_log_completed, action: :mark_completed
      define :mark_mde_import_log_failed, action: :mark_failed
    end

    resource Emisint.Assessments.MdeSchoolIndexResult do
      define :list_mde_school_index_results, action: :read
      define :upsert_mde_school_index_result, action: :upsert
    end

    resource Emisint.Assessments.MdeIndexThreshold do
      define :list_mde_index_thresholds, action: :read
      define :upsert_mde_index_threshold, action: :upsert
    end

    resource Emisint.Assessments.MdeEmoContact do
      define :upsert_mde_emo_contact, action: :upsert
      define :list_mde_emo_contacts, action: :read
      define :get_mde_emo_contact_by_district_code, action: :read, get_by: [:district_code]
    end
  end
end
