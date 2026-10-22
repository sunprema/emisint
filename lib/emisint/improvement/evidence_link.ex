defmodule Emisint.Improvement.EvidenceLink do
  @moduledoc """
  An evidence link attached to an entry. Only absolute `http`/`https` URLs are
  accepted; the app stores the link but cannot verify access to it.
  """
  use Ash.Resource, data_layer: :embedded

  validations do
    validate Emisint.Improvement.Validations.HttpUrl
  end

  attributes do
    attribute :url, :string do
      allow_nil? false
      public? true
      constraints max_length: 2048
    end

    attribute :label, :string do
      public? true
      constraints max_length: 200
    end
  end
end
