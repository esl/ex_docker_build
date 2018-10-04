defmodule ExDockerBuild.Tar do
  @spec tar(Path.t(), Path.t()) :: {:ok, Path.t()} | {:error, {:file.filename(), any()}}
  def tar(input_path, output_path) do
    if File.dir?(input_path) do
      tar_dir(input_path, output_path)
    else
      tar_file(input_path, output_path)
    end
  end

  defp tar_dir(input_path, output_path) do
    files =
      input_path
      |> File.ls!()
      |> Enum.filter(&(!String.starts_with?(&1, ".git")))
      |> Enum.map(&Path.join(input_path, &1))

    filename = Path.basename(input_path)
    destination_path = Path.join([output_path, "#{filename}.tar"])
    do_tar(files, destination_path)
  end

  defp tar_file(input_path, output_path) do
    filename = Path.basename(input_path)
    destination_path = Path.join([output_path, "#{filename}.tar"])
    do_tar(input_path, destination_path)
  end

  defp do_tar(files, destination_path) when is_list(files) do
    files =
      Enum.map(files, fn file ->
        {Path.basename(file) |> to_charlist(), to_charlist(file)}
      end)

    case :erl_tar.create(destination_path, files) do
      :ok -> {:ok, destination_path}
      {:error, _} = error -> error
    end
  end

  defp do_tar(file, destination_path) do
    do_tar([file], destination_path)
  end
end
