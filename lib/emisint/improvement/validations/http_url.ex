defmodule Emisint.Improvement.Validations.HttpUrl do
  @moduledoc "Requires `:url` to be an absolute http(s) URL with a host."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :url) do
      nil ->
        :ok

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and host not in [nil, ""] ->
            :ok

          _ ->
            {:error, field: :url, message: "must be an http or https link"}
        end
    end
  end
end
