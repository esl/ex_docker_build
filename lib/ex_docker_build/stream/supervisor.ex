defmodule ExDockerBuild.Stream.Supervisor do
  @moduledoc false
  # Supervisor for Docker HTTP Stream backend GenServers

  use DynamicSupervisor

  alias ExDockerBuild.Stream.Worker

  # API functions

  def new_worker(url, opts) do
    DynamicSupervisor.start_child(__MODULE__, {Worker, [url, opts]})
  end

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
