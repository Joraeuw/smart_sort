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
      <div class="max-w-8xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
          <div class="flex justify-between">
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

            <div class="flex items-center space-x-3 text-black">
              <.form for={@select_form} phx-change="update_select" class="flex items-center space-x-3">
              <div class="flex items-center space-x-3">
                <select
                  name="read_status"
                  class="block text-sm border-gray-300 rounded-md"
                >
                  <option value="all" selected={@filter_read_status == "all"}>All emails</option>
                  <option value="unread" selected={@filter_read_status == "unread"}>Unread only</option>
                  <option value="read" selected={@filter_read_status == "read"}>Read only</option>
                </select>

                <select
                  name="sort"
                  class="block text-sm border-gray-300 rounded-md"
                >
                  <option value="newest" selected={@sort_by == "newest"}>Newest first</option>
                  <option value="oldest" selected={@sort_by == "oldest"}>Oldest first</option>
                  <option value="sender" selected={@sort_by == "sender"}>By sender</option>
                  <option value="subject" selected={@sort_by == "subject"}>By subject</option>
                </select>
                </div>
              </.form>
            </div>
          </div>
        </div>

                <!-- Bulk Actions Bar -->
        <%= if @selected_count > 0 do %>
          <div class="bg-gradient-to-r from-blue-50/80 to-indigo-50/80 border border-blue-200 rounded-xl p-5 mb-6 shadow-sm backdrop-blur-sm">
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-6">
                <div class="flex items-center space-x-3">
                  <div class="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
                    <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                    </svg>
                  </div>
                  <div>
                    <span class="text-base font-semibold text-blue-900">
                      {@selected_count} email{if @selected_count != 1, do: "s"} selected
                    </span>
                    <p class="text-xs text-blue-700 mt-0.5">Ready for bulk actions</p>
                  </div>
                </div>

                <div class="flex items-center space-x-3 border-l border-blue-200/50 pl-6">
                  <button
                    phx-click="select_all_emails"
                    class="inline-flex items-center px-4 py-2.5 text-sm font-semibold text-blue-700 bg-gradient-to-r from-blue-100 to-blue-200 hover:from-blue-200 hover:to-blue-300 rounded-xl transition-all duration-300 transform hover:scale-105 shadow-sm hover:shadow-md ring-1 ring-blue-300/50"
                  >
                    <div class="w-4 h-4 mr-2 flex items-center justify-center bg-blue-600 rounded-full">
                      <svg class="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7" />
                      </svg>
                    </div>
                    Select All
                  </button>
                  <button
                    phx-click="deselect_all_emails"
                    class="inline-flex items-center px-4 py-2.5 text-sm font-semibold text-gray-700 bg-gradient-to-r from-gray-100 to-gray-200 hover:from-gray-200 hover:to-gray-300 rounded-xl transition-all duration-300 transform hover:scale-105 shadow-sm hover:shadow-md ring-1 ring-gray-300/50"
                  >
                    <div class="w-4 h-4 mr-2 flex items-center justify-center bg-gray-600 rounded-full">
                      <svg class="w-2.5 h-2.5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </div>
                    Clear All
                  </button>
                </div>
              </div>

              <div class="flex items-center space-x-3">
                <%= if @bulk_action_processing do %>
                  <div class="flex items-center space-x-3 px-4 py-2 bg-white rounded-lg border border-blue-200">
                    <div class="flex space-x-1">
                      <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce"></div>
                      <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                      <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                    </div>
                    <span class="text-sm font-medium text-blue-900">Processing bulk action...</span>
                  </div>
                <% else %>
                  <button
                    phx-click="bulk_unsubscribe"
                    class="inline-flex items-center px-5 py-3 bg-gradient-to-r from-orange-500 to-red-500 hover:from-orange-600 hover:to-red-600 text-white font-semibold rounded-xl shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 ring-2 ring-orange-200 hover:ring-orange-300"
                  >
                    <div class="w-5 h-5 mr-2.5 flex items-center justify-center bg-white/20 rounded-full">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636" />
                      </svg>
                    </div>
                    Bulk Unsubscribe
                  </button>

                  <button
                    phx-click="bulk_delete"
                    class="inline-flex items-center px-5 py-3 bg-gradient-to-r from-red-500 to-pink-500 hover:from-red-600 hover:to-pink-600 text-white font-semibold rounded-xl shadow-lg hover:shadow-xl transform hover:scale-105 transition-all duration-300 ring-2 ring-red-200 hover:ring-red-300"
                  >
                    <div class="w-5 h-5 mr-2.5 flex items-center justify-center bg-white/20 rounded-full">
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </div>
                    Delete Selected
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

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
            |> assign(:unsubscribe_task, nil)
            |> assign(:bulk_action_processing, false)
            |> assign(:selected_count, 0)
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

  # Handle successful task completion
  def handle_info({ref, result}, socket) do
    if socket.assigns[:unsubscribe_task] && socket.assigns.unsubscribe_task.task.ref == ref do
      # Get the email that was being processed
      case Email.get(socket.assigns.unsubscribe_task.email_id) do
        {:ok, email} ->
          case result do
            {:ok, %{success: true, method: method, details: details} = result} ->
              verification_info = get_verification_details(result)

              flash_message =
                case verification_info do
                  "" -> "Successfully unsubscribed using #{method}: #{details}"
                  info -> "Successfully unsubscribed using #{method}: #{details}\n🔍 #{info}"
                end

              # Update email status to success
              case Email.complete_unsubscribe_success(email, details) do
                {:ok, updated_email} ->
                  socket =
                    socket
                    |> put_flash(:info, flash_message)
                    |> assign(:unsubscribe_task, nil)
                    |> stream_insert(:emails, updated_email)
                    |> maybe_update_selected_email(updated_email)

                  {:noreply, socket}

                {:error, _changeset} ->
                  socket =
                    socket
                    |> put_flash(:error, "Failed to update email status")
                    |> assign(:unsubscribe_task, nil)

                  {:noreply, socket}
              end

            {:ok, %{success: false, method: method, details: details} = result} ->
              # Enhanced failure message with debugging info
              debug_info = get_failure_debug_info(result)

              flash_message =
                case debug_info do
                  "" -> "Unsubscribe failed via #{method}: #{details}"
                  info -> "Unsubscribe failed via #{method}: #{details}\n🔍 #{info}"
                end

              # Update email status to failed
              case Email.complete_unsubscribe_failure(email, details) do
                {:ok, updated_email} ->
                  socket =
                    socket
                    |> put_flash(:error, flash_message)
                    |> assign(:unsubscribe_task, nil)
                    |> stream_insert(:emails, updated_email)
                    |> maybe_update_selected_email(updated_email)

                  {:noreply, socket}

                {:error, _changeset} ->
                  socket =
                    socket
                    |> put_flash(:error, "Failed to update email status")
                    |> assign(:unsubscribe_task, nil)

                  {:noreply, socket}
              end

            {:error, reason} ->
              # Update email status to failed
              case Email.complete_unsubscribe_failure(email, inspect(reason)) do
                {:ok, updated_email} ->
                  socket =
                    socket
                    |> put_flash(:error, "Unsubscribe failed: #{inspect(reason)}")
                    |> assign(:unsubscribe_task, nil)
                    |> stream_insert(:emails, updated_email)
                    |> maybe_update_selected_email(updated_email)

                  {:noreply, socket}

                {:error, _changeset} ->
                  socket =
                    socket
                    |> put_flash(:error, "Failed to update email status")
                    |> assign(:unsubscribe_task, nil)

                  {:noreply, socket}
              end
          end

        {:error, _} ->
          socket =
            socket
            |> put_flash(:error, "Could not find email to update")
            |> assign(:unsubscribe_task, nil)

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle task crash
  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    if socket.assigns[:unsubscribe_task] && socket.assigns.unsubscribe_task.task.ref == ref do
      # Get the email that was being processed and mark as failed
      case Email.get(socket.assigns.unsubscribe_task.email_id) do
        {:ok, email} ->
          case Email.complete_unsubscribe_failure(email, "Process crashed unexpectedly") do
            {:ok, updated_email} ->
              socket =
                socket
                |> put_flash(:error, "Unsubscribe process failed unexpectedly")
                |> assign(:unsubscribe_task, nil)
                |> stream_insert(:emails, updated_email)
                |> maybe_update_selected_email(updated_email)

              {:noreply, socket}

            {:error, _changeset} ->
              socket =
                socket
                |> put_flash(:error, "Unsubscribe process failed and could not update status")
                |> assign(:unsubscribe_task, nil)

              {:noreply, socket}
          end

        {:error, _} ->
          socket =
            socket
            |> put_flash(:error, "Unsubscribe process failed unexpectedly")
            |> assign(:unsubscribe_task, nil)

          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
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
            socket =
              socket
              |> stream_insert(:emails, updated_email)
              |> assign(:selected_email, nil)
              |> maybe_update_selected_email(updated_email)

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to mark email as unread")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email not found")}
    end
  end

  def handle_event("unsubscribe_email", %{"id" => email_id}, socket) do
    case Email.get(email_id) do
      {:ok, email} ->
        if Email.unsubscribe_processing?(email) do
          {:noreply,
           put_flash(socket, :info, "Unsubscribe is already in progress for this email")}
        else
          case Email.start_unsubscribe(email) do
            {:ok, updated_email} ->
              task =
                Task.async(fn ->
                  SmartSort.AI_Reactor.UnsubscribeService.unsubscribe(
                    updated_email,
                    socket.assigns.user.email
                  )
                end)

              socket =
                socket
                |> assign(:unsubscribe_task, %{task: task, email_id: updated_email.id})
                |> stream_insert(:emails, updated_email)
                |> maybe_update_selected_email(updated_email)
                |> put_flash(
                  :info,
                  "Starting unsubscribe process for #{email.from_name || email.from_email}..."
                )

              {:noreply, socket}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to start unsubscribe process")}
          end
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Email not found")}
    end
  end

  def handle_event("toggle_email_selection", %{"id" => email_id}, socket) do
    email_id = String.to_integer(email_id)

    # Find the email in current_page_emails to get the current selection state
    case Enum.find(socket.assigns.current_page_emails, &(&1.id == email_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Email not found")}

      email ->
        # Toggle the selection state
        updated_email = %{email | is_selected: !email.is_selected}

        # Update the selected count
        current_count = socket.assigns.selected_count
        new_count = if updated_email.is_selected, do: current_count + 1, else: current_count - 1

        # Update the current_page_emails assign to keep it in sync
        updated_page_emails =
          Enum.map(socket.assigns.current_page_emails, fn page_email ->
            if page_email.id == email_id do
              updated_email
            else
              page_email
            end
          end)

        # Update the email in the stream, the count, and the page emails
        socket =
          socket
          |> stream_insert(:emails, updated_email)
          |> assign(:selected_count, new_count)
          |> assign(:current_page_emails, updated_page_emails)

        {:noreply, socket}
    end
  end

  def handle_event("select_all_emails", _params, socket) do
    # Update all emails to be selected
    updated_emails =
      Enum.map(socket.assigns.current_page_emails, fn email ->
        %{email | is_selected: true}
      end)

    # Update the stream with all selected emails and set count
    socket =
      socket
      |> assign(:current_page_emails, updated_emails)
      |> assign(:selected_count, length(updated_emails))
      |> stream(:emails, updated_emails, reset: true)

    {:noreply, socket}
  end

  def handle_event("deselect_all_emails", _params, socket) do
    # Update all emails to be unselected
    updated_emails =
      Enum.map(socket.assigns.current_page_emails, fn email ->
        %{email | is_selected: false}
      end)

    # Update the stream with all unselected emails and reset count
    socket =
      socket
      |> assign(:current_page_emails, updated_emails)
      |> assign(:selected_count, 0)
      |> stream(:emails, updated_emails, reset: true)

    {:noreply, socket}
  end

  def handle_event("bulk_delete", _params, socket) do
    selected_emails =
      socket.assigns.current_page_emails
      |> Enum.filter(fn email -> email.is_selected end)

    if length(selected_emails) == 0 do
      {:noreply, put_flash(socket, :error, "No emails selected")}
    else
      selected_count = length(selected_emails)

      Enum.each(selected_emails, fn email ->
        Email.delete(email)
      end)

      socket =
        socket
        |> put_flash(:info, "Successfully deleted #{selected_count} emails")

      send(self(), :load_emails)
      {:noreply, socket}
    end
  end

  def handle_event("bulk_unsubscribe", _params, socket) do
    # Get selected emails from current page
    selected_emails =
      socket.assigns.current_page_emails
      |> Enum.filter(fn email -> email.is_selected end)

    if length(selected_emails) == 0 do
      {:noreply, put_flash(socket, :error, "No emails selected")}
    else
      selected_count = length(selected_emails)

      socket =
        socket
        |> assign(:bulk_action_processing, true)
        |> put_flash(:info, "Starting unsubscribe process for #{selected_count} emails...")

      # Perform bulk unsubscribe in background
      Task.start(fn ->
        results =
          Enum.map(selected_emails, fn email ->
            # Mark as processing
            case Email.start_unsubscribe(email) do
              {:ok, updated_email} ->
                # Perform unsubscribe
                case SmartSort.AI_Reactor.UnsubscribeService.unsubscribe(
                       updated_email,
                       socket.assigns.user.email
                     ) do
                  {:ok, %{success: true} = result} ->
                    Email.complete_unsubscribe_success(updated_email, result.details || "")
                    {:ok, :success}

                  {:ok, %{success: false} = result} ->
                    Email.complete_unsubscribe_failure(updated_email, result.details || "")
                    {:ok, :failed}

                  {:error, reason} ->
                    Email.complete_unsubscribe_failure(updated_email, inspect(reason))
                    {:ok, :failed}
                end

              {:error, _} ->
                {:error, :update_failed}
            end
          end)

        successful = Enum.count(results, &match?({:ok, :success}, &1))
        failed = Enum.count(results, &match?({:ok, :failed}, &1))

        send(
          self(),
          {:bulk_action_complete, :unsubscribe,
           %{total: selected_count, successful: successful, failed: failed}}
        )
      end)

      {:noreply, socket}
    end
  end

  def handle_info(
        {:bulk_action_complete, :unsubscribe,
         %{total: total, successful: successful, failed: failed}},
        socket
      ) do
    message =
      if failed == 0 do
        "Successfully unsubscribed from #{successful} emails"
      else
        "Unsubscribe completed: #{successful} successful, #{failed} failed out of #{total} emails"
      end

    socket =
      socket
      |> assign(:bulk_action_processing, false)
      |> put_flash(:info, message)

    # Reload emails to reflect status changes
    send(self(), :load_emails)
    {:noreply, socket}
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

        # Make sure all emails have is_selected set to false when loading
        emails_with_selection = Enum.map(emails, &Map.put(&1, :is_selected, false))

        socket =
          socket
          |> assign(:loading, false)
          |> assign(:total_emails, total_count)
          |> assign(:total_pages, total_pages)
          |> assign(:current_page_emails, emails_with_selection)
          |> assign(:selected_count, 0)
          |> stream(:emails, emails_with_selection, reset: true)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to load emails: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

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

  # Helper functions for unsubscribe task management
  defp get_verification_details(result) do
    case result do
      %{verification_details: details} when is_binary(details) -> details
      %{verification_info: info} when is_binary(info) -> info
      _ -> ""
    end
  end

  defp get_failure_debug_info(result) do
    case result do
      %{debug_info: info} when is_binary(info) -> info
      %{error_details: details} when is_binary(details) -> details
      %{automation_details: details} when is_binary(details) -> details
      _ -> ""
    end
  end
end
