defmodule Emisint.Analytics do
  use Ash.Domain, otp_app: :emisint, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Emisint.Analytics.DataSyncLog
    resource Emisint.Analytics.PerformanceSnapshot
    resource Emisint.Analytics.InterventionTrigger
  end
end
