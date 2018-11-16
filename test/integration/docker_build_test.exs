defmodule ExDockerBuild.Integration.DockerBuildTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  alias ExDockerBuild.DockerBuild

  @moduletag :integration

  describe "bind mount host dir into container" do
    @cwd System.cwd!()
    @file_path Path.join([@cwd, "myfile.txt"])

    setup do
      on_exit(fn ->
        File.rm_rf!(@file_path)
      end)
    end

    test "build docker image binding a mount at build time" do
      instructions = [
        {"FROM", "alpine:latest"},
        {"VOLUME", @cwd <> ":/data"},
        {"RUN", "echo \"hello-world!!!!\" > /data/myfile.txt"},
        {"CMD", "[\"cat\", \"/data/myfile.txt\"]"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)

      assert log =~ "STEP 1/4 : FROM alpine:latest"
      assert log =~ "pulling image alpine:latest"
      assert log =~ "STEP 2/4 : VOLUME #{@cwd}:/data"
      assert log =~ "STEP 3/4 : RUN echo \"hello-world!!!!\" > /data/myfile.txt"
      assert log =~ "STEP 4/4 : CMD [\"cat\", \"/data/myfile.txt\"]"
      assert File.exists?(@file_path)
      assert File.read!(@file_path) == "hello-world!!!!\n"
    end

    test "build docker image relative binding a mount at build time" do
      instructions = [
        {"FROM", "alpine:latest"},
        {"VOLUME", ".:/data"},
        {"RUN", "echo \"hello-relative-world!!!!\" > /data/myfile.txt"},
        {"CMD", "[\"cat\", \"/data/myfile.txt\"]"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)

      assert log =~ "STEP 2/4 : VOLUME .:/data"
      assert File.exists?(@file_path)
      assert File.read!(@file_path) == "hello-relative-world!!!!\n"
    end
  end

  describe "mount a named volume" do
    test "build docker image mounting a named volume" do
      instructions = [
        {"FROM", "alpine:latest"},
        {"RUN", "mkdir /myvol"},
        {"RUN", "echo \"hello-world!!!!\" > /myvol/greeting"},
        {"VOLUME", "vol_storage"},
        {"VOLUME", "vol_storage:/myvol"},
        {"CMD", "[\"cat\", \"/myvol/greeting\"]"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")

          with {:ok, container_id} <- ExDockerBuild.create_container(%{"Image" => image_id}),
               {:ok, ^container_id} <- ExDockerBuild.start_container(container_id),
               {:ok, [container_logs]} = ExDockerBuild.containers_logs(container_id),
               {:ok, ^container_id} <- ExDockerBuild.stop_container(container_id),
               :ok <- ExDockerBuild.remove_container(container_id) do
            assert container_logs =~ "hello-world!!!!"
          else
            error ->
              assert error == nil, "should not be an error"
          end

          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)

      assert log =~ "STEP 1/6 : FROM alpine:latest"
      assert log =~ "pulling image alpine:latest"
      assert log =~ "STEP 2/6 : RUN mkdir /myvol"
      assert log =~ "STEP 3/6 : RUN echo \"hello-world!!!!\" > /myvol/greeting"
      assert log =~ "STEP 4/6 : VOLUME vol_storage"
      assert log =~ "STEP 5/6 : VOLUME vol_storage:/myvol"
      assert log =~ "STEP 6/6 : CMD [\"cat\", \"/myvol/greeting\"]"
    end
  end

  describe "tagging an image" do
    test "build docker image mounting a named volume" do
      instructions = [
        {"FROM", "alpine:latest"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")

          assert :ok =
                   ExDockerBuild.tag_image(image_id, "fake/fake_testci", "v1.0.0", %{
                     docker_username: "",
                     docker_password: "",
                     docker_servername: ""
                   })
        end)

      assert log =~ "STEP 1/1 : FROM alpine:latest"
    end
  end

  describe "container listens on the specified network ports" do
    test "expose assume tcp port 80 as default value" do
      instructions = [
        {"FROM", "alpine:latest"},
        {"EXPOSE", "80"}
      ]

      _log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")
          assert {:ok, container_id} = ExDockerBuild.create_container(%{"Image" => image_id})
          assert {:ok, container_id} == ExDockerBuild.start_container(container_id)
          assert {:ok, container_id} == ExDockerBuild.stop_container(container_id)
          assert {:ok, body} = ExDockerBuild.container_inspect(container_id, false)
          assert %{"Config" => %{"ExposedPorts" => %{"80/tcp" => %{}}}} = body
          assert :ok = ExDockerBuild.remove_container(container_id)
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)
    end

    test "defining tcp and udp ports" do
      instructions = [
        {"FROM", "alpine:latest"},
        {"EXPOSE", "80/tcp"},
        {"EXPOSE", "88/udp"}
      ]

      _log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")
          assert {:ok, container_id} = ExDockerBuild.create_container(%{"Image" => image_id})
          assert {:ok, container_id} == ExDockerBuild.start_container(container_id)
          assert {:ok, container_id} == ExDockerBuild.stop_container(container_id)
          assert {:ok, body} = ExDockerBuild.container_inspect(container_id, false)
          assert %{"Config" => %{"ExposedPorts" => %{"80/tcp" => %{}, "88/udp" => %{}}}} = body
          assert :ok = ExDockerBuild.remove_container(container_id)
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)
    end
  end
end
