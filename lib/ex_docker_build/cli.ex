defmodule ExDockerBuild.CLI do
  def main([]) do
    IO.puts "You forgot to pass the path to the Dockerfile"
  end

  def main([args | _]) do
    path = Path.expand(args)

    {:ok, _} =
      path
      |> ExDockerBuild.DockerfileParser.parse_file!()
      |> ExDockerBuild.DockerBuild.build(path)
  end
end
