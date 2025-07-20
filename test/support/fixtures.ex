defmodule SmartSort.Fixtures do
  @moduledoc """
  This module provides test fixtures for the SmartSort application.
  """

  alias SmartSort.Accounts.{User, ConnectedAccount}
  alias SmartSort.Repo

  def user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        email: "test#{System.unique_integer()}@example.com",
        name: "Test User",
        avatar: "https://example.com/avatar.jpg"
      })

    {:ok, user} = User.create(attrs)
    user
  end

  def connected_account_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    attrs =
      Enum.into(attrs, %{
        email: "test#{System.unique_integer()}@gmail.com",
        provider: "google",
        provider_id: "#{System.unique_integer()}",
        access_token: "access_token_123",
        refresh_token: "refresh_token_123",
        is_primary: true,
        user_id: user.id
      })

    {:ok, connected_account} = ConnectedAccount.create(attrs)
    connected_account
  end

  def mock_ueberauth_auth(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        uid: "123456789",
        provider: :google,
        info: %Ueberauth.Auth.Info{
          email: "test@gmail.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "access_token_123",
          refresh_token: "refresh_token_123",
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_unix()
        }
      })

    struct(Ueberauth.Auth, attrs)
  end

  def mock_ueberauth_failure(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        provider: :google,
        strategy: Ueberauth.Strategy.Google,
        error: "access_denied",
        error_message: "User denied access"
      })

    struct(Ueberauth.Failure, attrs)
  end

  def category_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    attrs =
      Enum.into(attrs, %{
        name: "Test Category #{System.unique_integer()}",
        description: "A test category for emails",
        user_id: user.id
      })

    {:ok, category} = SmartSort.Accounts.Category.create(attrs)
    category
  end

  def email_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    connected_account = attrs[:connected_account] || connected_account_fixture(%{user: user})
    category = attrs[:category] || category_fixture(%{user: user})

    attrs =
      Enum.into(attrs, %{
        gmail_id: "gmail_#{System.unique_integer()}",
        thread_id: "thread_#{System.unique_integer()}",
        subject: "Test Email Subject",
        from_email: "sender@example.com",
        from_name: "Test Sender",
        to_email: "recipient@example.com",
        snippet: "This is a test email snippet",
        body: "This is the full body of the test email",
        body_type: "text",
        received_at: DateTime.utc_now(),
        user_id: user.id,
        connected_account_id: connected_account.id,
        category_id: category.id,
        is_read: false,
        is_archived: false,
        confidence_score: 0.85,
        ai_summary: "AI analysis of this email"
      })

    {:ok, email} = SmartSort.Accounts.Email.create(attrs)
    email
  end
end
