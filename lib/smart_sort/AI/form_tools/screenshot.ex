defmodule SmartSort.AI.FormTools.Screenshot do
  @moduledoc """
  Handles taking screenshots for form analysis and automation.
  Provides utilities for capturing web page screenshots using Wallaby.
  """

  require Logger

  def take_screenshot_with_session(session, label) do
    Logger.info("[SCREENSHOT] Taking full-page screenshot with existing session: #{label}")

    try do
      screenshot_name = generate_screenshot_path(label)

      session_with_larger_window =
        Wallaby.Browser.resize_window(session, 1280, 2400)

      session_at_top =
        Wallaby.Browser.execute_script(session_with_larger_window, "window.scrollTo(0, 0);")

      session_scrolled =
        Wallaby.Browser.execute_script(session_at_top, """
          // Scroll to the very bottom to ensure all content is loaded
          window.scrollTo(0, document.body.scrollHeight);

          // Wait a moment for any dynamic content to load
          return new Promise(resolve => {
            setTimeout(() => {
              // Scroll back to top for the screenshot
              window.scrollTo(0, 0);
              resolve();
            }, 500);
          });
        """)

      updated_session = Wallaby.Browser.take_screenshot(session_scrolled, name: screenshot_name)

      full_path = build_full_path(screenshot_name)

      case File.read(full_path) do
        {:ok, image_data} ->
          File.rm(full_path)

          screenshot_data = %{
            label: label,
            timestamp: DateTime.utc_now(),
            size: byte_size(image_data),
            data: Base.encode64(image_data),
            filename: screenshot_name
          }

          Logger.info(
            "[SCREENSHOT] Full-page screenshot captured successfully: #{byte_size(image_data)} bytes (1280x1200 window)"
          )

          {:ok, screenshot_data, updated_session}

        {:error, reason} ->
          Logger.error("[SCREENSHOT] Failed to read screenshot file: #{reason}")
          {:error, "Failed to read screenshot file: #{reason}", updated_session}
      end
    rescue
      error ->
        Logger.error("[SCREENSHOT] Screenshot capture failed: #{inspect(error)}")
        {:error, "Screenshot capture failed: #{inspect(error)}", session}
    end
  end

  @doc """
  Takes a screenshot of the given URL and returns the path to the saved image.

  ## Examples

      iex> take_screenshot("https://example.com")
      {:ok, "/tmp/wallaby_screenshots/screenshot_1641234567890.png"}

      iex> take_screenshot("invalid-url")
      {:error, "Failed to navigate to URL"}
  """
  def take_screenshot(url) do
    Logger.info("Taking screenshot of: #{url}")

    try do
      {:ok, session} = Wallaby.start_session()
      session = Wallaby.Browser.visit(session, url)

      # Wait for page to fully load
      :timer.sleep(2000)

      screenshot_path = generate_screenshot_path()
      session = Wallaby.Browser.take_screenshot(session, name: screenshot_path)

      Wallaby.end_session(session)
      full_path = build_full_path(screenshot_path)

      case File.exists?(full_path) do
        true ->
          Logger.info("[SCREENSHOT] Screenshot saved: #{full_path}")
          {:ok, full_path}

        false ->
          Logger.error("[SCREENSHOT] Screenshot file not found after capture")
          {:error, "Screenshot file not created"}
      end
    rescue
      error ->
        Logger.error("[SCREENSHOT] Screenshot failed: #{inspect(error)}")
        {:error, "Screenshot capture failed: #{inspect(error)}"}
    end
  end

  @doc """
  Takes a screenshot with a custom name.

  ## Examples

      iex> take_screenshot_named("https://example.com", "my_screenshot")
      {:ok, "/tmp/wallaby_screenshots/my_screenshot.png"}
  """
  def take_screenshot_named(url, name) do
    Logger.info("[SCREENSHOT] Taking named screenshot '#{name}' of: #{url}")

    try do
      {:ok, session} = Wallaby.start_session()
      session = Wallaby.Browser.visit(session, url)

      # Wait for page to fully load
      :timer.sleep(2000)

      session = Wallaby.Browser.take_screenshot(session, name: name)

      Wallaby.end_session(session)

      full_path = build_full_path("#{name}.png")

      case File.exists?(full_path) do
        true ->
          Logger.info("[SCREENSHOT] Named screenshot saved: #{full_path}")
          {:ok, full_path}

        false ->
          Logger.error("[SCREENSHOT] Named screenshot file not found after capture")
          {:error, "Screenshot file not created"}
      end
    rescue
      error ->
        Logger.error("[SCREENSHOT] Named screenshot failed: #{inspect(error)}")
        {:error, "Screenshot capture failed: #{inspect(error)}"}
    end
  end

  @doc """
  Takes a screenshot and automatically cleans it up after the given function completes.

  ## Examples

      iex> take_screenshot_with_cleanup("https://example.com", fn path ->
      ...>   File.read!(path) |> Base.encode64()
      ...> end)
      {:ok, "base64_encoded_image_data"}
  """
  def take_screenshot_with_cleanup(url, process_fn) when is_function(process_fn, 1) do
    case take_screenshot(url) do
      {:ok, screenshot_path} ->
        try do
          result = process_fn.(screenshot_path)
          delete_screenshot(screenshot_path)
          {:ok, result}
        rescue
          error ->
            delete_screenshot(screenshot_path)
            {:error, "Processing failed: #{inspect(error)}"}
        end

      error ->
        error
    end
  end

  @doc """
  Takes a full-page screenshot capturing the entire page content including below the fold.

  ## Examples

      iex> take_full_page_screenshot("https://example.com")
      {:ok, "/tmp/wallaby_screenshots/fullpage_screenshot_1641234567890.png"}
  """
  def take_full_page_screenshot(url, wallaby_session) do
    Logger.info("[SCREENSHOT] Taking FULL PAGE screenshot of: #{url}")

    try do
      session = Wallaby.Browser.visit(wallaby_session, url)

      # Wait for page to fully load
      :timer.sleep(3000)

      # Get full page dimensions and resize browser
      session = prepare_full_page_capture(session)

      screenshot_path = generate_screenshot_path("fullpage")
      session = Wallaby.Browser.take_screenshot(session, name: screenshot_path)

      full_path = build_full_path(screenshot_path)

      case File.exists?(full_path) do
        true ->
          Logger.info("[SCREENSHOT] Full page screenshot saved: #{full_path}")
          {:ok, full_path, session}

        false ->
          Logger.error("[SCREENSHOT] Full page screenshot file not found after capture")
          {:error, "Screenshot file not created", session}
      end
    rescue
      error ->
        Logger.error("[SCREENSHOT] Full page screenshot failed: #{inspect(error)}")
        {:error, "Full page screenshot capture failed: #{inspect(error)}"}
    end
  end

  @doc """
  Takes a full-page screenshot with a custom name.
  """
  def take_full_page_screenshot_named(url, name) do
    Logger.info("[SCREENSHOT] Taking named full page screenshot '#{name}' of: #{url}")

    try do
      {:ok, session} = Wallaby.start_session()
      session = Wallaby.Browser.visit(session, url)

      # Wait for page to fully load
      :timer.sleep(3000)

      # Get full page dimensions and resize browser
      session = prepare_full_page_capture(session)

      session = Wallaby.Browser.take_screenshot(session, name: "fullpage_#{name}")

      Wallaby.end_session(session)

      full_path = build_full_path("fullpage_#{name}.png")

      case File.exists?(full_path) do
        true ->
          Logger.info("[SCREENSHOT] Named full page screenshot saved: #{full_path}")
          {:ok, full_path}

        false ->
          Logger.error("[SCREENSHOT] Named full page screenshot file not found after capture")
          {:error, "Screenshot file not created"}
      end
    rescue
      error ->
        Logger.error("[SCREENSHOT] Named full page screenshot failed: #{inspect(error)}")
        {:error, "Screenshot capture failed: #{inspect(error)}"}
    end
  end

  @doc """
  Deletes a screenshot file.

  ## Examples

      iex> delete_screenshot("/tmp/wallaby_screenshots/screenshot.png")
      :ok
  """
  def delete_screenshot(screenshot_path) do
    case File.rm(screenshot_path) do
      :ok ->
        Logger.info("[SCREENSHOT] Cleaned up screenshot: #{screenshot_path}")
        :ok

      {:error, reason} ->
        Logger.warning("[SCREENSHOT] Failed to delete screenshot #{screenshot_path}: #{reason}")
        {:error, reason}
    end
  end

  defp generate_screenshot_path(prefix \\ "screenshot") do
    timestamp = System.system_time(:millisecond)
    "#{prefix}_#{timestamp}"
  end

  defp build_full_path(filename) do
    filename = if String.ends_with?(filename, ".png"), do: filename, else: "#{filename}.png"
    Path.join(["screenshots/wallaby", filename])
  end

  @doc """
  Takes a full-page screenshot with automatic cleanup.
  """
  def take_full_page_screenshot_with_cleanup(url, wallaby_session, process_fn)
      when is_function(process_fn, 1) do
    case take_full_page_screenshot(url, wallaby_session) do
      {:ok, screenshot_path, changed_wallaby_session} ->
        try do
          result = process_fn.(screenshot_path)
          delete_screenshot(screenshot_path)
          {:ok, result, changed_wallaby_session}
        rescue
          error ->
            delete_screenshot(screenshot_path)
            {:error, "Processing failed: #{inspect(error)}"}
        end

      error ->
        error
    end
  end

  defp prepare_full_page_capture(session) do
    Logger.info("[SCREENSHOT] [FULLPAGE] Preparing full-page capture...")

    try do
      # Get page dimensions using JavaScript
      page_info =
        Wallaby.Browser.execute_script(session, """
          return {
            documentHeight: Math.max(
              document.documentElement.scrollHeight,
              document.documentElement.offsetHeight,
              document.documentElement.clientHeight
            ),
            bodyHeight: Math.max(
              document.body.scrollHeight,
              document.body.offsetHeight,
              document.body.clientHeight
            ),
            windowHeight: window.innerHeight,
            windowWidth: window.innerWidth,
            hasScrollableContent: document.documentElement.scrollHeight > window.innerHeight
          };
        """)

      Logger.info(
        "[SCREENSHOT] [FULLPAGE] Page dimensions - Document: #{page_info["documentHeight"]}px, Body: #{page_info["bodyHeight"]}px, Viewport: #{page_info["windowHeight"]}px"
      )

      # Use the larger of document or body height
      full_height = max(page_info["documentHeight"], page_info["bodyHeight"])
      current_width = page_info["windowWidth"]

      # Ensure minimum dimensions and reasonable maximums
      # Cap at 10k pixels
      final_height = max(full_height, 800) |> min(10000)
      # Cap at 3k pixels
      final_width = max(current_width, 1280) |> min(3000)

      if page_info["hasScrollableContent"] do
        Logger.info(
          "[SCREENSHOT] [FULLPAGE] Resizing browser to capture full page: #{final_width}x#{final_height}"
        )

        # Resize the browser window to capture the full page
        session = Wallaby.Browser.resize_window(session, final_width, final_height)

        # Scroll to top to ensure we capture from the beginning
        Wallaby.Browser.execute_script(session, "window.scrollTo(0, 0);")

        # Wait for any dynamic content to load after resize
        :timer.sleep(1500)

        # Also wait for any animations or transitions to complete
        Wallaby.Browser.execute_script(session, """
          // Force any lazy-loaded content to load
          window.dispatchEvent(new Event('scroll'));
          window.dispatchEvent(new Event('resize'));
        """)

        :timer.sleep(500)
      else
        Logger.info("[SCREENSHOT] [FULLPAGE] Page fits in viewport, using standard capture")
      end

      session
    rescue
      error ->
        Logger.warning(
          "[SCREENSHOT] [FULLPAGE] Failed to prepare full-page capture: #{inspect(error)}"
        )

        Logger.warning("[SCREENSHOT] [FULLPAGE] Falling back to standard screenshot")
        session
    end
  end
end
