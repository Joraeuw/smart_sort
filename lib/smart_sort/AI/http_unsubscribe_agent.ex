defmodule SmartSort.AI.HttpUnsubscribeAgent do
  @moduledoc """
  Agent responsible for handling simple HTTP-based unsubscribe requests.
  Takes screenshots and analyzes pages to determine next steps.
  """

  require Logger
  alias SmartSort.AI.FormTools.Screenshot
  alias SmartSort.AI.UnsubscribePageAnalyzer

  @doc """
  Executes a simple HTTP unsubscribe request.
  Takes screenshot and analyzes the response to determine next steps.
  """
  def execute_http_unsubscribe(url, wallaby_session, user_email) do
    Logger.info("[HTTP_AGENT] Starting HTTP unsubscribe for: #{url}")
    headers = get_default_headers()

    case attempt_get_request(url, headers) do
      {:requires_analysis, page_data} ->
        analyze_unsubscribe_page(page_data, wallaby_session, user_email)

      {:error, _reason} ->
        case attempt_post_request(url, headers) do
          {:requires_analysis, page_data} ->
            analyze_unsubscribe_page(page_data, wallaby_session, user_email)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Private functions

  defp attempt_get_request(url, headers) do
    Logger.info("[HTTP_AGENT] Making GET request to: #{url}")

    case HTTPoison.get(url, headers, follow_redirect: true, timeout: 10_000, max_redirect: 15) do
      {:ok, %{status_code: code, body: body, headers: response_headers}} when code in 200..299 ->
        Logger.info("[HTTP_AGENT] GET response: #{code} (#{byte_size(body)} bytes)")

        # Check if response is gzip-compressed and decompress if needed
        decompressed_body = decompress_response_body(body, response_headers)

        Logger.info(
          "[HTTP_AGENT] Decompressed content: #{String.length(decompressed_body)} chars"
        )

        # Take screenshot and analyze the page
        Logger.info("[HTTP_AGENT] Taking screenshot for page analysis...")
        {:requires_analysis, %{url: url, html_content: decompressed_body, method: "GET"}}

      {:ok, %{status_code: code}} ->
        Logger.error("[HTTP_AGENT] GET failed with status: #{code}")
        {:error, "GET request failed with status: #{code}"}

      {:error, reason} ->
        Logger.error("[HTTP_AGENT] GET request failed: #{inspect(reason)}")
        {:error, "GET request failed: #{inspect(reason)}"}
    end
  end

  defp attempt_post_request(url, headers) do
    params = %{
      "unsubscribe" => "true",
      "action" => "unsubscribe",
      "confirm" => "yes"
    }

    Logger.info("[HTTP_AGENT] Making POST request to: #{url}")

    case HTTPoison.post(url, {:form, params}, headers, timeout: 10_000) do
      {:ok, %{status_code: code, body: body, headers: response_headers}} when code in 200..299 ->
        Logger.info("[HTTP_AGENT] POST response: #{code}")

        # Check if response is gzip-compressed and decompress if needed
        decompressed_body = decompress_response_body(body, response_headers)

        # Take screenshot and analyze the page
        Logger.info("[HTTP_AGENT] Taking screenshot for page analysis...")
        {:requires_analysis, %{url: url, html_content: decompressed_body, method: "POST"}}

      {:ok, %{status_code: code}} ->
        Logger.error("[HTTP_AGENT] POST failed with status: #{code}")
        {:error, "POST request failed with status: #{code}"}

      {:error, reason} ->
        Logger.error("[HTTP_AGENT] POST failed: #{inspect(reason)}")
        {:error, "POST request failed: #{inspect(reason)}"}
    end
  end

  defp analyze_unsubscribe_page(
         %{url: url, html_content: html, method: method},
         wallaby_session,
         user_email
       ) do
    Logger.info("[HTTP_AGENT] Analyzing unsubscribe page with screenshot...")

    case Screenshot.take_full_page_screenshot_with_cleanup(
           url,
           wallaby_session,
           fn screenshot_path ->
             case File.read(screenshot_path) do
               {:ok, image_data} ->
                 base64_image = Base.encode64(image_data)

                 Logger.info(
                   "[HTTP_AGENT] Full-page screenshot captured (#{byte_size(image_data)} bytes)"
                 )

                 UnsubscribePageAnalyzer.analyze_page(
                   html,
                   base64_image,
                   url,
                   method,
                   user_email
                 )

               {:error, reason} ->
                 Logger.error("[HTTP_AGENT] Failed to read screenshot: #{reason}")
                 UnsubscribePageAnalyzer.analyze_page(html, nil, url, method, user_email)
             end
           end
         ) do
      {:ok, result, changed_wallaby_session} ->
        case result do
          {:requires_form, form_data} ->
            updated_form_data = Map.put(form_data, :wallaby_session, changed_wallaby_session)
            {:requires_form, updated_form_data}

          {:ok, success_message} ->
            cleanup_session(changed_wallaby_session)
            {:ok, success_message}

          {:error, reason} ->
            cleanup_session(changed_wallaby_session)
            {:error, reason}

          other_result ->
            Logger.warning(
              "[HTTP_AGENT] Unexpected analyzer result format: #{inspect(other_result)}"
            )

            cleanup_session(changed_wallaby_session)
            other_result
        end

      {:error, reason} ->
        Logger.error("[HTTP_AGENT] Screenshot failed: #{reason}")
        fallback_result = UnsubscribePageAnalyzer.analyze_page(html, nil, url, method, user_email)

        case fallback_result do
          {:requires_form, form_data} ->
            updated_form_data = Map.put(form_data, :wallaby_session, wallaby_session)
            {:requires_form, updated_form_data}

          other_result ->
            other_result
        end
    end
  end

  defp cleanup_session(nil), do: :ok

  defp cleanup_session(session) do
    try do
      Logger.info("[HTTP_AGENT] Cleaning up Wallaby session...")
      Wallaby.end_session(session)
      Logger.info("[HTTP_AGENT] Wallaby session cleaned up successfully")
    rescue
      error ->
        Logger.warning("[HTTP_AGENT] Error cleaning up session: #{inspect(error)}")
    catch
      :exit, reason ->
        Logger.warning("[HTTP_AGENT] Exit signal during session cleanup: #{inspect(reason)}")
    end
  end

  defp get_default_headers do
    [
      {"User-Agent", "Mozilla/5.0 (compatible; SmartSort Unsubscribe Bot)"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.5"},
      {"Accept-Encoding", "gzip, deflate"},
      {"Connection", "keep-alive"},
      {"Upgrade-Insecure-Requests", "1"}
    ]
  end

  # Helper function to decompress gzip-encoded responses
  defp decompress_response_body(body, headers) do
    content_encoding =
      headers
      |> Enum.find(fn {name, _value} -> String.downcase(name) == "content-encoding" end)
      |> case do
        {_name, encoding} -> String.downcase(encoding)
        nil -> nil
      end

    case content_encoding do
      "gzip" ->
        Logger.info("[HTTP_AGENT] [DECOMPRESS] Decompressing gzip content...")

        try do
          decompressed = :zlib.gunzip(body)

          Logger.info(
            "[HTTP_AGENT] [DECOMPRESS] Successfully decompressed #{byte_size(body)} -> #{String.length(decompressed)} chars"
          )

          decompressed
        rescue
          error ->
            Logger.warning(
              "[HTTP_AGENT] [DECOMPRESS] Failed to decompress gzip: #{inspect(error)}"
            )

            Logger.warning("[HTTP_AGENT] [DECOMPRESS] Using raw body as fallback")
            body
        end

      "deflate" ->
        Logger.info("[HTTP_AGENT] [DECOMPRESS] Decompressing deflate content...")

        try do
          decompressed = :zlib.uncompress(body)

          Logger.info(
            "[HTTP_AGENT] [DECOMPRESS] Successfully decompressed #{byte_size(body)} -> #{String.length(decompressed)} chars"
          )

          decompressed
        rescue
          error ->
            Logger.warning(
              "[HTTP_AGENT] [DECOMPRESS] Failed to decompress deflate: #{inspect(error)}"
            )

            Logger.warning("[HTTP_AGENT] [DECOMPRESS] Using raw body as fallback")
            body
        end

      _ ->
        # No compression or unknown compression
        if is_binary(body) and String.valid?(body) do
          body
        else
          # Try to convert binary to string if possible
          case :unicode.characters_to_binary(body, :latin1, :utf8) do
            converted when is_binary(converted) -> converted
            _ -> body
          end
        end
    end
  end
end
