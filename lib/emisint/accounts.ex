defmodule Emisint.Accounts do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Accounts.Token

    resource Emisint.Accounts.User do
      define :list_users, action: :read
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_email, action: :get_by_email
      define :get_user_by_subject, action: :get_by_subject
      define :assign_organization, action: :assign_organization
      define :update_user_role, action: :update_role
    end

    resource Emisint.Accounts.Organization do
      define :create_organization, action: :create
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_slug, action: :read, get_by: [:slug]
      define :list_organizations, action: :read
      define :update_organization, action: :update
    end

    resource Emisint.Accounts.School do
      define :create_school, action: :create
      define :get_school, action: :read, get_by: [:id]
      define :get_school_by_building_code, action: :read, get_by: [:mde_building_code]
      define :list_schools, action: :read
      define :update_school, action: :update
    end

    resource Emisint.Accounts.ApiKey
  end
end
