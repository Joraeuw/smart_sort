defmodule SmartSortWeb.DashboardComponents do
  use SmartSortWeb, :html

  require SmartSortWeb.CoreComponents

  attr :user, :map, required: true, doc: "The current user with primary email info"
  attr :connected_accounts, :list, default: [], doc: "List of additional connected Gmail accounts"

  def gmail_accounts_section(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <h2 class="text-lg font-medium text-gray-900">Connected Gmail Accounts</h2>
        <p class="mt-1 text-sm text-gray-500">
          Connect multiple Gmail accounts to manage all your inboxes in one place
        </p>
      </div>

      <div class="p-6">
        <.primary_account_card user={@user} />

        <%= for account <- @connected_accounts do %>
          <.connected_account_card account={account} />
        <% end %>

        <.action_button click="connect_gmail_account" label="Connect Another Gmail Account" />
      </div>
    </div>
    """
  end

  attr :categories, :any
  attr :categories_count, :integer
  attr :show_form, :boolean, default: false, doc: "Whether to show the category creation form"
  attr :category_form, Phoenix.HTML.Form, required: true

  def categories_section(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow">
      <div class="px-6 py-4 border-b border-gray-200">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-medium text-gray-900">Email Categories</h2>
            <p class="mt-1 text-sm text-gray-500">
              AI will automatically sort your emails into these categories
            </p>
          </div>
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
            {@categories_count} categories
          </span>
        </div>
      </div>

      <div class="p-6">
        <%= if @categories_count == 0 do %>
          <.empty_categories_state />
        <% else %>
          <.categories_list categories={@categories} />
        <% end %>

        <%= if @show_form do %>
          <.category_form form={@category_form} />
        <% else %>
          <.action_button click="show_category_form" label="Add New Category" />
        <% end %>
      </div>
    </div>
    """
  end

  attr :user, :map, required: true

  defp primary_account_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 bg-green-50 border border-green-200 rounded-lg mb-4">
      <div class="flex items-center space-x-3">
        <div class="w-10 h-10 bg-green-100 rounded-full flex items-center justify-center">
          <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
            <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
          </svg>
        </div>
        <div>
          <p class="text-sm font-medium text-gray-900">{@user.email}</p>
          <p class="text-xs text-green-600">Primary Account • Connected</p>
        </div>
      </div>
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
        Active
      </span>
    </div>
    """
  end

  attr :account, :map, required: true

  defp connected_account_card(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg mb-3">
      <div class="flex items-center space-x-3">
        <div class="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
          <svg class="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
            <path d="M2.003 5.884L10 9.882l7.997-3.998A2 2 0 0016 4H4a2 2 0 00-1.997 1.884z" />
            <path d="M18 8.118l-8 4-8-4V14a2 2 0 002 2h12a2 2 0 002-2V8.118z" />
          </svg>
        </div>
        <div>
          <p class="text-sm font-medium text-gray-900">{@account.email}</p>
          <p class="text-xs text-blue-600">Connected</p>
        </div>
      </div>
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
        Active
      </span>
    </div>
    """
  end

  defp empty_categories_state(assigns) do
    ~H"""
    <div class="text-center py-12">
      <svg
        class="mx-auto h-12 w-12 text-gray-400"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 48 48"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M20 12H8a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
        />
      </svg>
      <h3 class="mt-2 text-sm font-medium text-gray-900">No categories yet</h3>
      <p class="mt-1 text-sm text-gray-500">
        Get started by creating your first email category.
      </p>
    </div>
    """
  end

  attr :categories, :list, required: true

  defp categories_list(assigns) do
    ~H"""
    <div id="categories" phx-update="stream" class="space-y-3">
      <%= for {idx, category} <- @categories do %>
        <.category_card id={idx} category={category} />
      <% end %>
    </div>
    """
  end

  attr :id, :string
  attr :category, :map, required: true

  defp category_card(assigns) do
    ~H"""
    <div id={@id} class="group">
      <.link navigate={~p"/categories/#{@category.id}/emails"}>
        <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg hover:border-gray-300 transition-colors">
          <div class="flex items-center space-x-4">
            <div class="w-10 h-10 bg-gradient-to-r from-blue-500 to-indigo-500 rounded-lg flex items-center justify-center">
              <span class="text-white font-medium text-sm">
                {String.first(@category.name) |> String.upcase()}
              </span>
            </div>
            <div>
              <h3 class="text-sm font-medium text-gray-900">{@category.name}</h3>
              <p class="text-sm text-gray-500">{@category.description}</p>
            </div>
          </div>

          <div class="flex items-center space-x-3">
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
              {@category.email_count} emails
            </span>
            <button
              phx-click="delete_category"
              phx-value-id={@category.id}
              class="text-gray-400 hover:text-red-500 transition-colors"
              onclick="return confirm('Are you sure you want to delete this category?')"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
            </button>
          </div>
        </div>
      </.link>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp category_form(assigns) do
    ~H"""
    <.form for={@form} phx-change="validate_category" phx-submit="create_category" class="mt-4 space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Category Name
        </label>
        <.input
          field={@form[:name]}
          type="text"
          placeholder="e.g., Newsletters, Work, Personal"
          class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
          required
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 mb-2">
          Description
        </label>
        <.input
          field={@form[:description]}
          type="textarea"
          placeholder="Describe what types of emails should go in this category..."
          rows="3"
          class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
        />
      </div>

      <div class="flex space-x-3">
        <button
          type="submit"
          class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 6v6m0 0v6m0-6h6m-6 0H6"
            />
          </svg>
          Create Category
        </button>

        <button
          type="button"
          phx-click="hide_category_form"
          class="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          Cancel
        </button>
      </div>
    </.form>
    """
  end

  defp action_button(assigns) do
    ~H"""
    <button
      phx-click={@click}
      class="w-full mt-4 flex items-center justify-center px-4 py-3 border-2 border-dashed border-gray-300 rounded-lg text-base font-medium text-gray-600 hover:border-gray-400 hover:text-gray-700 transition-colors"
    >
      <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 6v6m0 0v6m0-6h6m-6 0H6"
        />
      </svg>
      <%= @label %>
    </button>
    """
  end
end
