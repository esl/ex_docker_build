defmodule ExDockerBuild.DockerBuild do
  require Logger

  @env ~r/^\s*(\w+)[\s=]+(.*)$/
  @flag ~r/^\s*--(\w+)[\s=]+(.*)$$/

  alias ExDockerBuild.Utils.Map, as: MapUtils
  alias ExDockerBuild.API.Docker

  @spec build(list(String.t()), Path.t()) :: {:ok, Docker.image_id()} | {:error, any()}
  def build(instructions, path) do
    steps = length(instructions)

    try do
      {ctx, _} =
        instructions
        |> Enum.reduce({%{}, 1}, fn {cmd, args}, {context, step} ->
          cmd = String.upcase(cmd)
          Logger.info("STEP #{step}/#{steps} : #{cmd} #{args}")

          case exec({cmd, args}, context, path) do
            {:error, error} ->
              # fail fast
              throw(error)

            {:ok, new_image_id} when is_binary(new_image_id) ->
              {Map.put(context, "Image", new_image_id), step + 1}

            new_ctx when is_map(new_ctx) ->
              {new_ctx, step + 1}
          end
        end)

      {:ok, Map.fetch!(ctx, "Image")}
    catch
      error ->
        {:error, error}
    end
  end

  defp exec({"ENV", args}, context, _path) do
    # add support for both `ENV MIX_ENV prod` and `ENV MIX_ENV=prod`
    env = Regex.run(@env, args, capture: :all_but_first)
    unless env, do: raise("invalid env")

    Map.merge(context, %{"Env" => [Enum.join(env, "=")]})
    |> ExDockerBuild.create_layer()
  end

  defp exec({"RUN", command}, context, _path) do
    command =
      case parse_args(command) do
        {:shell_form, _cmd} ->
          ["/bin/sh", "-c", command]

        {:exec_form, cmd} ->
          ["/bin/sh", "-c" | cmd]
      end

    Map.merge(context, %{"CMD" => command})
    |> ExDockerBuild.create_layer(wait: true)
  end

  defp exec({"FROM", image}, context, _path) do
    [base_image | rest] = String.split(image)
    # support for `FROM elixir:latest as elixir` and `FROM elixir:latest`
    name =
      case rest do
        [] -> ""
        [as, container_name] when as in ["AS", "as"] -> container_name
      end

    new_context = Map.merge(context, %{"Image" => base_image, "ContainerName" => name})

    with :ok <- ExDockerBuild.pull(base_image),
         {:ok, new_image_id} <- ExDockerBuild.create_layer(new_context) do
      %{new_context | "Image" => new_image_id}
    else
      {:error, _} = error ->
        error
    end
  end

  # TODO:
  # Add support for --chown
  # Add support for ["src", "dest"] (paths with whitespaces)
  # Add support for multiple src
  defp exec({"COPY", args}, context, path) do
    {flags, [origin, dest]} = parse_copy_args(args)

    Enum.find(flags, fn {flag, value} ->
      if flag == "from", do: value
    end)
    |> case do
      nil ->
        absolute_origin = [path, origin] |> Path.join() |> Path.expand()
        copy_from_file_system(absolute_origin, dest, context)

      {_from, name} ->
        copy_from_other_container(name, origin, dest, context)
    end
  end

  defp exec({"WORKDIR", wd_path}, context, _path) do
    Map.merge(context, %{"WorkingDir" => wd_path})
    |> ExDockerBuild.create_layer()
  end

  defp exec({"CMD", command}, context, _path) do
    command =
      case parse_args(command) do
        {:shell_form, cmd} -> String.split(cmd, " ")
        {:exec_form, cmd} -> cmd
      end

    Map.merge(context, %{"CMD" => command})
    |> ExDockerBuild.create_layer()
  end

  defp exec({"ENTRYPOINT", command}, context, _path) do
    command =
      case parse_args(command) do
        {:shell_form, cmd} -> String.split(cmd, " ")
        {:exec_form, cmd} -> cmd
      end

    Map.merge(context, %{"ENTRYPOINT" => command})
    |> ExDockerBuild.create_layer()
  end

  # TODO:
  # defp exec({"LABEL", args}, context, _path) do
  # end

  defp exec({"EXPOSE", args}, context, _path) do
    args =
      if not String.contains?(args, "/") do
        args <> "/tcp"
      else
        args
      end

    Map.merge(context, %{"ExposedPorts" => %{"#{args}" => %{}}})
    |> ExDockerBuild.create_layer()
  end

  # defp exec({"ARG", args}, context, _path) do
  # end

  # Supports:
  # VOLUME volume_name for named volumes
  # VOLUME /path/in/host:/path/in/container for bind mounting a directory
  # VOLUME volume_name:/path/in/container for mounting a named volume
  # doesn't support standard VOLUME /path/in/container
  defp exec({"VOLUME", args}, context, _path) do
    if args =~ ":" do
      [src, dst | _] = String.split(args, ":")
      absolute_src = Path.expand(src)
      expanded_mount = absolute_src <> ":" <> dst

      mounts = %{
        "HostConfig" => %{
          "Binds" => [expanded_mount]
        }
      }

      Map.merge(context, mounts)
      |> ExDockerBuild.create_layer()
      |> case do
        {:ok, new_image_id} ->
          new_ctx =
            %{"Image" => new_image_id}
            |> Map.merge(mounts)

          MapUtils.contextual_merge(context, new_ctx)

        {:error, _} = error ->
          error
      end
    else
      case ExDockerBuild.create_volume(%{"Name" => args}) do
        :ok ->
          context

        {:error, _} = error ->
          error
      end
    end
  end

  # parse instruction arguments as shell form `CMD command param1 param2` and
  # as exec form `CMD ["executable","param1","param2"]` or JSON Array form
  defp parse_args(args) do
    case Poison.decode(args) do
      {:error, _error} -> {:shell_form, args}
      {:ok, value} -> {:exec_form, value}
    end
  end

  defp copy_from_other_container(name, origin, _dest, _context) do
    with {:ok, 200} <- ExDockerBuild.get_archive(name, origin) do
      {:ok, :copied}
    else
      {:error, _} = error ->
        error
    end
  end

  defp copy_from_file_system(origin, dest, context) do
    with {:ok, container_id} <- ExDockerBuild.create_container(context),
         {:ok, ^container_id} <- ExDockerBuild.start_container(container_id),
         {:ok, ^container_id} <- ExDockerBuild.upload_file(container_id, origin, dest),
         {:ok, new_image_id} <- ExDockerBuild.commit(container_id, %{}),
         {:ok, ^container_id} <- ExDockerBuild.stop_container(container_id),
         :ok <- ExDockerBuild.remove_container(container_id) do
      {:ok, new_image_id}
    else
      {:error, _} = error ->
        error
    end
  end

  defp parse_copy_args(args) do
    {flags, paths} =
      args
      |> String.split(" ")
      |> Enum.reduce({[], []}, fn arg, {flags, paths} ->
        case Regex.run(@flag, arg, capture: :all_but_first) do
          nil ->
            {flags, [arg | paths]}

          [flag, value] ->
            {[{flag, value} | flags], paths}
        end
      end)

    {flags, Enum.reverse(paths)}
  end
end
