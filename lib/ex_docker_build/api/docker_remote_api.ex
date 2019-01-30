defmodule ExDockerBuild.API.DockerRemoteAPI do
  alias ExDockerBuild.API.Docker
  alias ExDockerBuild.HttpStream
  @behaviour Docker

  @version "v1.37"
  @endpoint URI.encode_www_form("/var/run/docker.sock")
  @protocol "http+unix"
  @url "#{@protocol}://#{@endpoint}/#{@version}"
  @json_header {"Content-Type", "application/json"}
  @tar_header {"Content-Type", "application/tar"}

  @impl Docker
  def commit(container_id, payload) do
    "#{@url}/commit"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"container" => container_id}))
    |> URI.to_string()
    |> HTTPoison.post(Poison.encode!(payload), [@json_header])
  end

  @impl Docker
  def create_container(payload, params \\ %{}) do
    name = Map.get(payload, "ContainerName", "")

    params = if name != "", do: Map.merge(params, %{name: name}), else: params

    "#{@url}/containers/create"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
    |> HTTPoison.post(Poison.encode!(payload), [@json_header])
  end

  @impl Docker
  def remove_container(container_id, params \\ %{}) do
    "#{@url}/containers/#{container_id}"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
    |> HTTPoison.delete()
  end

  @impl Docker
  def start_container(container_id) do
    HTTPoison.post("#{@url}/containers/#{container_id}/start", "", [])
  end

  @impl Docker
  def stop_container(container_id) do
    "#{@url}/containers/#{container_id}/stop"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{t: 5}))
    |> URI.to_string()
    |> HTTPoison.post("", [], timeout: 30_000, recv_timeout: 30_000)
  end

  @impl Docker
  def wait_container(container_id, timeout \\ :infinity) do
    HTTPoison.post("#{@url}/containers/#{container_id}/wait", "", [],
      timeout: timeout,
      recv_timeout: timeout
    )
  end

  @impl Docker
  def containers_logs(container_id, params \\ %{}, opts \\ []) do
    default_params = %{stdout: 1, stderr: 1, tail: "all", timestamps: 1, follow: 0}
    final_params = Map.merge(default_params, params)

    url =
      "#{@url}/containers/#{container_id}/logs"
      |> URI.parse()
      |> Map.put(:query, URI.encode_query(final_params))
      |> URI.to_string()

    try do
      logs =
        url
        |> HttpStream.new_stream(opts)
        |> Enum.to_list()

      {:ok, logs}
    catch
      :exit, _ -> {:error, :failed_to_stream_logs}
    end
  end

  @impl Docker
  def upload_file(container_id, archive_payload, output_path) do
    query_params =
      URI.encode_query(%{
        "path" => output_path,
        "noOverwriteDirNonDir" => false
      })

    "#{@url}/containers/#{container_id}/archive"
    |> URI.parse()
    |> Map.put(:query, query_params)
    |> URI.to_string()
    |> HTTPoison.put(archive_payload, [@tar_header])
  end

  @impl Docker
  def pull(image) do
    # TODO:  ADD support for X-Registry-Auth
    "#{@url}/images/create"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"fromImage" => image}))
    |> URI.to_string()
    |> HTTPoison.post("", [], timeout: :infinity, recv_timeout: :infinity)
  end

  @impl Docker
  def create_volume(payload) do
    HTTPoison.post("#{@url}/volumes/create", Poison.encode!(payload), [@json_header])
  end

  @impl Docker
  def delete_image(image_id, force) do
    "#{@url}/images/#{image_id}"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"force" => force}))
    |> URI.to_string()
    |> HTTPoison.delete()
  end

  @impl Docker
  def push_image(image_id, tag, %{
        docker_username: docker_username,
        docker_password: docker_password,
        docker_servername: docker_servername
      }) do
    docker_credentials = %{
      "username" => docker_username,
      "password" => docker_password,
      "servername" => docker_servername
    }

    header =
      Poison.encode!(docker_credentials)
      |> Base.encode64()

    "#{@url}/images/#{image_id}/push"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"tag" => tag}))
    |> URI.to_string()
    |> HTTPoison.post("", [{"X-Registry-Auth", header}])
  end

  @impl Docker
  def tag_image(image_id, repo, tag) do
    "#{@url}/images/#{image_id}/tag"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"repo" => repo, "tag" => tag}))
    |> URI.to_string()
    |> HTTPoison.post("")
  end

  @impl Docker
  def container_inspect(container_id, size) do
    "#{@url}/containers/#{container_id}/json"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"size" => size}))
    |> URI.to_string()
    |> HTTPoison.get()
  end

  @impl Docker
  def get_archive(container_id, path) do
    "#{@url}/containers/#{container_id}/archive"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"path" => path}))
    |> URI.to_string()
    |> HTTPoison.get()
  end

  @impl Docker
  def image_history(image_id) do
    "#{@url}/images/#{image_id}/history"
    |> HTTPoison.get()
  end
end
