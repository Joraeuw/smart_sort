defmodule SmartSortWeb.AuthController do
  use SmartSortWeb, :controller
  plug Ueberauth

  require Logger
  alias SmartSort.Accounts.User
  alias SmartSort.Accounts
  alias SmartSort.GmailAccountHandler
  alias SmartSort.Jobs.RefreshGoogleTokens
  alias SmartSortWeb.UserAuth

  def request(conn, _params) do
    # Ueberauth handles the request automatically
    conn
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case get_session(conn, :add_account_for_user_id) do
      nil ->
        handle_normal_oauth_flow(conn, auth)

      existing_user_id ->
        handle_add_account_flow(conn, auth, existing_user_id)
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.warning("OAuth authentication failed", failure: inspect(failure))

    conn
    |> put_flash(:error, "Failed to authenticate with Google")
    |> redirect(to: ~p"/")
  end

  def add_account(conn, _params) do
    conn
    |> put_session(:add_account_for_user_id, conn.assigns.current_user.id)
    |> redirect(external: "/auth/google")
  end

  def logout_user(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully")
    |> UserAuth.logout_user()
  end

  defp handle_normal_oauth_flow(conn, auth) do
    case Accounts.find_or_create_user_from_oauth(auth) do
      {:ok, user, connected_account} ->
        start_gmail_watching_for_account(connected_account)

        conn
        |> put_flash(:info, "Successfully signed in!")
        |> UserAuth.log_in_user(user)

      {:error, reason} ->
        Logger.error("Failed to authenticate user",
          email: auth.info.email,
          reason: inspect(reason)
        )

        conn
        |> put_flash(:error, "Failed to sign in")
        |> redirect(to: ~p"/")
    end
  end

  defp handle_add_account_flow(conn, auth, existing_user_id) do
    with {:ok, existing_user} <- User.get(existing_user_id),
         {:ok, connected_account} <-
           Accounts.add_email_account_to_existing_user(existing_user, auth) do
      start_gmail_watching_for_account(connected_account)

      conn
      |> clear_session_flags()
      |> put_flash(:info, "Gmail account #{auth.info.email} connected successfully!")
      |> redirect(to: ~p"/dashboard")
    else
      {:error, :already_connected} ->
        conn
        |> clear_session_flags()
        |> put_flash(:error, "This Gmail account is already connected to your account")
        |> redirect(to: ~p"/dashboard")

      {:error, :connected_to_other_user} ->
        conn
        |> clear_session_flags()
        |> put_flash(:error, "This Gmail account is already connected to another user")
        |> redirect(to: ~p"/dashboard")

      {:error, reason} ->
        Logger.error("Failed to connect Gmail account",
          user_id: existing_user_id,
          email: auth.info.email,
          reason: inspect(reason)
        )

        conn
        |> clear_session_flags()
        |> put_flash(:error, "Failed to connect Gmail account")
        |> redirect(to: ~p"/dashboard")
    end
  end

  defp clear_session_flags(conn) do
    conn
    |> delete_session(:add_account_for_user_id)
  end

  defp start_gmail_watching_for_account(connected_account) do
    case GmailAccountHandler.start_watching_inbox(connected_account) do
      {:ok, _response} ->
        RefreshGoogleTokens.schedule(connected_account)

      {:error, reason} ->
        Logger.error("Failed to start Gmail watching with reason: #{inspect(reason)}",
          email: connected_account.email,
          reason: inspect(reason)
        )
    end
  end
end
