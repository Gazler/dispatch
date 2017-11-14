defmodule Dispatch.HashRingServer do
  @moduledoc false

  alias Dispatch.HashRings

  def start_link(opts \\ []) do
    name = Keyword.fetch!(opts, :name)
    opts = [name: Module.concat(name, HashRing)]
    GenServer.start_link(__MODULE__, [], opts)
  end

  @doc false
  def init(_) do
    {:ok, HashRings.new()}
  end

  def handle_call({:get, type}, _reply, state) do
    {:reply, HashRings.get(state, type), state}
  end

  def handle_call({:get, type, :allow_offline}, _reply, state) do
    {:reply, HashRings.get(state, type, allow_disabled: true), state}
  end

  def handle_call({:disable_service, type, service_info}, _reply, state) do
    {:reply, :ok, HashRings.disable(state, type, service_info)}
  end

  def handle_call({:enable_service, type, service_info}, _reply, state) do
    {:reply, :ok, HashRings.enable(state, type, service_info)}
  end

  def handle_call({:sync, events}, _reply, state) do
    {:reply, :ok, HashRings.sync(state, events)}
  end
end
