defmodule ExDockerBuild do
  require Logger

  alias ExDockerBuild.Tar
  alias ExDockerBuild.API.{Docker, DockerRemoteAPI}

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

  @spec commit(Docker.container_id(), map()) ::
          {:ok, Docker.image_id()} | {:error, any()}
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

  @spec commit(map(), map()) :: {:ok, Docker.container_id()} | {:error, any()}
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

  @spec start_container(Docker.container_id()) ::
          {:ok, Docker.container_id()} | {:error, any()}
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

  @spec stop_container(Docker.container_id()) ::
          {:ok, Docker.container_id()} | {:error, any()}
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

  @spec upload_file(Docker.container_id(), Path.t(), Path.t()) ::
          {:ok, Docker.container_id()} | {:error, any()} | no_return()
  def upload_file(container_id, input_path, output_path) do
    case Tar.tar(input_path, File.cwd!()) do
      {:ok, final_path} ->
        archive_payload = File.read!(final_path)

        try do
          case DockerRemoteAPI.upload_file(container_id, archive_payload, output_path) do
            {:ok, %{status_code: 200}} ->
              {:ok, container_id}

            {:ok, %{body: body, status_code: _}} ->
              {:error, body}

            {:error, %{reason: reason}} ->
              {:error, reason}
          end
        after
          File.rm!(final_path)
        end

      {:error, _} = error ->
        error
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
end
