defmodule SmartSortWeb.LandingLive do
  alias SmartSort.Macros.NotFound
  alias SmartSort.Accounts.User
  use SmartSortWeb, :live_view

  def mount(_params, session, socket) do
    current_user = get_current_user_from_session(session)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "SmartSort - AI Email Management")

    {:ok, socket}
  end

  def handle_event("sign_in_with_google", _params, socket) do
    {:noreply, redirect(socket, external: "/auth/google")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 via-white to-indigo-50">
      <!-- Navigation -->
      <nav class="relative max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 lg:px-8 py-6">
        <div class="flex items-center">
          <div class="flex items-center">
            <div class="w-10 h-10 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-lg flex items-center justify-center">
              <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M7 16V4m0 0L3 8l4 4m0-8l4 4-4 4m6 0v12m0 0l4-4-4-4m0 8l-4-4 4-4"
                />
              </svg>
            </div>
            <span class="ml-3 text-2xl font-bold text-gray-900">SmartSort</span>
          </div>
        </div>

        <%= if @current_user do %>
          <div class="flex items-center space-x-4">
            <img src={@current_user.avatar} alt="Avatar" class="w-8 h-8 rounded-full" />
            <span class="text-sm text-gray-700">Welcome, {@current_user.name}</span>
            <a
              href="/dashboard"
              class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-blue-700 transition-colors"
            >
              Go to Dashboard
            </a>
          </div>
        <% else %>
          <button
            phx-click="sign_in_with_google"
            class="bg-white text-gray-700 px-4 py-2 rounded-lg text-sm font-medium border border-gray-300 hover:bg-gray-50 transition-colors flex items-center space-x-2"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24">
              <path
                fill="#4285F4"
                d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
              />
              <path
                fill="#34A853"
                d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
              />
              <path
                fill="#FBBC04"
                d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
              />
              <path
                fill="#EA4335"
                d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
              />
            </svg>
            <span>Sign in</span>
          </button>
        <% end %>
      </nav>
      
    <!-- Hero Section -->
      <div class="relative">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-20 pb-16 text-center lg:pt-32">
          <!-- Floating Elements -->
          <div class="absolute top-20 left-10 w-20 h-20 bg-blue-100 rounded-full opacity-50 animate-pulse">
          </div>
          <div
            class="absolute top-40 right-20 w-16 h-16 bg-indigo-100 rounded-full opacity-50 animate-pulse"
            style="animation-delay: 1s"
          >
          </div>
          <div
            class="absolute bottom-20 left-20 w-12 h-12 bg-purple-100 rounded-full opacity-50 animate-pulse"
            style="animation-delay: 2s"
          >
          </div>

          <div class="relative">
            <!-- Badge -->
            <div class="inline-flex items-center px-4 py-2 rounded-full text-sm font-medium bg-blue-100 text-blue-800 mb-8">
              <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z"
                  clip-rule="evenodd"
                />
              </svg>
              Powered by Advanced AI
            </div>
            
    <!-- Main Headline -->
            <h1 class="text-5xl md:text-7xl font-bold text-gray-900 mb-6">
              <span class="bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent">
                Smart
              </span>
              Email Sorting <br />
              <span class="text-4xl md:text-5xl text-gray-600">Made Simple</span>
            </h1>
            
    <!-- Subtitle -->
            <p class="text-xl md:text-2xl text-gray-600 mb-8 max-w-3xl mx-auto leading-relaxed">
              Transform your Gmail chaos into organized categories. Let AI automatically sort, summarize, and manage your emails with intelligent precision.
            </p>
            
    <!-- CTA Buttons -->
            <%= if @current_user do %>
              <div class="flex flex-col sm:flex-row gap-4 justify-center items-center">
                <a
                  href="/dashboard"
                  class="bg-gradient-to-r from-blue-600 to-indigo-600 text-white px-8 py-4 rounded-xl text-lg font-semibold hover:shadow-2xl hover:scale-105 transition-all duration-300 flex items-center space-x-3"
                >
                  <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M7 16V4m0 0L3 8l4 4m0-8l4 4-4 4"
                    />
                  </svg>
                  <span>Go to Dashboard</span>
                </a>
              </div>
            <% else %>
              <div class="flex flex-col sm:flex-row gap-4 justify-center items-center">
                <button
                  phx-click="sign_in_with_google"
                  class="bg-gradient-to-r from-blue-600 to-indigo-600 text-white px-8 py-4 rounded-xl text-lg font-semibold hover:shadow-2xl hover:scale-105 transition-all duration-300 flex items-center space-x-3 group"
                >
                  <svg
                    class="w-6 h-6 group-hover:rotate-12 transition-transform duration-300"
                    viewBox="0 0 24 24"
                  >
                    <path
                      fill="currentColor"
                      d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                    />
                    <path
                      fill="currentColor"
                      d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                    />
                    <path
                      fill="currentColor"
                      d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                    />
                    <path
                      fill="currentColor"
                      d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                    />
                  </svg>
                  <span>Start Smart Sorting</span>
                </button>

                <div class="text-sm text-gray-500 flex items-center space-x-2">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path
                      fill-rule="evenodd"
                      d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span>Secure OAuth • No passwords needed</span>
                </div>
              </div>
            <% end %>
            
    <!-- Quick Stats -->
            <div class="mt-16 grid grid-cols-1 sm:grid-cols-3 gap-8 max-w-2xl mx-auto">
              <div class="text-center">
                <div class="text-3xl font-bold text-blue-600">AI-Powered</div>
                <div class="text-sm text-gray-500 mt-1">Automatic Categorization</div>
              </div>
              <div class="text-center">
                <div class="text-3xl font-bold text-indigo-600">Instant</div>
                <div class="text-sm text-gray-500 mt-1">Email Summaries</div>
              </div>
              <div class="text-center">
                <div class="text-3xl font-bold text-purple-600">Bulk</div>
                <div class="text-sm text-gray-500 mt-1">Smart Actions</div>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Features Preview -->
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div class="text-center mb-12">
          <h2 class="text-3xl font-bold text-gray-900 mb-4">How SmartSort Works</h2>
          <p class="text-lg text-gray-600">Three simple steps to email organization mastery</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <!-- Step 1 -->
          <div class="bg-white/60 backdrop-blur-sm rounded-2xl p-8 border border-white/20 hover:shadow-xl transition-all duration-300 relative">
            <div class="absolute -top-4 -left-4 w-8 h-8 bg-blue-500 text-white rounded-full flex items-center justify-center text-sm font-bold">
              1
            </div>
            <div class="w-12 h-12 bg-blue-100 rounded-xl flex items-center justify-center mb-6">
              <svg class="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-gray-900 mb-3">Create Categories</h3>
            <p class="text-gray-600">
              Define custom email categories with descriptions. AI learns your preferences.
            </p>
          </div>
          
    <!-- Step 2 -->
          <div class="bg-white/60 backdrop-blur-sm rounded-2xl p-8 border border-white/20 hover:shadow-xl transition-all duration-300 relative">
            <div class="absolute -top-4 -left-4 w-8 h-8 bg-indigo-500 text-white rounded-full flex items-center justify-center text-sm font-bold">
              2
            </div>
            <div class="w-12 h-12 bg-indigo-100 rounded-xl flex items-center justify-center mb-6">
              <svg
                class="w-6 h-6 text-indigo-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-gray-900 mb-3">AI Auto-Sort</h3>
            <p class="text-gray-600">
              Emails are automatically categorized and summarized as they arrive.
            </p>
          </div>
          
    <!-- Step 3 -->
          <div class="bg-white/60 backdrop-blur-sm rounded-2xl p-8 border border-white/20 hover:shadow-xl transition-all duration-300 relative">
            <div class="absolute -top-4 -left-4 w-8 h-8 bg-purple-500 text-white rounded-full flex items-center justify-center text-sm font-bold">
              3
            </div>
            <div class="w-12 h-12 bg-purple-100 rounded-xl flex items-center justify-center mb-6">
              <svg
                class="w-6 h-6 text-purple-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 10V3L4 14h7v7l9-11h-7z"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-gray-900 mb-3">Bulk Actions</h3>
            <p class="text-gray-600">
              Take actions on multiple emails at once. Archive, delete, or unsubscribe intelligently.
            </p>
          </div>
        </div>
      </div>
      
    <!-- Footer -->
      <footer class="border-t border-gray-200 bg-white/50 backdrop-blur-sm">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div class="flex justify-between items-center">
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
              <span class="ml-2 text-lg font-semibold text-gray-900">SmartSort</span>
            </div>
            <p class="text-sm text-gray-500">© 2025 SmartSort. Making email smart.</p>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  defp get_current_user_from_session(session) do
    case session["user_id"] do
      nil ->
        nil

      user_id ->
        case User.get(user_id) do
          {:ok, user} -> user
          {:error, %NotFound{}} -> nil
        end
    end
  end
end
