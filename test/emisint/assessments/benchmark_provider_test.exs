defmodule Emisint.Assessments.BenchmarkProviderTest do
  use Emisint.DataCase, async: true

  alias Emisint.Assessments.BenchmarkProvider

  defp org_id, do: Ash.UUID.generate()

  defp valid_attrs do
    %{name: "NWEA MAP", code: "nwea_map_2024", scoring_system: :nwea_map, subjects: ["math", "reading"]}
  end

  defp create_provider(oid, overrides \\ %{}) do
    Ash.create!(BenchmarkProvider, Map.merge(valid_attrs(), overrides), tenant: oid, authorize?: false)
  end

  describe "create/1" do
    test "creates a benchmark provider with required attrs" do
      oid = org_id()

      assert {:ok, provider} =
               Ash.create(BenchmarkProvider, valid_attrs(), tenant: oid, authorize?: false)

      assert provider.name == "NWEA MAP"
      assert provider.code == "nwea_map_2024"
      assert provider.scoring_system == :nwea_map
      assert provider.subjects == ["math", "reading"]
      assert provider.organization_id == oid
    end

    test "subjects defaults to empty list" do
      oid = org_id()

      assert {:ok, provider} =
               Ash.create(
                 BenchmarkProvider,
                 %{name: "i-Ready", code: "i_ready_2024", scoring_system: :i_ready},
                 tenant: oid,
                 authorize?: false
               )

      assert provider.subjects == []
    end

    test "rejects invalid scoring_system" do
      oid = org_id()

      assert {:error, _} =
               Ash.create(
                 BenchmarkProvider,
                 %{name: "Test", code: "test_001", scoring_system: :unknown},
                 tenant: oid,
                 authorize?: false
               )
    end

    test "enforces unique code per org" do
      oid = org_id()
      create_provider(oid)

      assert {:error, error} =
               Ash.create(BenchmarkProvider, valid_attrs(), tenant: oid, authorize?: false)

      assert error.errors |> Enum.any?(&(&1.field == :code))
    end

    test "same code is allowed in different orgs" do
      assert {:ok, _} = Ash.create(BenchmarkProvider, valid_attrs(), tenant: org_id(), authorize?: false)
      assert {:ok, _} = Ash.create(BenchmarkProvider, valid_attrs(), tenant: org_id(), authorize?: false)
    end
  end

  describe "update/1" do
    test "updates name and subjects" do
      oid = org_id()
      provider = create_provider(oid)

      assert {:ok, updated} =
               Ash.update(provider, %{name: "NWEA MAP Growth", subjects: ["math", "reading", "science"]},
                 tenant: oid,
                 authorize?: false
               )

      assert updated.name == "NWEA MAP Growth"
      assert updated.subjects == ["math", "reading", "science"]
    end

    test "code is immutable (not in update accept list)" do
      oid = org_id()
      provider = create_provider(oid)

      assert {:error, error} =
               Ash.update(provider, %{code: "new_code"}, tenant: oid, authorize?: false)

      assert error.errors |> Enum.any?(&match?(%Ash.Error.Invalid.NoSuchInput{input: :code}, &1))
    end
  end

  describe "code interface" do
    test "create_benchmark_provider/2 works via domain" do
      assert {:ok, provider} =
               Emisint.Assessments.create_benchmark_provider(valid_attrs(), tenant: org_id(), authorize?: false)

      assert provider.scoring_system == :nwea_map
    end

    test "get_benchmark_provider_by_code/2 works via domain" do
      oid = org_id()
      create_provider(oid)

      assert {:ok, provider} =
               Emisint.Assessments.get_benchmark_provider_by_code("nwea_map_2024",
                 tenant: oid,
                 authorize?: false
               )

      assert provider.code == "nwea_map_2024"
    end
  end
end
