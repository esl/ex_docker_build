defmodule ExDockerBuild.Integration.DockerBuildTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  alias ExDockerBuild.DockerBuild

  @moduletag :integration

  @cwd System.cwd!()
  @file_path Path.join([@cwd, "myfile.txt"])

  setup do
    on_exit(fn ->
      File.rm!(@file_path)
    end)
  end

  test "build docker image binding a mount at build time" do
    instructions = [
      {"FROM", "alpine:latest"},
      {"VOLUME", @cwd <> ":/data"},
      {"RUN", "echo \"hello-world!!!!\" > /data/myfile.txt"},
      {"CMD", "[\"cat\", \"/data/myfile.txt\"]"}
    ]

    log = capture_log(fn ->
      assert {:ok, image_id} = DockerBuild.build(instructions, "")
    end)

    assert log =~ "STEP 1/4 : FROM alpine:latest"
    assert log =~ "pulling image alpine:latest"
    assert log =~ "STEP 2/4 : VOLUME #{@cwd}:/data"
    assert log =~ "STEP 3/4 : RUN echo \"hello-world!!!!\" > /data/myfile.txt"
    assert log =~ "STEP 4/4 : CMD [\"cat\", \"/data/myfile.txt\"]"
    # TODO: delete image on exit
    # on_exit(fn ->

    # end)
    assert File.exists?(@file_path)
    assert File.read!(@file_path) == "hello-world!!!!\n"
  end
end
