defmodule Emisint.Accounts do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Accounts.Token
    resource Emisint.Accounts.User

    resource Emisint.Accounts.Organization do
      define :create_organization, action: :create
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_slug, action: :read, get_by: [:slug]
      define :list_organizations, action: :read
      define :update_organization, action: :update
    end
  end
end
