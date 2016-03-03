defmodule ClusterMember.Core do
  require Logger

  @sync_dir "/tmp/sync_dir/"
  @interval 1_000

  def start() do
    loop
  end

  def loop do
    sign_as_active_node
    status = inspect check_active_nodes
    Logger.info(Atom.to_string(Node.self) <> status)
    :timer.sleep(@interval)
    loop
  end

  def sign_as_active_node do
    File.mkdir_p @sync_dir
    {:ok, file} = File.open(path, [:write])
    IO.binwrite(file, time_now_as_string)
    File.close file
  end

  def check_active_nodes do
    active_nodes
      |> Enum.map(&(String.to_atom &1))
      |> Enum.map(&({&1, Node.ping(&1) == :pong}))
  end

  def active_nodes do
    {:ok, active_members} = File.ls(@sync_dir)
    active_members
  end

  def path do
    @sync_dir <> Atom.to_string(Node.self)
  end

  def time_now_as_string do
    inspect :calendar.universal_time
  end

  def name_at_ip(name) do
    Enum.join([name, my_ip], "@")
  end

  def my_ip do
    System.get_env("MY_IP") || "127.0.0.1"
  end

  def rand_string(length \\ 10) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64
    |> String.replace("-", "_")
    |> binary_part(0, length)
  end
end
