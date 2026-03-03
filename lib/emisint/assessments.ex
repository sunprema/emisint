defmodule Emisint.Assessments do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Assessments.BenchmarkProvider do
      define :create_benchmark_provider, action: :create
      define :get_benchmark_provider, action: :read, get_by: [:id]
      define :get_benchmark_provider_by_code, action: :read, get_by: [:code]
      define :list_benchmark_providers, action: :read
      define :update_benchmark_provider, action: :update
    end

    resource Emisint.Assessments.AssessmentResult do
      define :create_assessment_result, action: :create
      define :upsert_assessment_result, action: :bulk_upsert
      define :get_assessment_result, action: :read, get_by: [:id]
      define :list_assessment_results, action: :read
      define :update_assessment_result, action: :update
    end

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
      define :get_mde_school_vs_lea_snapshot, action: :by_building_and_year,
        args: [:building_code, :school_year]

      define :upsert_mde_school_vs_lea_snapshot, action: :upsert
    end

    resource Emisint.Assessments.MdeEnrollmentResult do
      define :list_mde_enrollment_results, action: :read
      define :upsert_mde_enrollment_result, action: :upsert
    end
  end
end
