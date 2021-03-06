defmodule ExDockerBuild.Integration.DockerBuildTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  alias ExDockerBuild.DockerBuild

  alias ExDockerBuild.API.VolumeFilter

  @moduletag :integration

  @cwd File.cwd!()
  @file_path Path.join([@cwd, "myfile.txt"])

  describe "bind mount host dir into container" do
    setup do
      on_exit(fn ->
        File.rm_rf!(@file_path)
      end)
    end

    test "build docker image binding a mount at build time" do
      instructions = [
        {"FROM", "alpine:3.8"},
        {"VOLUME", @cwd <> ":/data"},
        {"RUN", "echo \"hello-world!!!!\" > /data/myfile.txt"},
        {"CMD", "[\"cat\", \"/data/myfile.txt\"]"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)

      assert log =~ "STEP 1/4 : FROM alpine:3.8"
      assert log =~ "pulling image alpine:3.8"
      assert log =~ "STEP 2/4 : VOLUME #{@cwd}:/data"
      assert log =~ "STEP 3/4 : RUN echo \"hello-world!!!!\" > /data/myfile.txt"
      assert log =~ "STEP 4/4 : CMD [\"cat\", \"/data/myfile.txt\"]"
      assert File.exists?(@file_path)
      assert File.read!(@file_path) == "hello-world!!!!\n"
    end

    test "build docker image relative binding a mount at build time" do
      instructions = [
        {"FROM", "alpine:3.8"},
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
    setup do
      on_exit(fn ->
        volume_storage = Path.join([@cwd, "vol_storage"])
        File.rm_rf(volume_storage)
      end)
    end

    test "build docker image mounting a named volume" do
      instructions = [
        {"FROM", "alpine:3.8"},
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
          assert :ok = ExDockerBuild.delete_volume("vol_storage")
        end)

      assert log =~ "STEP 1/6 : FROM alpine:3.8"
      assert log =~ "pulling image alpine:3.8"
      assert log =~ "STEP 2/6 : RUN mkdir /myvol"
      assert log =~ "STEP 3/6 : RUN echo \"hello-world!!!!\" > /myvol/greeting"
      assert log =~ "STEP 4/6 : VOLUME vol_storage"
      assert log =~ "STEP 5/6 : VOLUME vol_storage:/myvol"
      assert log =~ "STEP 6/6 : CMD [\"cat\", \"/myvol/greeting\"]"
    end

    @tag capture_log: true
    test "create and manage persistent storage as volumes that can be attached to containers" do
      volume_name = "vol_storage"

      instructions = [
        {"FROM", "alpine:3.8"},
        {"VOLUME", volume_name},
        {"VOLUME", "vol_storage:/myvol"}
      ]

      capture_log(fn ->
        assert {:ok, image_id} = DockerBuild.build(instructions, "")
      end)

      {:ok, body} = ExDockerBuild.get_volumes(%VolumeFilter{name: volume_name})
      assert %{"Volumes" => [%{"Name" => volume_name, "Scope" => "local"}]} = body
      {:ok, volume_body} = ExDockerBuild.inspect_volume(volume_name)
      assert %{"Name" => ^volume_name, "Scope" => "local"} = volume_body
      assert :ok = ExDockerBuild.delete_volume(volume_name)
    end
  end

  describe "tagging an image" do
    test "build docker image mounting a named volume" do
      instructions = [
        {"FROM", "alpine:3.8"}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "")

          assert :ok = ExDockerBuild.tag_image(image_id, "fake/fake_testci", "v1.0.0")
        end)

      assert log =~ "STEP 1/1 : FROM alpine:3.8"
    end
  end

  describe "container listens on the specified network ports" do
    test "expose assume tcp port 80 as default value" do
      instructions = [
        {"FROM", "alpine:3.8"},
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
        {"FROM", "alpine:3.8"},
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

  describe "copying files to a container" do
    setup do
      File.write!(@file_path, "This is a copying test.")

      on_exit(fn ->
        File.rm_rf!(@file_path)
        Path.wildcard("*.tar") |> Enum.map(&File.rm!/1)
        File.rm_rf!("archive")
      end)
    end

    test "copying files from filesystem to a container" do
      instructions = [
        {"FROM", "alpine:3.8"},
        {"COPY", "#{@file_path} ."}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "/")
          assert {:ok, container_id} = ExDockerBuild.create_container(%{"Image" => image_id})
          assert {:ok, archive} = ExDockerBuild.get_archive(container_id, "myfile.txt")
          assert byte_size(archive) > 0
          File.write!("./mytar.tar", archive)
          assert :ok = ExDockerBuild.remove_container(container_id)
          assert :ok = ExDockerBuild.delete_image(image_id, true)
        end)

      assert log =~ "STEP 2/2 : COPY #{@file_path} ."
      assert :ok = :erl_tar.extract("./mytar.tar", [{:cwd, "./archive"}])
      assert File.read!("archive/myfile.txt") == "This is a copying test."
    end

    test "copying files from one container to another" do
      instructions = [
        {"FROM", "alpine:3.8 as copy"},
        {"COPY", "#{@file_path} ."},
        {"FROM", "alpine:3.8"},
        {"COPY", "--from=copy /myfile.txt ."}
      ]

      log =
        capture_log(fn ->
          assert {:ok, image_id} = DockerBuild.build(instructions, "/")
          assert {:ok, container_id} = ExDockerBuild.create_container(%{"Image" => image_id})
          assert {:ok, archive} = ExDockerBuild.get_archive(container_id, "myfile.txt")
          assert :ok = ExDockerBuild.remove_container(container_id)
          assert :ok = ExDockerBuild.delete_image(image_id, true)
          assert byte_size(archive) > 0
          File.write!("./mycopytar.tar", archive)
          assert :ok = :erl_tar.extract("./mycopytar.tar")
          assert File.read!("myfile.txt") == "This is a copying test."
        end)

      assert log =~ "STEP 4/4 : COPY --from=copy /myfile.txt ."
    end
  end

  describe "image history" do
    @tag capture_log: true
    test "gets image history" do
      assert :ok = ExDockerBuild.pull("alpine:3.8")
      assert {:ok, history} = ExDockerBuild.image_history("alpine:3.8")

      assert [
               %{"created_by" => "/bin/sh -c #(nop)  CMD [\"/bin/sh\"]", "empty_layer" => true},
               %{"created_by" => command}
             ] = history

      assert "/bin/sh -c #(nop) ADD file:" <> <<_::binary-size(64)>> <> " in / " = command
    end
  end
end
