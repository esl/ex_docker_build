defmodule ExDockerBuild.Stream.Worker do
  use GenServer, restart: :temporary

  @timeout 10_000

  defmodule State do
    alias __MODULE__

    @type t :: %__MODULE__{
            id: reference(),
            chunks: list(),
            more_chunks: boolean(),
            reply_to: pid()
          }
    defstruct id: nil, chunks: [], more_chunks: false, reply_to: nil

    def new, do: %State{}
  end

  # API

  @spec get_chunk(pid) :: {:chunk, String.t()} | :halt
  def get_chunk(name) do
    GenServer.call(name, :get_chunk)
  end

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec stop(pid) :: :ok
  def stop(name) do
    GenServer.stop(name)
  end

  # Callbacks

  def init([url, opts]) do
    GenServer.cast(self(), {:initalize, url, opts})
    {:ok, State.new()}
  end

  def handle_cast({:initalize, url, opts}, state) do
    timeout = Keyword.get(opts, :timeout, @timeout)
    %{id: resp_id} = HTTPoison.get!(url, [], stream_to: self(), recv_timeout: timeout)
    {:noreply, %{state | id: resp_id, more_chunks: true}}
  end

  # Server is replaying with chunk, if there is any in accumulator
  def handle_call(:get_chunk, _from, %{chunks: [chunk | rest]} = state) do
    state = %{state | chunks: rest}
    response = {:chunk, chunk}
    {:reply, response, state}
  end

  # Server is not replaying, as there are no chunks in accumulator. However we know that there will
  # be more chunks, as we did not received %HTTPostion.AsyncEnd yet
  def handle_call(:get_chunk, from, %{chunks: [], more_chunks: true} = state) do
    state = %{state | reply_to: from}
    {:noreply, state}
  end

  # Server is replaying with `:halt` atom to indicate there will be no more chunks. We know that,
  # because we received %HTTPostion.AsyncEnd
  def handle_call(:get_chunk, _from, %{chunks: [], more_chunks: false} = state) do
    {:reply, :halt, state}
  end

  # Server acumulates new chunk, when there is no client demanding chunk.
  def handle_info(
        %HTTPoison.AsyncChunk{id: id, chunk: chunk},
        %{id: id, chunks: chunks, reply_to: nil} = state
      ) do
    {:noreply, %{state | chunks: [chunk | chunks]}}
  end

  # Server do not accumulate new chunk, where there is a client waiting for a chunk. Instead of
  # storing it, chunk is send directly to client.
  def handle_info(%HTTPoison.AsyncChunk{id: id, chunk: chunk}, %{id: id, reply_to: pid} = state) do
    GenServer.reply(pid, {:chunk, chunk})
    {:noreply, %{state | reply_to: nil}}
  end

  # If there is the end of the Stream and there is no client waiting for chunk, server just marks
  # the end of the stream in its state.
  def handle_info(%HTTPoison.AsyncEnd{id: id}, %{id: id, reply_to: nil} = state) do
    {:noreply, %{state | more_chunks: false}}
  end

  # If there is the end of stream AND there is nothing in the accumulator AND there is a
  # client waiting for response we replay with `:halt` to indicate there won't be more chunks.
  def handle_info(%HTTPoison.AsyncEnd{id: id}, %{id: id, chunks: [], reply_to: pid} = state) do
    GenServer.reply(pid, :halt)
    state = %{state | more_chunks: false, reply_to: nil}
    {:noreply, state}
  end

  # Handle headers, do nothing
  def handle_info(%HTTPoison.AsyncHeaders{id: id}, %{id: id} = state) do
    {:noreply, state}
  end

  # Handle status, do nothing if successful (200, 201, 204, 301, 304 etc)
  def handle_info(%HTTPoison.AsyncStatus{code: code, id: id}, %{id: id} = state)
      when code >= 200 and code < 400 do
    {:noreply, state}
  end

  # Handle error codes
  def handle_info(%HTTPoison.AsyncStatus{code: code, id: id}, %{id: id} = state)
      when code >= 400 do
    {:stop, {:error, code}, state}
  end

  # stop if response there was an error
  def handle_info(%HTTPoison.Error{} = error, state) do
    {:stop, error, state}
  end
end
