defmodule SmartSort.Helpers.WithHelpersTest do
  use ExUnit.Case

  alias SmartSort.Helpers.WithHelpers

  describe "check/2" do
    test "returns :ok when condition is true" do
      result = WithHelpers.check(true, "error message")
      assert result == :ok
    end

    test "returns error tuple when condition is false" do
      result = WithHelpers.check(false, "error message")
      assert result == {:error, "error message"}
    end

    test "handles different error messages" do
      result1 = WithHelpers.check(false, "first error")
      result2 = WithHelpers.check(false, "second error")

      assert result1 == {:error, "first error"}
      assert result2 == {:error, "second error"}
    end

    test "ignores error message when condition is true" do
      result = WithHelpers.check(true, "this should be ignored")
      assert result == :ok
    end
  end
end
