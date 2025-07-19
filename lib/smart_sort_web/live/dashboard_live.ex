defmodule SmartSortWeb.DashboardLive do
  alias SmartSort.Accounts
  alias SmartSort.Accounts.Category
  alias SmartSort.Accounts.User
  use SmartSortWeb, :live_view

  alias SmartSortWeb.DashboardComponents

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center">
              <div class="w-8 h-8 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-lg flex items-center justify-center">
                <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M7 16V4m0 0L3 8l4 4m0-8l4 4-4 4"
                  />
                </svg>
              </div>
              <h1 class="ml-3 text-xl font-semibold text-gray-900">SmartSort</h1>
            </div>

            <div class="flex items-center space-x-4">
              <img src={@user.avatar} alt="Avatar" class="w-8 h-8 rounded-full" />
              <span class="text-sm text-gray-700">{@user.name}</span>
              <button phx-click="logout" class="text-gray-500 hover:text-gray-700 text-sm">
                Sign out
              </button>
            </div>
          </div>
        </div>
      </header>
      
    <!-- Main Content -->
      <main class="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        <div class="space-y-8">
          <DashboardComponents.gmail_accounts_section
            user={@user}
            connected_accounts={@connected_accounts}
          />

          <DashboardComponents.categories_section
            categories_count={@categories_count}
            categories={@streams.categories}
            show_form={@show_category_form}
            category_form={@category_form}
          />
        </div>
      </main>
    </div>
    """
  end

  def mount(_params, session, socket) do
    user = get_user_from_session(session)

    socket =
      socket
      |> assign(:user, user)
      |> assign(:page_title, "Dashboard")
      |> assign(:categories_count, length(user.categories))
      |> stream(:categories, user.categories)
      |> assign(:connected_accounts, SmartSort.Accounts.get_user_connected_accounts(user.id))
      |> assign(:show_category_form, false)
      |> assign(:category_form, to_form(Category.changeset(%Category{})))

    {:ok, socket}
  end

  def handle_event("show_category_form", _params, socket) do
    {:noreply, assign(socket, :show_category_form, true)}
  end

  def handle_event("hide_category_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_category_form, false)
     |> assign(:category_form, to_form(Category.changeset(%Category{})))}
  end

  def handle_event("validate_category", %{"category" => category_params}, socket) do
    changeset =
      %Category{}
      |> Category.changeset(Map.put(category_params, "user_id", socket.assigns.user.id))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :category_form, to_form(changeset))}
  end

  def handle_event("create_category", %{"category" => category_params}, socket) do
    case Accounts.create_category(Map.put(category_params, "user_id", socket.assigns.user.id)) do
      {:ok, category} ->
        {:noreply,
         socket
         |> stream_insert(:categories, category)
         |> assign(:categories_count, socket.assigns.categories_count + 1)
         |> assign(:show_category_form, false)
         |> assign(:category_form, to_form(Category.changeset(%Category{})))
         |> put_flash(:info, "Category created successfully!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :category_form, to_form(changeset))}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Category.get!(id)

    {:noreply,
     socket
     |> stream_delete(:categories, category)
     |> assign(:categories_count, socket.assigns.categories_count - 1)
     |> put_flash(:info, "Category deleted successfully")}
  end

  def handle_event("connect_gmail_account", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/add-account")}
  end

  def handle_event("logout", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/logout")}
  end

  defp get_user_from_session(session) do
    case session["user_id"] do
      nil -> nil
      user_id -> User.get!(user_id, [:categories])
    end
  end
end
