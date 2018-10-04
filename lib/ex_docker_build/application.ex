defmodule ExDockerBuild.Application do
  @moduledoc false

  use Application

  alias ExDockerBuild.Stream

  def start(_type, _args) do
    children = [
      {Stream.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: ExDockerBuild.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
