defmodule Dispatch.Cluster do
  alias Dispatch.Helper
  alias __MODULE__
  @timeout 5_000

  def spawn do
    # Turn node into a distributed node with the given long name
    :net_kernel.start([:"master@127.0.0.1"])

    # Allow slave nodes to fetch all code from this node
    :erl_boot_server.start([])
    allow_boot to_char_list("127.0.0.1")

    # Start configured nodes as slaves
    nodes = Application.get_env(:phoenix_pubsub, :nodes, [])

    nodes
    |> Enum.map(&Task.async(fn -> spawn_node(&1) end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  defp spawn_node(node_host) do
    slave = case :slave.start(to_char_list("127.0.0.1"), node_name(node_host), inet_loader_args()) do
      {:ok, slave} -> slave
      other ->
        IO.puts "error! #{inspect other}"
        nil
    end
    add_code_paths(slave)
    transfer_configuration(slave)
    ensure_applications_started(slave)
    {:ok, slave}
  end

  defp rpc(slave, module, method, args) do
    :rpc.block_call(slave, module, method, args)
  end

  defp inet_loader_args do
    to_char_list("-loader inet -hosts 127.0.0.1 -setcookie #{:erlang.get_cookie()}")
  end

  defp allow_boot(host) do
    {:ok, ipv4} = :inet.parse_ipv4_address(host)
    :erl_boot_server.add_slave(ipv4)
  end

  defp add_code_paths(slave) do
    :rpc.block_call(slave, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(slave) do
    for {app_name, _, _} <- Application.loaded_applications do
      for {key, val} <- Application.get_all_env(app_name) do
        rpc(slave, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(slave) do
    rpc(slave, Application, :ensure_all_started, [:mix])
    rpc(slave, Mix, :env, [Mix.env()])
    for {app_name, _, _} <- Application.loaded_applications do
      rpc(slave, Application, :ensure_all_started, [app_name])
    end
  end

  defp node_name(node_host) do
    node_host
    |> to_string
    |> String.split("@")
    |> Enum.at(0)
    |> String.to_atom
  end

  def call_node(node, func) do
    parent = self()
    ref = make_ref()

    pid = Node.spawn_link(node, fn ->
      result = func.()
      send parent, {ref, result}
      ref = Process.monitor(parent)
      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end
    end)

    receive do
      {^ref, result} -> {pid, result}
    after
      @timeout -> {pid, {:error, :timeout}}
    end
  end

  def setup_remote_registry(func) do
    Application.get_env(:phoenix_pubsub, :nodes, [])
    |> Enum.map(&(Cluster.call_node(&1, func)))
  end

end
