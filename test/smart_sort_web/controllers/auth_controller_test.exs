defmodule SmartSortWeb.AuthControllerTest do
  use SmartSortWeb.ConnCase

  import Mox
  import SmartSort.Fixtures

  alias SmartSort.Accounts

  setup :verify_on_exit!

  describe "index/2" do
    test "redirects to Google OAuth", %{conn: conn} do
      conn = get(conn, ~p"/auth/google")

      assert redirected_to(conn) =~ "accounts.google.com"
      assert redirected_to(conn) =~ "oauth"
    end
  end

  describe "callback/2 - failure cases" do
    test "handles OAuth failure", %{conn: conn} do
      failure = mock_ueberauth_failure()

      conn =
        conn
        |> fetch_session()
        |> assign(:ueberauth_failure, failure)
        |> get(~p"/auth/google/callback")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Google"
    end

    test "handles missing OAuth data", %{conn: conn} do
      conn =
        conn
        |> fetch_session()
        |> get(~p"/auth/google/callback")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed to authenticate with Google"
    end
  end

  describe "add_account/2" do
    test "redirects to Google OAuth with session flag", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> fetch_session()
        |> put_session(:user_id, user.id)
        |> get(~p"/auth/add-account")

      assert redirected_to(conn) == "/auth/google"
      assert get_session(conn, :add_account_for_user_id) == user.id
    end
  end
end
