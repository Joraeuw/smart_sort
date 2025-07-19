defmodule SmartSortWeb.PageController do
  use SmartSortWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
