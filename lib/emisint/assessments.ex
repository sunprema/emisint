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
  end
end
