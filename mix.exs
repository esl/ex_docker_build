defmodule ExDockerBuild.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_docker_build,
      version: "0.5.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [flags: [:error_handling, :race_conditions, :underspecs]],
      package: package(),
      description: description(),
      escript: [main_module: ExDockerBuild.CLI]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExDockerBuild.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.3.0"},
      {:hackney, "~> 1.13.0"},
      {:poison, "~> 4.0"},
      {:excoveralls, "~> 0.9", only: :test},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev], runtime: false},
      {:mock, "~> 0.3.2", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true},
    ]
  end

  defp description() do
    "Docker remote API client written in elixir for building docker images with support for bind mounting hosts file system at build time"
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/sescobb27/ex_docker_build"},
      source_url: "https://github.com/sescobb27/ex_docker_build",
      homepage_url: "https://github.com/sescobb27/ex_docker_build"
    ]
  end
end
