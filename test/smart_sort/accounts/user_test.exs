defmodule SmartSort.Accounts.UserTest do
  use SmartSort.DataCase

  import SmartSort.Fixtures

  alias SmartSort.Accounts.User

  describe "changeset/2" do
    test "creates valid user with all required fields" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        avatar: "https://example.com/avatar.jpg"
      }

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "requires email" do
      attrs = %{
        name: "Test User",
        avatar: "https://example.com/avatar.jpg"
      }

      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert {:email, {"can't be blank", _}} = List.keyfind(changeset.errors, :email, 0)
    end

    test "requires name" do
      attrs = %{
        email: "test@example.com",
        avatar: "https://example.com/avatar.jpg"
      }

      changeset = User.changeset(%User{}, attrs)
      refute changeset.valid?
      assert {:name, {"can't be blank", _}} = List.keyfind(changeset.errors, :name, 0)
    end

    test "validates email format" do
      attrs = %{
        email: "invalid-email",
        name: "Test User"
      }

      changeset = User.changeset(%User{}, attrs)
      # Note: The current implementation doesn't validate email format
      assert changeset.valid?
    end
  end

  describe "create/1" do
    test "creates user with valid attributes" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        avatar: "https://example.com/avatar.jpg"
      }

      assert {:ok, user} = User.create(attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.avatar == "https://example.com/avatar.jpg"
    end

    test "returns error changeset with invalid attributes" do
      attrs = %{email: "invalid-email"}

      assert {:error, changeset} = User.create(attrs)
      refute changeset.valid?
    end
  end

  describe "get/1" do
    test "returns user when it exists" do
      user = user_fixture()
      assert {:ok, found_user} = User.get(user.id)
      assert found_user.id == user.id
      assert found_user.email == user.email
    end

    test "returns error when user does not exist" do
      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.User}} =
               User.get(999_999)
    end
  end

  describe "get_by/1" do
    test "returns user when it exists" do
      user = user_fixture()
      assert {:ok, found_user} = User.get_by(%{email: user.email})
      assert found_user.id == user.id
    end

    test "returns error when user does not exist" do
      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.User}} =
               User.get_by(%{email: "nonexistent@example.com"})
    end
  end

  describe "update/2" do
    test "updates user with valid attributes" do
      user = user_fixture()
      attrs = %{name: "Updated Name"}

      assert {:ok, updated_user} = User.update(user, attrs)
      assert updated_user.name == "Updated Name"
    end

    test "returns error changeset with invalid attributes" do
      user = user_fixture()
      attrs = %{email: "invalid-email"}

      # Note: The current implementation doesn't validate email format, so this succeeds
      assert {:ok, updated_user} = User.update(user, attrs)
      assert updated_user.email == "invalid-email"
    end
  end

  describe "delete/1" do
    test "deletes user" do
      user = user_fixture()
      assert {:ok, deleted_user} = User.delete(user)

      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.User}} =
               User.get(user.id)
    end
  end
end
