defmodule SmartSortWeb.UserAuth do
  use SmartSortWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias SmartSort.Accounts.User

  def log_in_user(conn, user) do
    conn
    |> put_session(:user_id, user.id)
    |> put_session(:live_socket_id, "user_sessions:#{user.id}")
    |> redirect(to: signed_in_path(conn))
  end

  def logout_user(conn) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  def fetch_current_user(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn

      user_id ->
        case User.get(user_id) do
          {:ok, user} -> assign(conn, :current_user, user)
          _ -> conn
        end
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  defp signed_in_path(_conn), do: ~p"/dashboard"
end
