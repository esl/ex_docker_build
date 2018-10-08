defmodule ExDockerBuild.DockerfileParser do
  @comment ~r/^\s*#/
  @continuation ~r/^.*\\\s*$/
  @instruction ~r/^\s*(\w+)\s+(.*)$/

  @spec parse!(Path.t() | String.t()) :: list(String.t()) | no_return()
  def parse!(path_or_content) do
    content =
      if File.exists?(path_or_content) do
        File.read!(path_or_content)
      else
        path_or_content
      end

    {parsed_lines, _} =
      content
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {acc, continuation?} ->
        case parse_line(line, continuation?) do
          nil ->
            {acc, continuation?}

          {:continue, _} = result ->
            {join(result, acc), true}

          {:end, _} = result ->
            {join(result, acc), false}
        end
      end)

    Enum.reverse(parsed_lines)
  end

  @spec parse_line(String.t(), boolean()) ::
          nil
          | {:continue, String.t() | {String.t(), String.t()}}
          | {:end, String.t() | {String.t(), String.t()}}
  defp parse_line(line, continuation?) do
    line = String.trim(line)

    cond do
      line == "" || Regex.match?(@comment, line) ->
        nil

      # continuations are not instructions
      continuation? ->
        if Regex.match?(@continuation, line) do
          # remove trailing continuation (\)
          {:continue, String.slice(line, 0..-2)}
        else
          {:end, line}
        end

      true ->
        # line: "RUN set -xe \\"
        [command, value] = Regex.run(@instruction, line, capture: :all_but_first)
        # ["RUN set -xe \\", "RUN", "set -xe \\"]
        if Regex.match?(@continuation, line) do
          # remove trailing continuation (\)
          {:continue, {command, String.slice(value, 0..-2)}}
        else
          {:end, {command, value}}
        end
    end
  end

  @spec join(parsed_line, list()) :: list()
        when parsed_line:
               {:continue, String.t() | {String.t(), String.t()}}
               | {:end, String.t() | {String.t(), String.t()}}
  # first line - accumulator empty
  defp join({:continue, _} = val, []) do
    [val]
  end

  # a continuation of a previous continuation - need to join lines
  defp join({:continue, val}, [{:continue, {prev_command, prev_value}} | rest]) do
    [{:continue, {prev_command, prev_value <> " " <> val}} | rest]
  end

  # a new continuation - other continuation already finished
  defp join({:continue, _} = val, acc) do
    [val | acc]
  end

  # first line - single instruction
  defp join({:end, val}, []) do
    [val]
  end

  # the end of a continuation
  defp join({:end, val}, [{:continue, {prev_command, prev_value}} | rest]) do
    [{prev_command, prev_value <> " " <> val} | rest]
  end

  # single instruction
  defp join({:end, val}, acc) do
    [val | acc]
  end
end
