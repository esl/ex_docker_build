defmodule ExDockerBuild.Integration.HttpStreamTest do
  use ExUnit.Case, async: true

  alias ExDockerBuild.HttpStream

  @moduletag :integration

  describe "http streaming with success codes" do
    test "streams 301 redirects" do
      result =
        "https://google.com"
        |> HttpStream.new_stream()
        |> Enum.to_list()

      refute result == ""
    end

    test "streams 200 success" do
      result =
        "https://www.google.com"
        |> HttpStream.new_stream()
        |> Enum.to_list()

      refute result == ""
    end
  end

  describe "http streaming with error codes" do
    # Silence GenServer crash
    @tag capture_log: true
    test "exits on invalid url" do
      stream = HttpStream.new_stream("fake_url")
      assert {:noproc, _} = catch_exit(Stream.run(stream))
    end

    # Silence GenServer crash
    @tag capture_log: true
    test "exits on 404 " do
      stream = HttpStream.new_stream("https://github.com/fakeuser/f@k3")
      assert {:noproc, _} = catch_exit(Stream.run(stream))
    end
  end
end
