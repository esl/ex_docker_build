defmodule ExDockerBuild.Utils.MapTest do
  use ExUnit.Case, async: true

  alias ExDockerBuild.Utils.Map, as: MapUtils

  describe "contextual_merge/2" do
    test "merges 2 maps based on rules - same value" do
      map1 = %{key1: "some"}
      map2 = %{key1: "some"}
      assert %{key1: "some"} == MapUtils.contextual_merge(map1, map2)
    end

    test "merges 2 maps based on rules - nil values" do
      map1 = %{key1: nil, key2: "some"}
      map2 = %{key2: nil, key1: "some"}
      assert %{key1: "some", key2: "some"} == MapUtils.contextual_merge(map1, map2)
    end

    test "merges 2 maps based on rules - deep map values" do
      volumes1 = %{
        "Volumes" => %{
          "/data" => %{}
        }
      }

      volumes2 = %{
        "Volumes" => %{
          "/tmp" => %{}
        }
      }

      assert %{
               "Volumes" => %{
                 "/data" => %{},
                 "/tmp" => %{}
               }
             } == MapUtils.contextual_merge(volumes1, volumes2)
    end

    test "merges 2 maps based on rules - deep map values with list" do
      mounts1 = %{
        "HostConfig" => %{
          "Binds" => ["/Users/kiro/test:/data"]
        }
      }

      mounts2 = %{
        "HostConfig" => %{
          "Binds" => ["/tmp:/tmp"]
        }
      }

      assert %{
               "HostConfig" => %{
                 "Binds" => ["/Users/kiro/test:/data", "/tmp:/tmp"]
               }
             } == MapUtils.contextual_merge(mounts1, mounts2)
    end

    test "merges 2 maps based on rules - overrida values" do
      ctx1 = %{
        "Image" => "old_image_id"
      }

      ctx2 = %{
        "Image" => "new_image_id"
      }

      assert %{"Image" => "new_image_id"} == MapUtils.contextual_merge(ctx1, ctx2)
    end
  end
end
