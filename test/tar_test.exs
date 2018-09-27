defmodule ExDockerBuild.TarTest do
  use ExUnit.Case, async: true

  alias ExDockerBuild.Tar

  @cwd System.cwd!()
  @fixtures_path Path.join([@cwd, "test", "fixtures"])

  setup do
    on_exit(fn ->
      Path.wildcard("*.tar") |> Enum.map(&File.rm!/1)
    end)

    :ok
  end

  describe "tar archives" do
    test "tar a directory" do
      assert {:ok, path} = Tar.tar(@fixtures_path, @cwd)
      assert File.exists?(path)
      assert Path.extname(path) == ".tar"

      assert :erl_tar.table(path) ==
               {:ok,
                [
                  'Dockerfile_bind.dockerfile',
                  'Dockerfile_erlang.dockerfile',
                  'Dockerfile_simple.dockerfile'
                ]}
    end

    test "tar a file" do
      assert {:ok, path} =
               Tar.tar(Path.join([@fixtures_path, "Dockerfile_erlang.dockerfile"]), @cwd)

      assert File.exists?(path)
      assert Path.extname(path) == ".tar"

      assert :erl_tar.table(path) == {:ok, ['Dockerfile_erlang.dockerfile']}
    end
  end
end
