defmodule SmartSortWeb.EmailsLive do
  use SmartSortWeb, :live_view

  alias SmartSort.Accounts.{Category, User}
  alias SmartSort.Accounts.Email
  alias SmartSortWeb.EmailComponents

  @search_debounce_ms 400

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-4">
              <.link
                navigate={~p"/dashboard"}
                class="text-gray-500 hover:text-gray-700 transition-colors"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </.link>

              <div class="flex items-center">
                <div class="w-8 h-8 bg-gradient-to-r from-blue-500 to-indigo-500 rounded-lg flex items-center justify-center">
                  <span class="text-white font-medium text-sm">
                    {String.first(@category.name) |> String.upcase()}
                  </span>
                </div>
                <div class="ml-3">
                  <h1 class="text-xl font-semibold text-gray-900">{@category.name}</h1>
                  <p class="text-sm text-gray-500">{@category.description}</p>
                </div>
              </div>
            </div>

            <div class="flex items-center space-x-4">
              <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                {@total_emails} emails
              </span>
              <img src={@user.avatar} alt="Avatar" class="w-8 h-8 rounded-full" />
              <span class="text-sm text-gray-700">{@user.name}</span>
            </div>
          </div>
        </div>
      </header>

      <!-- Search and Filters -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
          <div class="flex items-center justify-between">
            <div class="flex-1 mr-4">
              <.form for={@search_form} phx-change="search" phx-submit="search" class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                </div>
                <input
                  type="text"
                  name="q"
                  value={@search_query}
                  placeholder="Search emails by subject, sender, or content..."
                  class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                  phx-debounce={@search_debounce_ms}
                />
              </.form>
            </div>

            <div class="flex items-center space-x-3">
              <.form for={@select_form} phx-change="update_select" class="inline flex space-x-3">
                <select
                  name="read_status"
                  class="block text-sm border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="all" selected={@filter_read_status == "all"}>All emails</option>
                  <option value="unread" selected={@filter_read_status == "unread"}>Unread only</option>
                  <option value="read" selected={@filter_read_status == "read"}>Read only</option>
                </select>

                <select
                  name="sort"
                  class="block text-sm border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="newest" selected={@sort_by == "newest"}>Newest first</option>
                  <option value="oldest" selected={@sort_by == "oldest"}>Oldest first</option>
                  <option value="sender" selected={@sort_by == "sender"}>By sender</option>
                  <option value="subject" selected={@sort_by == "subject"}>By subject</option>
                </select>
              </.form>
            </div>
          </div>
        </div>

        <!-- Email List -->
        <%= if @loading do %>
          <EmailComponents.loading_state />
        <% else %>
          <%= if @total_emails == 0 do %>
            <EmailComponents.empty_state category={@category} />
          <% else %>
            <EmailComponents.email_list
              emails={@streams.emails}
              selected_email={@selected_email}
            />

            <!-- Pagination -->
            <%= if @total_pages > 1 do %>
              <EmailComponents.pagination
                current_page={@current_page}
                total_pages={@total_pages}
                total_emails={@total_emails}
              />
            <% end %>
          <% end %>
        <% end %>
      </div>

      <!-- Email Detail Modal (if email is selected) -->
      <%= if @selected_email do %>
        <EmailComponents.email_detail_modal
          email={@selected_email}
          category={@category}
        />
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"category_id" => category_id}, session, socket) do
    user = get_user_from_session(session)

    case Category.get(category_id) do
      {:ok, category} ->
        if category.user_id == user.id do
          socket =
            socket
            |> assign(:user, user)
            |> assign(:category, category)
            |> assign(:loading, true)
            |> assign(:search_query, "")
            |> assign(:search_form, to_form(%{}))
            |> assign(:select_form, to_form(%{}))
            |> assign(:search_debounce_ms, @search_debounce_ms)
            |> assign(:filter_read_status, "all")
            |> assign(:sort_by, "newest")
            |> assign(:current_page, 1)
            |> assign(:page_size, 10)
            |> assign(:total_emails, 0)
            |> assign(:total_pages, 1)
            |> assign(:selected_email, nil)
            |> stream(:emails, [])

          if connected?(socket) do
            send(self(), :load_emails)
          end

          {:ok, socket}
        else
          {:ok, redirect(socket, to: ~p"/dashboard")}
        end

      {:error, _} ->
        {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_info(:load_emails, socket) do
    load_emails(socket)
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    # Only reload if query actually changed
    if query != socket.assigns.search_query do
      socket =
        socket
        |> assign(:search_query, query)
        |> assign(:current_page, 1)
        |> assign(:loading, true)

      # Debounced search will be handled by phx-debounce on the input
      send(self(), :load_emails)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_select", params, socket) do
    cond do
      # Handle read status filter change
      Map.has_key?(params, "read_status") and
          params["read_status"] != socket.assigns.filter_read_status ->
        socket =
          socket
          |> assign(:filter_read_status, params["read_status"])
          |> assign(:current_page, 1)
          |> assign(:loading, true)

        send(self(), :load_emails)
        {:noreply, socket}

      # Handle sort change
      Map.has_key?(params, "sort") and params["sort"] != socket.assigns.sort_by ->
        socket =
          socket
          |> assign(:sort_by, params["sort"])
          |> assign(:current_page, 1)
          |> assign(:loading, true)

        send(self(), :load_emails)
        {:noreply, socket}

      # No changes detected
      true ->
        {:noreply, socket}
    end
  end

  def handle_event("select_email", %{"id" => email_id}, socket) do
    with {:ok, email} <- Email.get(email_id),
         {:ok, updated_email} <- maybe_mark_as_read(email) do
      updated_socket = stream_insert(socket, :emails, updated_email)
      {:noreply, assign(updated_socket, :selected_email, updated_email)}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email not found")}
    end
  end

  defp maybe_mark_as_read(%{is_read: true} = email), do: {:ok, email}
  defp maybe_mark_as_read(email), do: Email.update(email, %{is_read: true})

  def handle_event("close_email_detail", _params, socket) do
    {:noreply, assign(socket, :selected_email, nil)}
  end

  def handle_event("page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    if page != socket.assigns.current_page do
      socket =
        socket
        |> assign(:current_page, page)
        |> assign(:loading, true)

      send(self(), :load_emails)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mark_as_read", %{"id" => email_id}, socket) do
    case Email.get(email_id) do
      {:ok, email} ->
        case Email.update(email, %{is_read: true}) do
          {:ok, updated_email} ->
            # Update the email in the stream and update total count
            socket =
              socket
              |> stream_insert(:emails, updated_email)
              |> maybe_update_selected_email(updated_email)

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to mark email as read")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email not found")}
    end
  end

  def handle_event("mark_as_unread", %{"id" => email_id}, socket) do
    case Email.get(email_id) do
      {:ok, email} ->
        case Email.update(email, %{is_read: false}) do
          {:ok, updated_email} ->
            # Update the email in the stream and update total count
            socket =
              socket
              |> stream_insert(:emails, updated_email)
              |> maybe_update_selected_email(updated_email)

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to mark email as unread")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email not found")}
    end
  end

  defp load_emails(socket) do
    opts = [
      search_query: socket.assigns.search_query,
      read_status: socket.assigns.filter_read_status,
      sort_by: socket.assigns.sort_by,
      page: socket.assigns.current_page,
      page_size: socket.assigns.page_size
    ]

    case Email.get_emails_for_category_paginated(socket.assigns.category.id, opts) do
      {:ok, %{emails: emails, total_count: total_count}} ->
        total_pages = ceil(total_count / socket.assigns.page_size)

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:total_emails, total_count)
          |> assign(:total_pages, total_pages)
          |> stream(:emails, emails, reset: true)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to load emails: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  # Helper to update the selected email if it matches the updated email
  defp maybe_update_selected_email(socket, updated_email) do
    if socket.assigns.selected_email && socket.assigns.selected_email.id == updated_email.id do
      assign(socket, :selected_email, updated_email)
    else
      socket
    end
  end

  defp get_user_from_session(session) do
    case session["user_id"] do
      nil -> nil
      user_id -> User.get!(user_id, [:categories])
    end
  end
end
