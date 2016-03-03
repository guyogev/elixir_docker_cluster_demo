defmodule ClusterMember do
  use Application

  def start(_type, _args) do
    ClusterMember.Core.start
  end
end