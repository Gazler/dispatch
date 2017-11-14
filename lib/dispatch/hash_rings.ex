defmodule Dispatch.HashRings do
  @moduledoc false

  defstruct enabled: %{},
            disabled: %{}

  def new() do
    %__MODULE__{}
  end

  def get(hash_rings, type, opts \\ []) do
    hash_rings =
      if Keyword.get(opts, :allow_disabled) && Map.has_key?(hash_rings.disabled, type) do
        hash_rings.disabled
      else
        hash_rings.enabled
      end

    Map.get(hash_rings, type, {:error, :no_nodes})
  end

  def disable(hash_rings, type, node) do
    disabled_hash_ring = Map.get(hash_rings.disabled, type)
    enabled_hash_ring = Map.get(hash_rings.enabled, type)

    case {node_present?(enabled_hash_ring, node), disabled_hash_ring, enabled_hash_ring} do
      {true, %HashRing{}, %HashRing{}} ->
        remove_node(hash_rings, type, node)

      {true, _, %HashRing{} = hash_ring} ->
          hash_rings
          |> clone_to_disabled(type, hash_ring)
          |> remove_node(type, node)

      _ ->
        hash_rings
    end
  end

  def enable(hash_rings, type, node) do
    disabled_hash_ring = Map.get(hash_rings.disabled, type)
    enabled_hash_ring = Map.get(hash_rings.enabled, type) || HashRing.new()

    case {node_present?(disabled_hash_ring, node), disabled_hash_ring, enabled_hash_ring} do
      {true, %HashRing{}, %HashRing{}} ->
        hash_rings
        |> add_node(type, node)
        |> delete_disabled_if_equal(type)

      _ ->
        hash_rings
        |> add_node(type, node)
        |> add_node_to_disabled(type, node)
    end
  end

  def sync(hash_rings, events) do
    Enum.reduce(events, hash_rings, fn {type, {joins, leaves}}, acc ->
      enabled_joins = Keyword.get_values(joins, :enabled)
      disabled_joins = Keyword.get_values(joins, :disabled)

      enabled_hash_ring =
          Map.get(acc.enabled, type)
          |> sync_remove_leaves(leaves)
          |> sync_add_enabled_joins(enabled_joins)
          |> sync_remove_disabled_joins(disabled_joins)


      disabled_hash_ring =
        Map.get(acc.disabled, type)
        |> sync_remove_leaves(leaves)
        |> sync_add_disabled_joins(disabled_joins, enabled_hash_ring)

      acc
      |> sync_set_enabled(type, enabled_hash_ring)
      |> sync_set_disabled(type, disabled_hash_ring)
      |> delete_disabled_if_equal(type)
    end)
  end

  defp sync_remove_leaves(hash_ring, leaves) do
    enabled_leaves = Keyword.get_values(leaves, :enabled)
    disabled_leaves = Keyword.get_values(leaves, :disabled)
    leaves = Enum.uniq(enabled_leaves ++ disabled_leaves)

    Enum.reduce(leaves, hash_ring, fn
      _, nil -> nil
      leave, hash_ring -> HashRing.remove_node(hash_ring, leave)
    end)
  end

  defp sync_add_enabled_joins(hash_ring, joins) do
    hash_ring = hash_ring || HashRing.new()
    Enum.reduce(joins, hash_ring, fn join, hash_ring ->
      HashRing.add_node(hash_ring, join)
    end)
  end

  defp sync_remove_disabled_joins(hash_ring, joins) do
    hash_ring = hash_ring || HashRing.new()
    Enum.reduce(joins, hash_ring, fn join, hash_ring ->
      HashRing.remove_node(hash_ring, join)
    end)
  end

  defp sync_add_disabled_joins(hash_ring, joins, clone_hash_ring) do
    hash_ring = hash_ring || clone_hash_ring
    Enum.reduce(joins, hash_ring, fn join, hash_ring ->
      HashRing.add_node(hash_ring, join)
    end)
  end

  defp sync_set_enabled(hash_rings, _type, nil), do: hash_rings
  defp sync_set_enabled(%{enabled: enabled} = hash_rings, type, hash_ring) do
    enabled = Map.put(enabled, type, hash_ring)
    %{hash_rings | enabled: enabled}
  end

  defp sync_set_disabled(hash_rings, _type, nil), do: hash_rings
  defp sync_set_disabled(%{disabled: disabled} = hash_rings, type, hash_ring) do
    disabled = Map.put(disabled, type, hash_ring)
    %{hash_rings | disabled: disabled}
  end

  defp node_present?(nil, _), do: false
  defp node_present?(hash_ring, node), do: node in HashRing.nodes(hash_ring)

  defp remove_node(%{enabled: enabled} = hash_rings, type, node) do
    hash_ring =
      enabled
      |> Map.get(type)
      |> HashRing.remove_node(node)

    %{hash_rings | enabled: Map.put(enabled, type, hash_ring)}
  end

  defp clone_to_disabled(%{disabled: disabled} = hash_rings, type, hash_ring) do
    disabled = Map.put(disabled, type, hash_ring)
    %{hash_rings | disabled: disabled}
  end

  defp delete_disabled_if_equal(%{enabled: enabled, disabled: disabled} = hash_rings, type) do
    disabled_hash_ring = Map.get(disabled, type) || HashRing.new()
    enabled_hash_ring = Map.get(enabled, type) || HashRing.new()

    disabled =
      if MapSet.new(HashRing.nodes(enabled_hash_ring)) ==
        MapSet.new(HashRing.nodes(disabled_hash_ring)) do
        Map.delete(hash_rings.disabled, type)
      else
        hash_rings.disabled
      end

    %{hash_rings | disabled: disabled}
  end

  defp add_node(%{enabled: enabled} = hash_rings, type, node) do
    hash_ring =
      enabled
      |> Map.get(type)
      |> Kernel.||(HashRing.new())
      |> HashRing.add_node(node)

    %{hash_rings | enabled: Map.put(enabled, type, hash_ring)}
  end

  defp add_node_to_disabled(%{disabled: disabled} = hash_rings, type, node) do
    disabled =
      case Map.get(disabled, type) do
        %HashRing{} = hash_ring ->
          hash_ring = HashRing.add_node(hash_ring, node)
          Map.put(disabled, type, hash_ring)
        _ ->
          disabled
      end

    %{hash_rings | disabled: disabled}
  end
end
