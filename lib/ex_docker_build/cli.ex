defmodule ExDockerBuild.CLI do
  def main([]) do
    IO.puts("You forgot to pass the path to the Dockerfile")
  end

  def main(args) do
    IO.inspect(args)
    path = Path.expand(args)

    {:ok, _} =
      Path.join([path, "Dockerfile"])
      |> ExDockerBuild.DockerfileParser.parse_file!()
      |> ExDockerBuild.DockerBuild.build(path)
  end
end
