defmodule SmartSort.Accounts.CategoryTest do
  use SmartSort.DataCase

  import SmartSort.Fixtures

  alias SmartSort.Accounts.Category

  describe "changeset/2" do
    test "creates valid category with all required fields" do
      user = user_fixture()

      attrs = %{
        name: "Test Category",
        description: "A test category for emails",
        user_id: user.id
      }

      changeset = Category.changeset(%Category{}, attrs)
      assert changeset.valid?
    end

    test "requires name" do
      user = user_fixture()

      attrs = %{
        description: "A test category for emails",
        user_id: user.id
      }

      changeset = Category.changeset(%Category{}, attrs)
      refute changeset.valid?
      assert {:name, {"can't be blank", _}} = List.keyfind(changeset.errors, :name, 0)
    end

    test "requires user_id" do
      attrs = %{
        name: "Test Category",
        description: "A test category for emails"
      }

      changeset = Category.changeset(%Category{}, attrs)
      refute changeset.valid?
      assert {:user_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :user_id, 0)
    end
  end

  describe "create/1" do
    test "creates category with valid attributes" do
      user = user_fixture()

      attrs = %{
        name: "Test Category",
        description: "A test category for emails",
        user_id: user.id
      }

      assert {:ok, category} = Category.create(attrs)
      assert category.name == "Test Category"
      assert category.description == "A test category for emails"
      assert category.user_id == user.id
    end

    test "returns error changeset with invalid attributes" do
      attrs = %{name: ""}

      assert {:error, changeset} = Category.create(attrs)
      refute changeset.valid?
    end
  end

  describe "get/1" do
    test "returns category when it exists" do
      category = category_fixture()
      assert {:ok, found_category} = Category.get(category.id)
      assert found_category.id == category.id
      assert found_category.name == category.name
    end

    test "returns error when category does not exist" do
      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.Category}} =
               Category.get(999_999)
    end
  end

  describe "get_by/1" do
    test "returns category when it exists" do
      category = category_fixture()
      assert {:ok, found_category} = Category.get_by(%{name: category.name})
      assert found_category.id == category.id
    end

    test "returns error when category does not exist" do
      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.Category}} =
               Category.get_by(%{name: "Nonexistent Category"})
    end
  end

  describe "update/2" do
    test "updates category with valid attributes" do
      category = category_fixture()
      attrs = %{name: "Updated Category Name"}

      assert {:ok, updated_category} = Category.update(category, attrs)
      assert updated_category.name == "Updated Category Name"
    end

    test "returns error changeset with invalid attributes" do
      category = category_fixture()
      attrs = %{name: ""}

      assert {:error, changeset} = Category.update(category, attrs)
      refute changeset.valid?
    end
  end

  describe "delete/1" do
    test "deletes category" do
      category = category_fixture()
      assert {:ok, deleted_category} = Category.delete(category)

      assert {:error, %SmartSort.Macros.NotFound{entity: SmartSort.Accounts.Category}} =
               Category.get(category.id)
    end
  end
end
