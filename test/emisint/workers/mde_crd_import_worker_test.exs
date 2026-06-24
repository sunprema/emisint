defmodule Emisint.Workers.MdeCrdImportWorkerTest do
  use Emisint.DataCase, async: false
  use Oban.Testing, repo: Emisint.Repo

  alias Emisint.Workers.MdeCrdImportWorker

  describe "enqueueing" do
    test "inserts a job on the :data_ingestion queue with the import args" do
      args = %{"bucket" => "test-bucket", "key" => "imports/crd/file.csv", "log_id" => nil}

      assert {:ok, _job} =
               args
               |> MdeCrdImportWorker.new()
               |> Oban.insert()

      assert_enqueued(worker: MdeCrdImportWorker, queue: :data_ingestion, args: args)
    end
  end
end
