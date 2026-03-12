defmodule Emisint.Storage do
  @moduledoc """
  Tigris (S3-compatible) object storage wrapper for large CSV imports.

  Presigned URLs let the browser upload files directly to Tigris,
  bypassing the Phoenix WebSocket. Workers then stream objects back
  to a temp file for processing.
  """

  @doc "Returns the configured bucket name."
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
  Generates a presigned PUT URL the browser uses to upload directly.
  Returns `{:ok, url}` or `{:error, reason}`.
  """
  def presigned_upload_url(key, expires_in \\ 900) do
    ExAws.S3.presigned_url(ex_aws_config(), :put, bucket(), key, expires_in: expires_in)
  end

  @doc """
  Downloads the S3 object at `key` to `dest_path` on disk.
  Uses Req to stream response without loading full file into memory.
  Returns `dest_path`.
  """
  def download_to_file!(key, dest_path) do
    {:ok, url} = ExAws.S3.presigned_url(ex_aws_config(), :get, bucket(), key, expires_in: 300)

    File.open!(dest_path, [:write, :binary], fn file ->
      Req.get!(url,
        into: fn {:data, chunk}, {req, resp} ->
          IO.binwrite(file, chunk)
          {:cont, {req, resp}}
        end
      )
    end)

    dest_path
  end

  @doc "Deletes an object from the bucket. Best-effort, does not raise."
  def delete(key) do
    ExAws.S3.delete_object(bucket(), key)
    |> ExAws.request()

    :ok
  end

  defp ex_aws_config, do: ExAws.Config.new(:s3)
end
