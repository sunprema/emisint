defmodule Emisint.Accounts do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Accounts.Token
    resource Emisint.Accounts.User
  end
end
