defmodule ExDockerBuild.API.Docker do
  alias HTTPoison.{Response, Error}

  @type image_id :: String.t()
  @type container_id :: String.t()
  @type repository_name :: String.t()
  @type tag_name :: String.t()
  @type docker_credentials :: %{
          required(:docker_username) => String.t(),
          required(:docker_password) => String.t(),
          required(:docker_servername) => String.t()
        }

  @callback commit(container_id(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback delete_image(image_id(), boolean()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback create_container(map(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback remove_container(container_id(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback start_container(container_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback stop_container(container_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback wait_container(container_id(), pos_integer() | :infinity) ::
              {:ok, Response.t()} | {:error, Error.t()}
  @callback containers_logs(container_id(), params, keyword()) ::
              {:ok, list(String.t())} | {:error, any()}
            when params: %{
                   optional(:stdout) => 1 | 0,
                   optional(:stderr) => 1 | 0,
                   optional(:tail) => pos_integer() | String.t(),
                   optional(:timestamps) => 1 | 0,
                   optional(:follow) => 1 | 0
                 }
  @callback upload_file(container_id(), Path.t(), Path.t()) ::
              {:ok, Response.t()} | {:error, Error.t()}
  @callback pull(image_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback create_volume(map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback push_image(image_id(), String.t(), docker_credentials()) ::
              {:ok, Response.t()} | {:error, Error.t()}
  @callback tag_image(image_id(), repository_name(), tag_name(), docker_credentials()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback container_inspect(container_id(), boolean()) ::
              {:ok, Response.t()} | {:error, Error.t()}
end
