defmodule WikiParserTest do
  use ExUnit.Case
  doctest WikiParser

  test "greets the world" do
    assert WikiParser.hello() == :world
  end
end
