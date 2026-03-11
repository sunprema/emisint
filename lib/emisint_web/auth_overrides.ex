defmodule EmisintWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  # configure your UI overrides here

  # First argument to `override` is the component name you are overriding.
  # The body contains any number of configurations you wish to override
  # Below are some examples

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  override AshAuthentication.Phoenix.Components.Banner do
    set :image_url, "./images/emisint.webp"
    set :text_class, "bg-red-500"
  end

  override AshAuthentication.Phoenix.Components.SignIn do
    set :show_banner, true
  end
end
