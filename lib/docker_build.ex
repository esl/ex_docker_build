defmodule ExDockerBuild.DockerBuild do
  require Logger

  @env ~r/^\s*(\w+)[\s=]+(.*)$/

  alias ExDockerBuild.Utils.Map, as: MapUtils

  @spec build(list(String.t()), Path.t()) :: {:ok, DockerRemoteAPI.image_id()} | {:error, any()}
  def(build(instructions, path)) do
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

    ExDockerBuild.pull(base_image)

    Map.merge(context, %{"Image" => base_image, "ContainerName" => name})
    |> ExDockerBuild.create_layer()
  end

  defp exec({"COPY", args}, context, path) do
    [origin, dest] = String.split(args, " ")
    absolute_origin = [path, origin] |> Path.join() |> Path.expand()

    with {:ok, container_id} <- ExDockerBuild.create_container(context),
         {:ok, ^container_id} <- ExDockerBuild.start_container(container_id),
         {:ok, ^container_id} <- ExDockerBuild.upload_file(container_id, absolute_origin, dest),
         {:ok, new_image_id} <- ExDockerBuild.commit(container_id, %{}),
         {:ok, ^container_id} <- ExDockerBuild.stop_container(container_id),
         :ok <- ExDockerBuild.remove_container(container_id) do
      {:ok, new_image_id}
    else
      {:error, _} = error ->
        error
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

  # defp exec({"EXPOSE", args}, context, _path) do
  # end

  # defp exec({"ARG", args}, context, _path) do
  # end

  defp exec({"VOLUME", args}, context, _path) do
    String.split(args, ":")
    |> case do
      [_volume] ->
        {:error, "Only Bind Mounts are Supported"}

      [_src, _dst] ->
        mounts = %{
          "HostConfig" => %{
            "Binds" => [args]
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
end
