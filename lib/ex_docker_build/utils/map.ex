defmodule ExDockerBuild.Utils.Map do
  @spec contextual_merge(map(), map()) :: map()
  def contextual_merge(map1, map2) do
    Map.merge(map1, map2, fn
      # same value: do nothing
      _, value, value ->
        value

      # key does not exists or is nil in the other context
      _, nil, value ->
        value

      _, value, nil ->
        value

      # merge deep maps with the same merge logic
      _, value1, value2 when is_map(value1) and is_map(value2) ->
        contextual_merge(value1, value2)

      # concat lists of values
      _, value1, value2 when is_list(value1) and is_list(value2) ->
        value1 ++ value2

      # else override existing value
      _, _, value2 ->
        value2
    end)
  end
end
