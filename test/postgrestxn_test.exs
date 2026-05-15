defmodule PostgRESTxnTest do
  use ExUnit.Case
  doctest PostgRESTxn

  test "greets the world" do
    assert PostgRESTxn.hello() == :world
  end
end
