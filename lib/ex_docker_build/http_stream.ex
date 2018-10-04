defmodule ExDockerBuild.HttpStream do
  @moduledoc """
  This module exposes API for wrapping HTTP requests into Stream
  """

  alias ExDockerBuild.Stream.{Worker, Supervisor}

  @doc """
    Returns HTTP response wrapped into Stream.
  """
  @spec new_stream(String.t()) :: Enum.t()
  def new_stream(url, opts \\ []) do
    Stream.resource(init_fun(url, opts), &next_fun/1, &after_fun/1)
  end

  # Function called to initialize Stream
  defp init_fun(url, opts) do
    fn ->
      {:ok, pid} = Supervisor.new_worker(url, opts)
      pid
    end
  end

  # Function called where there is demand for new element
  defp next_fun(pid) do
    case Worker.get_chunk(pid) do
      {:chunk, chunk} -> {[chunk], pid}
      :halt -> {:halt, pid}
    end
  end

  # Function called when stream is finished, used for clean_up
  defp after_fun(pid) do
    Worker.stop(pid)
  end
end
