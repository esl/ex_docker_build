defmodule ExDockerBuild.API.Docker do
  alias HTTPoison.{Response, Error}

  @type image_id :: String.t()
  @type container_id :: String.t()

  @callback commit(container_id(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback create_container(map(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback remove_container(container_id(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback start_container(container_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback stop_container(container_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback wait_container(container_id(), pos_integer() | :infinity) ::
              {:ok, Response.t()} | {:error, Error.t()}
  @callback upload_file(container_id(), Path.t(), Path.t()) ::
              {:ok, Response.t()} | {:error, Error.t()}
  @callback pull(image_id()) :: {:ok, Response.t()} | {:error, Error.t()}
  @callback create_volume(map()) :: {:ok, Response.t()} | {:error, Error.t()}
end
