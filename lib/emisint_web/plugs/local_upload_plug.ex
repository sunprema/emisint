defmodule EmisintWeb.LocalUploadPlug do
  @moduledoc """
  Dev-only plug that accepts raw PUT requests and writes them to local disk,
  simulating Tigris presigned-URL uploads without needing real S3 credentials.

  Mounted at /dev/uploads in router.ex only when Mix.env() == :dev.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "PUT"} = conn, _opts) do
    key = Enum.join(conn.path_info, "/")
    dest = local_path(key)
    dest |> Path.dirname() |> File.mkdir_p!()

    {:ok, body, conn} = read_body(conn, length: 500_000_000)
    File.write!(dest, body)

    conn
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts) do
    conn
    |> send_resp(405, "Method Not Allowed")
    |> halt()
  end

  def local_path(key) do
    base = Application.get_env(:emisint, Emisint.Storage)[:local_dir] || local_default_dir()
    Path.join(base, key)
  end

  defp local_default_dir, do: Path.join(System.tmp_dir!(), "emisint_uploads")
end
