defmodule ExDockerBuild.API.VolumeFilter do
  defstruct name: nil, dangling: nil
  @type t :: %__MODULE__{name: String.t() | nil, dangling: true | false | nil}
end
