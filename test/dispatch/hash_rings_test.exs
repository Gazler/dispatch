defmodule Dispatch.HashRingsTest do
  use ExUnit.Case, async: false
  alias Dispatch.{HashRings}

  test "The hash rings have online and offline nodes for each type" do
    hash_rings =
      HashRings.new()
      |> HashRings.enable("foo", 1)
      |> HashRings.enable("foo", 2)
      |> HashRings.disable("foo", 2)
      |> HashRings.enable("foo", 3)
      |> HashRings.disable("foo", 1)
      |> HashRings.enable("bar", 1)
      |> HashRings.enable("bar", 2)

    assert_nodes(HashRings.get(hash_rings, "foo"), [3])
    assert_nodes(HashRings.get(hash_rings, "foo", allow_disabled: true), [1, 2, 3])
    assert_nodes(HashRings.get(hash_rings, "bar"), [1, 2])
    assert_nodes(HashRings.get(hash_rings, "bar", allow_disabled: true), [1, 2])
  end

  test "The disabled version is removed when there is node parity" do
    hash_rings =
      HashRings.new()
      |> HashRings.enable("foo", 1)
      |> HashRings.enable("foo", 2)
      |> HashRings.enable("foo", 3)
      |> HashRings.disable("foo", 2)

    assert Map.has_key?(hash_rings.disabled, "foo")

    hash_rings = HashRings.enable(hash_rings, "foo", 2)

    refute Map.has_key?(hash_rings.disabled, "foo")

    assert_nodes(HashRings.get(hash_rings, "foo"), [1, 2, 3])
    assert_nodes(HashRings.get(hash_rings, "foo", allow_disabled: true), [1, 2, 3])
  end

  test "sync updates the state of all the hash rings" do
    foo_joins = [enabled: 1, enabled: 3]
    foo_leaves = [enabled: 2]

    bar_joins = [enabled: 1, disabled: 3]
    bar_leaves = [disabled: 4]

    baz_joins = [disabled: 1, disabled: 3]
    baz_leaves = [enabled: 2, disabled: 4]

    events = %{
      "foo" => {foo_joins, foo_leaves},
      "bar" => {bar_joins, bar_leaves},
      "baz" => {baz_joins, baz_leaves}
    }

    hash_rings =
      HashRings.new()
      |> HashRings.enable("foo", 1)
      |> HashRings.enable("foo", 2)
      |> HashRings.disable("foo", 2)
      |> HashRings.enable("foo", 3)
      |> HashRings.disable("foo", 1)
      |> HashRings.enable("bar", 1)
      |> HashRings.enable("bar", 2)
      |> HashRings.sync(events)

    assert_nodes(HashRings.get(hash_rings, "foo"), [1, 3])
    assert_nodes(HashRings.get(hash_rings, "foo", allow_disabled: true), [1, 3])
    refute Map.has_key?(hash_rings.disabled, "foo")

    assert_nodes(HashRings.get(hash_rings, "bar"), [1, 2])
    assert_nodes(HashRings.get(hash_rings, "bar", allow_disabled: true), [1, 2, 3])

    assert_nodes(HashRings.get(hash_rings, "baz"), [])
    assert_nodes(HashRings.get(hash_rings, "baz", allow_disabled: true), [1, 3])
  end

  defp assert_nodes(hash_ring, eq) do
    assert hash_ring |> HashRing.nodes() |> MapSet.new() == MapSet.new(eq)
  end
end
