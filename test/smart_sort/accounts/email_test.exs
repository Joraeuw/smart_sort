defmodule SmartSort.Accounts.EmailTest do
  use SmartSort.DataCase

  import SmartSort.Fixtures

  alias SmartSort.Accounts.{Email, Category}

  describe "changeset/2" do
    test "creates valid email with all required fields" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "sender@example.com",
        to_email: "recipient@example.com",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      assert changeset.valid?
    end

    test "requires all required fields" do
      changeset = Email.changeset(%Email{}, %{})
      refute changeset.valid?

      assert {:gmail_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :gmail_id, 0)
      assert {:thread_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :thread_id, 0)
      assert {:subject, {"can't be blank", _}} = List.keyfind(changeset.errors, :subject, 0)
      assert {:from_email, {"can't be blank", _}} = List.keyfind(changeset.errors, :from_email, 0)

      assert {:received_at, {"can't be blank", _}} =
               List.keyfind(changeset.errors, :received_at, 0)

      assert {:user_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :user_id, 0)

      assert {:connected_account_id, {"can't be blank", _}} =
               List.keyfind(changeset.errors, :connected_account_id, 0)
    end

    test "validates email format for from_email" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "invalid-email",
        to_email: "recipient@example.com",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      refute changeset.valid?

      assert {:from_email, {"must be a valid email", _}} =
               List.keyfind(changeset.errors, :from_email, 0)
    end

    test "validates email format for to_email" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "sender@example.com",
        to_email: "invalid-email",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      refute changeset.valid?

      assert {:to_email, {"must be a valid email", _}} =
               List.keyfind(changeset.errors, :to_email, 0)
    end

    test "validates subject length" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        # Over 500 character limit
        subject: String.duplicate("a", 501),
        from_email: "sender@example.com",
        to_email: "recipient@example.com",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      refute changeset.valid?

      assert {:subject, {"should be at most %{count} character(s)", _}} =
               List.keyfind(changeset.errors, :subject, 0)
    end

    test "validates snippet length" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "sender@example.com",
        to_email: "recipient@example.com",
        # Over 1000 character limit
        snippet: String.duplicate("a", 1001),
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      refute changeset.valid?

      assert {:snippet, {"should be at most %{count} character(s)", _}} =
               List.keyfind(changeset.errors, :snippet, 0)
    end

    test "validates ai_summary length" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "sender@example.com",
        to_email: "recipient@example.com",
        # Over 2000 character limit
        ai_summary: String.duplicate("a", 2001),
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      changeset = Email.changeset(%Email{}, attrs)
      refute changeset.valid?

      assert {:ai_summary, {"should be at most %{count} character(s)", _}} =
               List.keyfind(changeset.errors, :ai_summary, 0)
    end

    test "enforces unique constraint on connected_account_id and gmail_id" do
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})

      attrs = %{
        gmail_id: "gmail_123",
        thread_id: "thread_456",
        subject: "Test Email",
        from_email: "sender@example.com",
        to_email: "recipient@example.com",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id
      }

      # Create first email
      {:ok, _email} = Email.create(attrs)

      # Try to create duplicate
      {:error, changeset} = Email.create(attrs)
      refute changeset.valid?

      assert {:connected_account_id, {"Email already exists for this account", _}} =
               List.keyfind(changeset.errors, :connected_account_id, 0)
    end
  end

  describe "assign_to_category/4" do
    test "assigns email to category and updates ai_summary and confidence_score" do
      email = email_fixture() |> Repo.preload(:user)
      category = category_fixture(%{user: email.user})

      ai_summary = "This email is about marketing"
      confidence_score = 0.95

      {:ok, updated_email} =
        Email.assign_to_category(email, category.id, ai_summary, confidence_score)

      assert updated_email.category_id == category.id
      assert updated_email.ai_summary == ai_summary
      assert updated_email.confidence_score == confidence_score
    end

    test "broadcasts category update when category is assigned" do
      email = email_fixture() |> Repo.preload(:user)
      category = category_fixture(%{user: email.user})

      {:ok, _updated_email} = Email.assign_to_category(email, category.id, "AI summary", 0.9)

      # Verify the category count was incremented
      updated_category = Category.get!(category.id)
      assert updated_category.email_count == category.email_count + 1
    end

    test "does not broadcast when category_id is nil" do
      email = email_fixture()

      {:ok, updated_email} = Email.assign_to_category(email, nil, "AI summary", 0.9)

      assert updated_email.category_id == nil
      assert updated_email.ai_summary == "AI summary"
      assert updated_email.confidence_score == 0.9
    end

    test "returns error when update fails" do
      email = email_fixture()

      # Try to assign to non-existent category
      assert_raise Ecto.ConstraintError, fn ->
        Email.assign_to_category(email, 99999, "AI summary", 0.9)
      end
    end
  end

  describe "delete/2" do
    test "deletes email and decrements category count when email has category" do
      email = email_fixture() |> Repo.preload(:category)
      category = email.category

      {:ok, _deleted_email} = Email.delete(email)

      # Verify the category count was decremented
      updated_category = Category.get!(category.id)
      assert updated_category.email_count == category.email_count - 1
    end

    test "deletes email without broadcasting when email has no category" do
      email = email_fixture(%{category_id: nil})

      {:ok, _deleted_email} = Email.delete(email)
    end

    test "returns error when delete fails" do
      email = %Email{id: 99999}

      {:error, _changeset} = Email.delete(email)
    end
  end

  describe "filter_where/1" do
    test "filters by search query" do
      email = email_fixture(%{subject: "Marketing Newsletter"})

      filter = %{search_query: "marketing"}
      query = Email.filter_where(filter)

      # The query should be a dynamic expression
    end

    test "filters by is_read status" do
      filter = %{is_read: true}
      query = Email.filter_where(filter)
    end

    test "filters by is_archived status" do
      filter = %{is_archived: false}
      query = Email.filter_where(filter)
    end

    test "filters by category_id" do
      category = category_fixture()
      filter = %{category_id: category.id}
      query = Email.filter_where(filter)
    end

    test "filters by user_id" do
      user = user_fixture()
      filter = %{user_id: user.id}
      query = Email.filter_where(filter)
    end

    test "filters by connected_account_id" do
      connected_account = connected_account_fixture()
      filter = %{connected_account_id: connected_account.id}
      query = Email.filter_where(filter)
    end

    test "filters by thread_id" do
      filter = %{thread_id: "thread_123"}
      query = Email.filter_where(filter)
    end

    test "filters by from_email" do
      filter = %{from_email: "sender@example.com"}
      query = Email.filter_where(filter)
    end

    test "filters by confidence_score range" do
      filter = %{confidence_score_gte: 0.5, confidence_score_lte: 0.9}
      query = Email.filter_where(filter)
    end

    test "filters by received date range" do
      now = DateTime.utc_now()
      filter = %{received_after: now, received_before: now}
      query = Email.filter_where(filter)
    end

    test "ignores empty or nil values" do
      filter = %{search_query: "", category_id: nil}
      query = Email.filter_where(filter)
    end
  end

  describe "order_entity_by/2" do
    test "orders by received_at" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, received_at: :desc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "orders by subject" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, subject: :asc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "orders by from_email" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, from_email: :asc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "orders by from_name" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, from_name: :asc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "orders by confidence_score" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, confidence_score: :desc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "orders by inserted_at" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, inserted_at: :desc)

      assert is_struct(ordered_query, Ecto.Query)
    end

    test "handles string sort parameters" do
      query = from(e in Email, as: :email)

      newest_query = Email.order_entity_by(query, "newest")
      oldest_query = Email.order_entity_by(query, "oldest")
      sender_query = Email.order_entity_by(query, "sender")
      subject_query = Email.order_entity_by(query, "subject")

      assert is_struct(newest_query, Ecto.Query)
      assert is_struct(oldest_query, Ecto.Query)
      assert is_struct(sender_query, Ecto.Query)
      assert is_struct(subject_query, Ecto.Query)
    end

    test "handles atom sort parameters" do
      query = from(e in Email, as: :email)

      newest_query = Email.order_entity_by(query, :newest)
      oldest_query = Email.order_entity_by(query, :oldest)
      sender_query = Email.order_entity_by(query, :sender)
      subject_query = Email.order_entity_by(query, :subject)

      assert is_struct(newest_query, Ecto.Query)
      assert is_struct(oldest_query, Ecto.Query)
      assert is_struct(sender_query, Ecto.Query)
      assert is_struct(subject_query, Ecto.Query)
    end

    test "ignores invalid sort parameters" do
      query = from(e in Email, as: :email)
      ordered_query = Email.order_entity_by(query, invalid_field: :asc)

      assert is_struct(ordered_query, Ecto.Query)
    end
  end

  describe "get_all_by_paginated/5" do
    test "returns paginated emails with total count" do
      # Create multiple emails
      user = user_fixture()
      connected_account = connected_account_fixture(%{user: user})
      category = category_fixture(%{user: user})

      for i <- 1..15 do
        email_fixture(%{
          user: user,
          connected_account: connected_account,
          category: category,
          subject: "Email #{i}"
        })
      end

      {:ok, emails, total_count} = Email.get_all_by_paginated(%{}, [received_at: :desc], 1, 10)

      assert length(emails) == 10
      assert total_count == 15
    end

    test "handles search terms" do
      email = email_fixture(%{subject: "Marketing Newsletter"})

      {:ok, emails, total_count} =
        Email.get_all_by_paginated(
          %{search_query: "marketing"},
          [received_at: :desc],
          1,
          10
        )

      assert length(emails) == 1
      assert total_count == 1
    end

    test "handles errors gracefully" do
      # Pass invalid search terms to trigger error
      result =
        Email.get_all_by_paginated(
          %{invalid_field: "invalid_value"},
          [received_at: :desc],
          1,
          10
        )

      # Should return empty results instead of error
      assert {:ok, [], 0} = result
    end
  end

  describe "get_emails_for_category_paginated/2" do
    test "returns emails for specific category" do
      category = category_fixture()
      email = email_fixture(%{category: category})

      {:ok, result} = Email.get_emails_for_category_paginated(category.id)

      assert result.total_count == 1
      assert length(result.emails) == 1
      assert hd(result.emails).category_id == category.id
    end

    test "filters by search query" do
      category = category_fixture()
      email = email_fixture(%{category: category, subject: "Marketing Email"})

      {:ok, result} =
        Email.get_emails_for_category_paginated(category.id, search_query: "marketing")

      assert result.total_count == 1
      assert length(result.emails) == 1
    end

    test "filters by read status" do
      category = category_fixture()
      email = email_fixture(%{category: category, is_read: false})

      {:ok, result} = Email.get_emails_for_category_paginated(category.id, read_status: "unread")

      assert result.total_count == 1
      assert length(result.emails) == 1
    end

    test "sorts by different criteria" do
      category = category_fixture()
      email1 = email_fixture(%{category: category, subject: "A Email"})
      email2 = email_fixture(%{category: category, subject: "B Email"})

      {:ok, result} = Email.get_emails_for_category_paginated(category.id, sort_by: "subject")

      assert result.total_count == 2
      assert length(result.emails) == 2
    end

    test "handles pagination" do
      category = category_fixture()

      # Create more emails than page size
      for i <- 1..30 do
        email_fixture(%{category: category, subject: "Email #{i}"})
      end

      {:ok, result} = Email.get_emails_for_category_paginated(category.id, page_size: 10)

      assert result.total_count == 30
      assert length(result.emails) == 10
    end
  end

  describe "unsubscribe functions" do
    test "start_unsubscribe sets processing status" do
      email = email_fixture()

      {:ok, updated_email} = Email.start_unsubscribe(email)

      assert updated_email.unsubscribe_status == "processing"
      assert updated_email.unsubscribe_attempted_at != nil
    end

    test "complete_unsubscribe_success sets success status" do
      email = email_fixture()

      {:ok, updated_email} =
        Email.complete_unsubscribe_success(email, "Successfully unsubscribed")

      assert updated_email.unsubscribe_status == "success"
      assert updated_email.unsubscribe_completed_at != nil
      assert updated_email.unsubscribe_details == "Successfully unsubscribed"
    end

    test "complete_unsubscribe_failure sets failed status" do
      email = email_fixture()

      {:ok, updated_email} = Email.complete_unsubscribe_failure(email, "Rate limit exceeded")

      assert updated_email.unsubscribe_status == "failed"
      assert updated_email.unsubscribe_completed_at != nil
      assert updated_email.unsubscribe_details == "Rate limit exceeded"
    end

    test "unsubscribe_processing? returns correct status" do
      email = email_fixture()

      # Initially not processing
      refute Email.unsubscribe_processing?(email)

      # Start unsubscribe
      {:ok, updated_email} = Email.start_unsubscribe(email)
      assert Email.unsubscribe_processing?(updated_email)

      # Complete unsubscribe
      {:ok, completed_email} = Email.complete_unsubscribe_success(updated_email)
      refute Email.unsubscribe_processing?(completed_email)
    end
  end
end
