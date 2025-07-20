defmodule SmartSort.Macros.NotFoundTest do
  use ExUnit.Case

  alias SmartSort.Macros.NotFound

  describe "struct creation" do
    test "creates struct with entity" do
      not_found = %NotFound{entity: SmartSort.Accounts.User}

      assert not_found.entity == SmartSort.Accounts.User
    end

    test "creates struct without entity" do
      not_found = %NotFound{}

      assert not_found.entity == nil
    end
  end

  describe "String.Chars implementation" do
    test "converts User module to string" do
      not_found = %NotFound{entity: SmartSort.Accounts.User}
      result = to_string(not_found)

      assert result == "user_not_found"
    end

    test "converts ConnectedAccount module to string" do
      not_found = %NotFound{entity: SmartSort.Accounts.ConnectedAccount}
      result = to_string(not_found)

      assert result == "connected_account_not_found"
    end

    test "converts Email module to string" do
      not_found = %NotFound{entity: SmartSort.Accounts.Email}
      result = to_string(not_found)

      assert result == "email_not_found"
    end

    test "converts Category module to string" do
      not_found = %NotFound{entity: SmartSort.Accounts.Category}
      result = to_string(not_found)

      assert result == "category_not_found"
    end

    test "handles module ending with 's'" do
      # Test with a hypothetical module ending with 's'
      not_found = %NotFound{entity: SmartSort.Accounts.Users}
      result = to_string(not_found)

      assert result == "user_not_found"
    end

    test "handles nil entity" do
      not_found = %NotFound{entity: nil}
      result = to_string(not_found)

      assert result == "nil_not_found"
    end
  end

  describe "Jason.Encoder implementation" do
    test "encodes to JSON string" do
      not_found = %NotFound{entity: SmartSort.Accounts.User}
      result = Jason.encode!(not_found)

      assert result == "\"user_not_found\""
    end

    test "encodes different entities to JSON" do
      not_found = %NotFound{entity: SmartSort.Accounts.ConnectedAccount}
      result = Jason.encode!(not_found)

      assert result == "\"connected_account_not_found\""
    end
  end

  describe "module_name/1 private function" do
    test "handles simple module names" do
      # Test the private function through the public interface
      not_found = %NotFound{entity: SmartSort.Accounts.User}
      result = to_string(not_found)

      assert result == "user_not_found"
    end

    test "handles complex module names" do
      not_found = %NotFound{entity: SmartSort.Accounts.ConnectedAccount}
      result = to_string(not_found)

      assert result == "connected_account_not_found"
    end
  end
end
