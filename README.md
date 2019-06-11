# Docker Build Clone using Elixir

[![Build Status](https://travis-ci.org/esl/ex_docker_build.svg?branch=master)](https://travis-ci.org/esl/ex_docker_build)
[![Coverage Status](https://coveralls.io/repos/github/esl/ex_docker_build/badge.svg)](https://coveralls.io/github/esl/ex_docker_build)

## What's the special thing about this?

This comes with support for **Bind Mounts at Build Time**

![Bind Mount at Build Time](https://user-images.githubusercontent.com/31992054/46028189-d2b73300-c0e7-11e8-9c78-3575f652bc98.png)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_docker_build` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_docker_build, "~> 0.6.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ex_docker_build](https://hexdocs.pm/ex_docker_build).

## Usage

### Example 1 - **Elixir Release with Distillery**

Clone the following example in a directory you wish

```sh
$> mkdir ~/workspace
$> cd workspace
$> git clone https://github.com/sescobb27/elixir-docker-guide
```

Start a mix session with `iex -S mix` and type the following instructions

```ex
path = Path.expand("~/workspace/elixir-docker-guide")

{:ok, image_id} = Path.join([path, "Dockerfile"]) |>
  ExDockerBuild.DockerfileParser.parse_file!() |>
  ExDockerBuild.DockerBuild.build(path)
```

Or you can start using escript:

```ex
mix escript.build
Generated escript ex_docker_build
```

Then call the escript passing the path to a Dockerfile

```ex
./ex_docker_build ~/workspace/elixir-docker-guide/Dockerfile

[info]  image created d44264c48dad
```

Copy the image_id into your clipboard and run the image with docker like this

```sh
docker run d44264c48dad # d44264c48dad being the image_id
```

### Example 2 - **Docker Build with Bind Mount**

in `test/fixtures/Dockerfile_bind.dockerfile` in line 2 `VOLUME /Users/kiro/test:/data`
change `/Users/kiro/test` with your path of preference e.g `/Your/User/test`
(must be an absolute path, relative paths aren't supported yet)

```sh
$> mkdir ~/test
```

```ex
path = Path.expand("./test/fixtures")

{:ok, image_id} = Path.join([path, "Dockerfile_bind.dockerfile"]) |>
  ExDockerBuild.DockerfileParser.parse_file!() |>
  ExDockerBuild.DockerBuild.build(path)
```

Then if you run `ls ~/test` you should see a file named `myfile.txt` with
`hello world!!!` as content

## Environment and debugging

This library respects the environmental variable `DOCKER_HOST` this can be
very helpful when debugging, for example:

In on terminal run `socat` :

```
socat -v UNIX-LISTEN:/tmp/fake,fork UNIX-CONNECT:/var/run/docker.sock
```

In the terminal where you are running `ex_docker_build` set the docker socket :

```
export DOCKER_HOST=unix:///tmp/fake
```

Now you can observe all interactions with the Docker API server.

## Limitations

- Doesn't support relative paths in the container when `COPY`ing
  - `COPY ./relative/path/to/origin:/absolute/path/to/destination`
- Doesn't support standard `VOLUMES`, it only supports the following `VOLUME`s type
  with custom syntax
  - [Bind Mounts](https://docs.docker.com/storage/bind-mounts/) e.g `VOLUME ~/path/to/host/dir:/path/to/container/dir`
  - [Named Volumes](https://docs.docker.com/storage/volumes/) e.g `VOLUME volume_name` and then using it like `VOLUME volume_name:/path/to/container/dir`

## TODO:

- [ ] add support for more docker file instructions
- [ ] resolve TODOs inside the source code
