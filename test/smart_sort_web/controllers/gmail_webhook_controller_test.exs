defmodule SmartSortWeb.GmailWebhookControllerTest do
  use SmartSortWeb.ConnCase

  import SmartSort.Fixtures

  describe "receive/2 - basic functionality" do
    test "returns 200 for any request", %{conn: conn} do
      conn = post(conn, ~p"/webhooks/gmail", %{})

      assert response(conn, 200) == "{\"status\":\"ok\"}"
    end

    test "handles empty request body", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/webhooks/gmail", "")

      assert response(conn, 200) == "{\"status\":\"ok\"}"
    end
  end
end
