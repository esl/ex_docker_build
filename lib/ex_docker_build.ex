defmodule ExDockerBuild do
  require Logger

  alias ExDockerBuild.Tar
  alias ExDockerBuild.API.{Docker, DockerRemoteAPI}
  alias ExDockerBuild.API.VolumeFilter

  @spec create_layer(map(), keyword()) :: {:ok, Docker.image_id()} | {:error, any()}
  def create_layer(payload, opts \\ []) do
    wait = Keyword.get(opts, :wait, false)

    with {:ok, container_id} <- create_container(payload),
         {:ok, ^container_id} <- start_container(container_id),
         {:ok, ^container_id} <- maybe_wait_container(container_id, wait),
         {:ok, ^container_id} <- stop_container(container_id),
         {:ok, new_image_id} <- commit(container_id, %{}),
         :ok <- remove_container(container_id) do
      {:ok, new_image_id}
    else
      {:error, _} = error -> error
    end
  end

  @spec commit(Docker.container_id(), map()) :: {:ok, Docker.image_id()} | {:error, any()}
  def commit(container_id, payload) do
    case DockerRemoteAPI.commit(container_id, payload) do
      {:ok, %{body: body, status_code: 201}} ->
        %{"Id" => image_id} = Poison.decode!(body)
        # ImageId comes in the form of sha256:IMGAGE_ID and the only part that we are
        # interested in is in the IMAGE_ID
        image_id = String.slice(image_id, 7..-1)
        Logger.info("image created #{image_id}")
        {:ok, image_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec create_container(map(), map()) :: {:ok, Docker.container_id()} | {:error, any()}
  def create_container(payload, params \\ %{}) do
    case DockerRemoteAPI.create_container(payload, params) do
      {:ok, %{body: body, status_code: 201}} ->
        %{"Id" => container_id} = Poison.decode!(body)
        Logger.info("container created #{container_id}")
        {:ok, container_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec remove_container(Docker.container_id(), map()) :: :ok | {:error, any()}
  def remove_container(container_id, params \\ %{}) do
    case DockerRemoteAPI.remove_container(container_id, params) do
      {:ok, %{status_code: 204}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec start_container(Docker.container_id()) :: {:ok, Docker.container_id()} | {:error, any()}
  def start_container(container_id) do
    case DockerRemoteAPI.start_container(container_id) do
      {:ok, %{status_code: code}} when code in [204, 304] ->
        {:ok, container_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec stop_container(Docker.container_id()) :: {:ok, Docker.container_id()} | {:error, any()}
  def stop_container(container_id) do
    case DockerRemoteAPI.stop_container(container_id) do
      {:ok, %{status_code: status}} when status in [204, 304] ->
        {:ok, container_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec maybe_wait_container(Docker.container_id(), timeout) ::
          {:ok, Docker.container_id()} | {:error, any()}
        when timeout: boolean() | pos_integer()
  def maybe_wait_container(container_id, timeout) when is_integer(timeout) do
    # wait some time for a container to be up and running
    # there's no way to know if a container is blocked running a CMD, ENTRYPOINT
    # instruction, or is running a long task
    # TODO: maybe use container inspect to see its current state or docker events
    case wait_container(container_id, timeout) do
      {:ok, _} = result ->
        result

      {:error, _} = error ->
        error
    end
  end

  def maybe_wait_container(container_id, true), do: wait_container(container_id)
  def maybe_wait_container(container_id, false), do: {:ok, container_id}

  @spec wait_container(Docker.container_id(), timeout) ::
          {:ok, Docker.container_id()} | {:error, any()}
        when timeout: pos_integer() | :infinity
  def wait_container(container_id, timeout \\ :infinity) do
    case DockerRemoteAPI.wait_container(container_id, timeout) do
      {:ok, %{status_code: 200}} ->
        {:ok, container_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec containers_logs(Docker.container_id(), map()) :: {:error, any()} | {:ok, [String.t()]}
  def containers_logs(container_id, params \\ %{}) do
    DockerRemoteAPI.containers_logs(container_id, params, stream_to: self())
  end

  @spec upload_file(Docker.container_id(), Path.t(), Path.t()) ::
          {:ok, Docker.container_id()} | {:error, any()} | no_return()
  def upload_file(container_id, input_path, output_path) do
    case Tar.tar(input_path, File.cwd!()) do
      {:ok, final_path} ->
        archive_payload = File.read!(final_path)

        try do
          upload_archive(container_id, archive_payload, output_path)
        after
          File.rm!(final_path)
        end

      {:error, _} = error ->
        error
    end
  end

  @spec upload_archive(Docker.container_id(), String.t(), Path.t()) ::
          {:ok, Docker.container_id()} | {:error, any()} | no_return()
  def upload_archive(container_id, archive_payload, output_path) do
    case DockerRemoteAPI.upload_file(container_id, archive_payload, output_path) do
      {:ok, %{status_code: 200}} ->
        {:ok, container_id}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec pull(Docker.image_id()) :: :ok | {:error, any()}
  def pull(image) do
    Logger.info("pulling image #{image}")

    case DockerRemoteAPI.pull(image) do
      {:ok, %{status_code: 200}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec create_volume(map()) :: :ok | {:error, any()}
  def create_volume(payload) do
    case DockerRemoteAPI.create_volume(payload) do
      {:ok, %{status_code: 201}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec get_volumes(VolumeFilter.t()) :: {:ok, any()} | {:error, any()}
  def get_volumes(filters \\ %VolumeFilter{}) do
    case DockerRemoteAPI.get_volumes(filters) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body)}

      {:ok, %{body: body, status_code: _}} ->
        {:error, Poison.decode!(body)}

      {:error, %{status_code: 500, message: message}} ->
        {:error, message}
    end
  end

  @spec inspect_volume(String.t()) :: {:ok, any()} | {:error, any()}
  def inspect_volume(volume_name) do
    case DockerRemoteAPI.inspect_volume(volume_name) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body)}

      {:ok, %{body: body, status_code: _}} ->
        {:error, Poison.decode!(body)}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec delete_volume(String.t()) :: :ok | {:error, any()}
  def delete_volume(volume_name) do
    case DockerRemoteAPI.delete_volume(volume_name) do
      {:ok, %{status_code: 204}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec delete_image(Docker.image_id()) :: :ok | {:error, any()}
  def delete_image(image) do
    delete_image(image, false)
  end

  @spec delete_image(Docker.image_id(), boolean()) :: :ok | {:error, any()}
  def delete_image(image, force) do
    Logger.info("deleting image by image id #{image}")

    case DockerRemoteAPI.delete_image(image, force) do
      {:ok, %{status_code: 200}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec push_image(Docker.image_id(), Docker.tag_name(), Docker.docker_credentials()) ::
          :ok | {:error, any()}
  def push_image(image, tag_name, credentials) do
    Logger.info("pushing image id #{image} tag #{tag_name} to docker registry")

    case DockerRemoteAPI.push_image(image, tag_name, credentials) do
      {:ok, %{status_code: 200}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec tag_image(
          Docker.image_id(),
          Docker.repository_name(),
          Docker.tag_name()
        ) :: :ok | {:error, any()}
  def tag_image(image, repo_name, tag_name) do
    case DockerRemoteAPI.tag_image(image, repo_name, tag_name) do
      {:ok, %{status_code: 201}} ->
        :ok

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec container_inspect(Docker.container_id(), boolean()) :: {:ok, any()} | {:error, any()}
  def container_inspect(container_id, size) do
    Logger.info("inspecting container by container id #{container_id}")

    case DockerRemoteAPI.container_inspect(container_id, size) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Poison.decode!(body)}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec get_archive(Docker.container_id(), String.t()) :: {:ok, any()} | {:error, any()}
  def get_archive(container_id, path) do
    Logger.info("getting archive from container id #{container_id}")

    case DockerRemoteAPI.get_archive(container_id, path) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  @spec image_history(Docker.image_id()) :: {:ok, any()} | {:error, any()}
  def image_history(image_id) do
    Logger.info("getting history for image id #{image_id}")

    case DockerRemoteAPI.image_history(image_id) do
      {:ok, %{status_code: 200, body: body}} ->
        history = body |> Poison.decode!() |> to_config_history()
        {:ok, history}

      {:ok, %{body: body, status_code: _}} ->
        {:error, body}

      {:error, %{reason: reason}} ->
        {:error, reason}
    end
  end

  defp to_config_history(history) do
    Enum.reduce(history, [], fn record, acc ->
      new_record =
        Enum.reduce(record, %{}, fn
          {"Id", _}, acc ->
            acc

          {"Size", v}, acc ->
            if v == 0 do
              Map.put_new(acc, "empty_layer", true)
            else
              acc
            end

          {"Comment", _}, acc ->
            acc

          {"Tags", _}, acc ->
            acc

          {k, v}, acc ->
            new_key = Macro.underscore(k)

            value =
              case new_key do
                "created" ->
                  v
                  |> DateTime.from_unix!()
                  |> DateTime.to_iso8601()

                _ ->
                  v
              end

            Map.put_new(acc, new_key, value)
        end)

      [new_record | acc]
    end)
    |> Enum.reverse()
  end
end
