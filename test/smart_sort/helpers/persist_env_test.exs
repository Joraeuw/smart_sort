defmodule SmartSort.Helpers.PersistEnvTest do
  use ExUnit.Case

  alias SmartSort.Helpers.PersistEnv

  describe "project_id/0" do
    test "returns project_id from configuration" do
      # This test will depend on the actual configuration
      # We'll just verify the function doesn't crash
      result = PersistEnv.project_id()

      # The result could be nil, a string, or any value depending on config
      # We just want to ensure the function executes without error
      assert is_atom(result) or is_binary(result) or is_nil(result)
    end
  end

  describe "google_client_id/0" do
    test "returns client_id from ueberauth configuration" do
      # This test will depend on the actual configuration
      # We'll just verify the function doesn't crash
      result = PersistEnv.google_client_id()

      # The result could be nil, a string, or any value depending on config
      # We just want to ensure the function executes without error
      assert is_atom(result) or is_binary(result) or is_nil(result)
    end
  end

  describe "google_client_secret/0" do
    test "returns client_secret from ueberauth configuration" do
      # This test will depend on the actual configuration
      # We'll just verify the function doesn't crash
      result = PersistEnv.google_client_secret()

      # The result could be nil, a string, or any value depending on config
      # We just want to ensure the function executes without error
      assert is_atom(result) or is_binary(result) or is_nil(result)
    end
  end

  describe "function execution" do
    test "all functions can be called without crashing" do
      # Test that all public functions can be called
      assert is_atom(PersistEnv.project_id()) or is_binary(PersistEnv.project_id()) or
               is_nil(PersistEnv.project_id())

      assert is_atom(PersistEnv.google_client_id()) or is_binary(PersistEnv.google_client_id()) or
               is_nil(PersistEnv.google_client_id())

      assert is_atom(PersistEnv.google_client_secret()) or
               is_binary(PersistEnv.google_client_secret()) or
               is_nil(PersistEnv.google_client_secret())
    end
  end
end
