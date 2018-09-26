defmodule DockerRemoteAPI do
  @version "v1.37"
  @endpoint URI.encode_www_form("/var/run/docker.sock")
  @protocol "http+unix"
  @url "#{@protocol}://#{@endpoint}/#{@version}"
  @json_header {"Content-Type", "application/json"}
  @tar_header {"Content-Type", "application/tar"}

  @type image_id :: String.t()
  @type container_id :: String.t()

  def commit(container_id, payload) do
    "#{@url}/commit"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"container" => container_id}))
    |> URI.to_string()
    |> HTTPoison.post(Poison.encode!(payload), [@json_header])
  end

  def create_container(payload, params \\ %{}) do
    name = Map.get(payload, "ContainerName", "")

    params = if name != "", do: Map.merge(params, %{name: name}), else: params

    "#{@url}/containers/create"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
    |> HTTPoison.post(Poison.encode!(payload), [@json_header])
  end

  def remove_container(container_id, params \\ %{}) do
    "#{@url}/containers/#{container_id}"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
    |> HTTPoison.delete()
  end

  def start_container(container_id, params \\ %{}) do
    HTTPoison.post("#{@url}/containers/#{container_id}/start", "", [])
  end

  def stop_container(container_id) do
    "#{@url}/containers/#{container_id}/stop"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{t: 5}))
    |> URI.to_string()
    |> HTTPoison.post("", [], timeout: 30_000, recv_timeout: 30_000)
  end

  def wait_container(container_id, timeout \\ :infinity) do
    HTTPoison.post("#{@url}/containers/#{container_id}/wait", "", [],
      timeout: timeout,
      recv_timeout: timeout
    )
  end

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

  def pull(image) do
    # TODO:  ADD support for X-Registry-Auth
    "#{@url}/images/create"
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"fromImage" => image}))
    |> URI.to_string()
    |> HTTPoison.post("", [], timeout: :infinity, recv_timeout: :infinity)
  end

  def create_volume(payload) do
    HTTPoison.post("#{@url}/volumes/create", Poison.encode!(payload), [@json_header])
  end
end
