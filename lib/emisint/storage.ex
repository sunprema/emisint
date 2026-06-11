defmodule Emisint.Storage do
  @moduledoc """
  Object storage wrapper for large CSV imports.

  In production (and when AWS_ACCESS_KEY_ID is set), uploads go directly to
  Tigris (S3-compatible) via presigned URLs. In dev without credentials, files
  are written to local disk and served through the LocalUploadPlug.
  """

  @doc "Returns the configured bucket name (Tigris only)."
  def bucket do
    System.get_env("BUCKET_NAME") ||
      Application.get_env(:emisint, __MODULE__, [])
      |> Keyword.get(:bucket, "emisint-imports")
  end

  @doc "Generates a unique object key for an import file."
  def import_key(prefix, filename) do
    ext = Path.extname(filename)
    "imports/#{prefix}/#{System.unique_integer([:positive])}#{ext}"
  end

  @doc """
  Generates an upload URL the browser uses to PUT a file.
  Returns `{:ok, url}` or `{:error, reason}`.
  """
  def presigned_upload_url(key, expires_in \\ 900) do
    if local?() do
      base = Application.get_env(:emisint, __MODULE__, []) |> Keyword.get(:local_upload_url, "http://localhost:4000")
      {:ok, "#{base}/dev/uploads/#{key}"}
    else
      ExAws.S3.presigned_url(ex_aws_config(), :put, bucket(), key, expires_in: expires_in)
    end
  end

  @doc """
  Downloads the object at `key` to `dest_path` on disk.
  Returns `dest_path`.
  """
  def download_to_file!(key, dest_path) do
    if local?() do
      src = EmisintWeb.LocalUploadPlug.local_path(key)
      File.copy!(src, dest_path)
      dest_path
    else
      {:ok, url} = ExAws.S3.presigned_url(ex_aws_config(), :get, bucket(), key, expires_in: 300)

      {:ok, fd} = :file.open(dest_path, [:write, :raw, :binary])

      try do
        Req.get!(url,
          into: fn {:data, chunk}, {req, resp} ->
            :file.write(fd, chunk)
            {:cont, {req, resp}}
          end
        )
      after
        :file.close(fd)
      end

      dest_path
    end
  end

  @doc "Deletes an object. Best-effort, never raises."
  def delete(key) do
    if local?() do
      key |> EmisintWeb.LocalUploadPlug.local_path() |> File.rm()
    else
      ExAws.S3.delete_object(bucket(), key)
      |> ExAws.request()
    end

    :ok
  rescue
    _ -> :ok
  end

  # Use local disk when explicitly configured OR when no AWS credentials are present.
  defp local? do
    cfg = Application.get_env(:emisint, __MODULE__, [])

    Keyword.get(cfg, :backend) == :local or
      (is_nil(System.get_env("AWS_ACCESS_KEY_ID")) and Keyword.get(cfg, :backend) != :tigris)
  end

  defp ex_aws_config, do: ExAws.Config.new(:s3)
end
