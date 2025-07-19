defmodule SmartSortWeb.EmailComponents do
  use SmartSortWeb, :html

  attr :emails, :list, required: true
  attr :selected_email, :map, default: nil

  def email_list(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      <div id="emails" phx-update="stream" class="divide-y divide-gray-200">
        <%= for {id, email} <- @emails do %>
          <.email_card id={id} email={email} selected={@selected_email && @selected_email.id == email.id} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :email, :map, required: true
  attr :selected, :boolean, default: false

  def email_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "p-4 hover:bg-gray-50 cursor-pointer transition-colors duration-150",
        @selected && "bg-blue-50 border-l-4 border-blue-500",
        !@email.is_read && "bg-blue-25"
      ]}
      phx-click="select_email"
      phx-value-id={@email.id}
    >
      <div class="flex items-start justify-between">
        <div class="flex-1 min-w-0">
          <div class="flex items-center space-x-3 mb-2">
            <!-- Read/Unread indicator -->
            <div class={[
              "w-2 h-2 rounded-full flex-shrink-0",
              @email.is_read && "bg-gray-300",
              !@email.is_read && "bg-blue-500"
            ]}>
            </div>

            <!-- Sender info -->
            <div class="flex items-center space-x-2 flex-1 min-w-0">
              <div class="w-8 h-8 bg-gradient-to-r from-gray-500 to-gray-600 rounded-full flex items-center justify-center flex-shrink-0">
                <span class="text-white text-xs font-medium">
                  {get_sender_initials(@email)}
                </span>
              </div>
              <div class="min-w-0 flex-1">
                <p class={[
                  "text-sm truncate",
                  @email.is_read && "text-gray-700",
                  !@email.is_read && "text-gray-900 font-medium"
                ]}>
                  {@email.from_name || @email.from_email}
                </p>
                <p class="text-xs text-gray-500 truncate">{@email.from_email}</p>
              </div>
            </div>

            <!-- Time -->
            <div class="text-xs text-gray-500 flex-shrink-0">
              {format_email_time(@email.received_at)}
            </div>
          </div>

          <!-- Subject -->
          <h3 class={[
            "text-sm mb-1 truncate",
            @email.is_read && "text-gray-700",
            !@email.is_read && "text-gray-900 font-medium"
          ]}>
            {@email.subject || "(No subject)"}
          </h3>

          <!-- Snippet/Preview -->
          <p class="text-sm text-gray-600 line-clamp-2">
            {@email.snippet || @email.ai_summary || "No preview available"}
          </p>

          <!-- Tags/Labels -->
          <div class="flex items-center justify-between mt-3">
            <div class="flex items-center space-x-2">
              <%= if @email.ai_summary do %>
                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800">
                  <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                  </svg>
                  AI Summary
                </span>
              <% end %>

              <%= if @email.is_archived do %>
                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                  Archived
                </span>
              <% end %>
            </div>

            <!-- Quick actions -->
            <div class="flex items-center space-x-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <%= if @email.is_read do %>
                <button
                  phx-click="mark_as_unread"
                  phx-value-id={@email.id}
                  class="p-1 text-gray-400 hover:text-blue-600 transition-colors"
                  title="Mark as unread"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 7.89a2 2 0 002.83 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                  </svg>
                </button>
              <% else %>
                <button
                  phx-click="mark_as_read"
                  phx-value-id={@email.id}
                  class="p-1 text-gray-400 hover:text-green-600 transition-colors"
                  title="Mark as read"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :email, :map, required: true
  attr :category, :map, required: true

  def email_detail_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 overflow-y-auto">
      <div class="flex min-h-screen items-center justify-center p-4">
        <!-- Backdrop -->
        <div phx-click="close_email_detail" class="fixed inset-0 z-40 bg-gray-100 bg-opacity-50"></div>

        <!-- Modal -->
        <div
          class="relative bg-white z-50 rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden"
        >
          <!-- Header -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <div class="flex items-center space-x-3">
              <div class="w-10 h-10 bg-gradient-to-r from-gray-500 to-gray-600 rounded-full flex items-center justify-center">
                <span class="text-white text-sm font-medium">
                  {get_sender_initials(@email)}
                </span>
              </div>
              <div>
                <h2 class="text-lg font-medium text-gray-900">
                  {@email.subject || "(No subject)"}
                </h2>
                <p class="text-sm text-gray-500">
                  in {@category.name}
                </p>
              </div>
            </div>

            <button
              phx-click="close_email_detail"
              class="text-gray-400 hover:text-gray-600 transition-colors"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Email metadata -->
          <div class="px-6 py-4 border-b border-gray-100 bg-gray-50">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
              <div>
                <span class="font-medium text-gray-700">From:</span>
                <span class="ml-2 text-gray-900">
                  {@email.from_name || @email.from_email}
                  <span class="text-gray-500">&lt;{@email.from_email}&gt;</span>
                </span>
              </div>
              <div>
                <span class="font-medium text-gray-700">Date:</span>
                <span class="ml-2 text-gray-900">{format_full_date(@email.received_at)}</span>
              </div>
              <div>
                <span class="font-medium text-gray-700">To:</span>
                <span class="ml-2 text-gray-900">{@email.to_email || "Multiple recipients"}</span>
              </div>
              <div>
                <span class="font-medium text-gray-700">Category:</span>
                <span class="ml-2">
                  <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                    {@category.name}
                  </span>
                </span>
              </div>
            </div>
          </div>

          <!-- AI Summary (if available) -->
          <%= if @email.ai_summary do %>
            <div class="px-6 py-4 border-b border-gray-100 bg-purple-50">
              <div class="flex items-start space-x-3">
                <div class="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center flex-shrink-0">
                  <svg class="w-4 h-4 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
                  </svg>
                </div>
                <div class="flex-1">
                  <h3 class="text-sm font-medium text-purple-900 mb-1">AI Summary</h3>
                  <p class="text-sm text-purple-800">{@email.ai_summary}</p>
                </div>
              </div>
            </div>
          <% end %>

          <!-- Email content -->
          <div class="flex-1 overflow-y-auto p-6">
            <div class="email-body-container">
              <%= render_email_body(@email) %>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex items-center justify-between p-6 border-t border-gray-200 bg-gray-50">
            <div class="flex items-center space-x-3">
              <%= if @email.is_read do %>
                <button
                  phx-click="mark_as_unread"
                  phx-value-id={@email.id}
                  class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Mark as unread
                </button>
              <% else %>
                <button
                  phx-click="mark_as_read"
                  phx-value-id={@email.id}
                  class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  Mark as read
                </button>
              <% end %>

              <!-- Toggle between full body and snippet -->
              <%= if has_full_body?(@email) do %>
                <button
                  phx-click="toggle_email_view"
                  phx-value-id={@email.id}
                  class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <%= if true do %>
                    Show snippet
                  <% else %>
                    Show full email
                  <% end %>
                </button>
              <% end %>
            </div>

            <button
              phx-click="close_email_detail"
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to render email body safely
  defp render_email_body(email) do
    assigns = %{email: email}

    ~H"""
    <%= cond do %>
      <% @email.body && String.trim(@email.body) != "" -> %>
        <%= render_body_content(@email) %>
      <% @email.snippet && String.trim(@email.snippet) != "" -> %>
        <div class="email-snippet">
          <div class="text-sm text-gray-500 mb-2 italic">Email preview:</div>
          <div class="whitespace-pre-wrap text-gray-900 leading-relaxed">
            {@email.snippet}
          </div>
        </div>
      <% true -> %>
        <div class="text-gray-500 italic text-center py-8">
          Email content not available
        </div>
    <% end %>
    """
  end

  # Render the actual body content based on type
  defp render_body_content(email) do
    assigns = %{email: email}

    ~H"""
    <%= if is_html_content?(@email) do %>
      <!-- HTML Email Content -->
      <div class="html-email-content prose max-w-none">
        <%= raw(sanitize_html_content(@email.body)) %>
      </div>
    <% else %>
      <!-- Plain Text Email Content -->
      <div class="plain-text-email">
        <div class="whitespace-pre-wrap text-gray-900 leading-relaxed font-mono text-sm bg-gray-50 p-4 rounded border">
          {@email.body}
        </div>
      </div>
    <% end %>
    """
  end

  # Helper functions you'll need to add to your LiveView module
  defp has_full_body?(email) do
    email.body && String.trim(email.body) != "" &&
      String.length(email.body) > String.length(email.snippet || "")
  end

  defp is_html_content?(email) do
    # Check if body_type field exists and is HTML, or detect HTML content
    case Map.get(email, :body_type) do
      "text/html" ->
        true

      _ ->
        # Fallback: detect HTML tags in content
        email.body && String.contains?(email.body, ["<html>", "<div>", "<p>", "<br>", "<table>"])
    end
  end

  defp sanitize_html_content(html_content) when is_binary(html_content) do
    # Basic HTML sanitization - you might want to use HtmlSanitizeEx for production
    html_content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/ims, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/ims, "")
    # Remove event handlers
    |> String.replace(~r/on\w+\s*=\s*["'][^"']*["']/i, "")
    |> String.replace(~r/javascript:/i, "")
    # Remove external stylesheets
    |> String.replace(~r/<link[^>]*>/i, "")
    |> limit_html_content()
  end

  defp sanitize_html_content(_), do: ""

  # Limit HTML content size for performance
  defp limit_html_content(html) do
    if String.length(html) > 100_000 do
      String.slice(html, 0, 100_000) <>
        "\n\n<div class='text-gray-500 italic'>... [Content truncated for performance]</div>"
    else
      html
    end
  end

  def loading_state(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
      <div class="flex items-center justify-center">
        <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <span class="ml-3 text-gray-600">Loading emails...</span>
      </div>
    </div>
    """
  end

  attr :category, :map, required: true

  def empty_state(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-12">
      <div class="text-center">
        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 48 48">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M34 8l-8-4-8 4-8-4v20l8 4 8-4 8 4 8-4V8l-8 4zM16 8v20M32 8v20" />
        </svg>
        <h3 class="mt-4 text-lg font-medium text-gray-900">No emails found</h3>
        <p class="mt-2 text-gray-500">
          There are no emails in the "{@category.name}" category yet.
        </p>
        <p class="mt-1 text-sm text-gray-400">
          Emails will appear here automatically as they're classified by AI.
        </p>
      </div>
    </div>
    """
  end

  attr :current_page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :total_emails, :integer, required: true

  def pagination(assigns) do
    ~H"""
    <div class="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6 mt-6 rounded-lg shadow-sm">
      <div class="flex-1 flex justify-between sm:hidden">
        <%= if @current_page > 1 do %>
          <button
            phx-click="page"
            phx-value-page={@current_page - 1}
            class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Previous
          </button>
        <% end %>
        <%= if @current_page < @total_pages do %>
          <button
            phx-click="page"
            phx-value-page={@current_page + 1}
            class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50"
          >
            Next
          </button>
        <% end %>
      </div>

      <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
        <div>
          <p class="text-sm text-gray-700">
            Showing page <span class="font-medium">{@current_page}</span> of
            <span class="font-medium">{@total_pages}</span>
            (<span class="font-medium">{@total_emails}</span> total emails)
          </p>
        </div>
        <div>
          <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px">
            <%= if @current_page > 1 do %>
              <button
                phx-click="page"
                phx-value-page={@current_page - 1}
                class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </button>
            <% end %>

            <!-- Page numbers -->
            <%= for page <- page_range(@current_page, @total_pages) do %>
              <button
                phx-click="page"
                phx-value-page={page}
                class={[
                  "relative inline-flex items-center px-4 py-2 border text-sm font-medium",
                  page == @current_page && "z-10 bg-blue-50 border-blue-500 text-blue-600",
                  page != @current_page && "bg-white border-gray-300 text-gray-500 hover:bg-gray-50"
                ]}
              >
                {page}
              </button>
            <% end %>

            <%= if @current_page < @total_pages do %>
              <button
                phx-click="page"
                phx-value-page={@current_page + 1}
                class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50"
              >
                <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
              </button>
            <% end %>
          </nav>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_sender_initials(email) do
    case email.from_name do
      nil ->
        email.from_email
        |> String.split("@")
        |> List.first()
        |> String.slice(0, 2)
        |> String.upcase()

      name ->
        name
        |> String.split(" ")
        |> Enum.map(&String.first/1)
        |> Enum.take(2)
        |> Enum.join()
        |> String.upcase()
    end
  end

  defp format_email_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_full_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp page_range(current_page, total_pages) do
    start_page = max(1, current_page - 2)
    end_page = min(total_pages, current_page + 2)

    start_page..end_page |> Enum.to_list()
  end
end
