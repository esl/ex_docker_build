defmodule ExDockerBuild.Stream.Supervisor do
  @moduledoc false
  # Supervisor for Docker HTTP Stream backend GenServers

  use Supervisor

  alias ExDockerBuild.Stream.Worker

  # API functions

  def new_worker(url, opts) do
    Supervisor.start_child(__MODULE__, [url, opts])
  end

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      worker(Worker, [], restart: :temporary)
    ]

    Supervisor.init(children, strategy: :simple_one_for_one)
  end
end
