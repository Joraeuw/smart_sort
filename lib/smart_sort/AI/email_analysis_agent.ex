defmodule SmartSort.AI.EmailAnalysisAgent do
  @moduledoc """
  Agent responsible for analyzing emails to detect unsubscribe methods.
  Extracts unsubscribe links and determines the best approach for URL-based unsubscribing.
  """

  require Logger

  defmodule UnsubscribeResponse do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    ## Field Descriptions:
    - confidence_score: Your confidence in finding valid unsubscribe information (0.0 to 1.0)
    - unsubscribe_url: Direct URL for unsubscribing (if found)
    - user_email: The email address that should be unsubscribed
    - link_search_text: A unique text snippet that appears near the unsubscribe link (for position finding)
    - link_context: Surrounding text context where the unsubscribe link appears
    - reasoning: Brief explanation of what unsubscribe information was found
    """

    @primary_key false
    embedded_schema do
      field :confidence_score, :float
      field :unsubscribe_url, :string
      field :user_email, :string
      field :link_search_text, :string
      field :link_context, :string
      field :reasoning, :string
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> Ecto.Changeset.validate_number(:confidence_score,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
    end
  end

  @doc """
  Analyzes an email to determine the best unsubscribe method.
  Returns analysis with method type, URLs, and confidence score.
  """
  def analyze_email(email) do
    Logger.info("[EMAIL_ANALYSIS] Analyzing email: #{email.id}")

    Logger.info(
      "[EMAIL_ANALYSIS] Email body length: #{String.length(email.body || email.snippet || "")} characters"
    )

    with {:ok, response} <- perform_analysis(email) do
      Logger.info(
        "[EMAIL_ANALYSIS] Extraction complete - found #{count_extracted_info(response)} unsubscribe option(s)"
      )

      log_analysis_details(response)
      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("[EMAIL_ANALYSIS] Failed to analyze email: #{inspect(reason)}")
        error
    end
  end

  # Count how many unsubscribe options were found
  defp count_extracted_info(response) do
    count = 0

    count =
      if response.unsubscribe_url && String.length(response.unsubscribe_url) > 0 do
        count + 1
      else
        count
      end

    count
  end

  defp perform_analysis(email) do
    headers = extract_headers(email)
    body_content = email.body || email.snippet || ""

    with {:ok, response} <-
           Instructor.chat_completion(
             model: "gpt-4o-mini",
             response_model: UnsubscribeResponse,
             max_retries: 3,
             messages: [
               %{
                 role: "system",
                 content: """
                 You are an expert at extracting unsubscribe information from emails.

                 Your job is to FIND and LOCATE unsubscribe URLs in email footers/signatures, NOT to decide which method to use.

                 CRITICAL RULES:
                 1. ONLY look for unsubscribe information in EMAIL FOOTERS/SIGNATURES - ignore all content links in the main body
                 2. Look for text patterns like: "unsubscribe", "opt out", "stop receiving", "manage preferences", "email preferences"
                 3. Unsubscribe links are typically near sender information, privacy policies, or legal text
                 4. IGNORE content links, article links, social media links, or any links in the main message content
                 5. DO NOT extract actual URLs - just provide location information
                 6. Potential wrong links could be: "track", "track_link", "click", "analytics", "pixel", "beacon", "icons", "images", "logo"

                 EXTRACT WHAT YOU FIND:
                 - If you find clickable unsubscribe links, provide location information (link_search_text and link_context)
                 - Focus only on URL-based unsubscribe methods

                 For URL-based unsubscribe:
                 - "link_search_text": Unique 10-20 word snippet immediately before/after the unsubscribe link
                 - "link_context": 50-100 words of footer/signature text surrounding the unsubscribe link
                 """
               },
               %{
                 role: "user",
                 content: """
                 Extract all available unsubscribe information from this email footer/signature:

                 EMAIL INFO:
                 #{headers}

                 EMAIL BODY:
                 #{body_content}

                 User's email: #{email.to_email}

                 EXTRACTION INSTRUCTIONS:
                 1. IGNORE all content in the main email body (articles, posts, discussions, etc.)

                 2. FOCUS ONLY on the email footer/signature section which typically contains:
                    - Sender company information and address
                    - "You received this email because..." explanations
                    - Legal/privacy text
                    - Actual unsubscribe links or instructions

                 3. EXTRACT ALL unsubscribe information you find in the footer:
                    - Clickable text that says "unsubscribe"
                    - Clickable text that says "unfollow [topic/service]"
                    - Clickable text that says "opt out" or "stop receiving"
                    - Clickable text that says "manage email preferences"

                 4. AVOID these common false positives:
                    - Links containing "track", "click", "analytics", "pixel", "beacon"
                    - Image tracking pixels or analytics URLs
                    - Generic footer links (privacy policy, terms, contact)
                    - Social media icons or links
                    - Company logo links

                 5. For CLICKABLE unsubscribe elements:
                    - Provide "link_search_text": Find the exact clickable text (like "unsubscribe", "unfollow Movie Chat", "click here")
                    - Provide "link_context": Include 50-100 words of surrounding footer text
                    - Examples of good clickable text:
                      * "unsubscribe" (from "If you don't want these emails, you can [unsubscribe]")
                      * "click here" (from "To stop receiving these notifications, [click here]")
                      * "Manage your email preferences" (if this text is clickable)
                      * "unfollow Movie Chat" (like in Quora emails)

                 7. Leave unsubscribe_url empty - the system will extract it from your location info

                 Focus on finding legitimate unsubscribe URLs in the email footer!
                 """
               }
             ]
           ) do
      # Validate and potentially fix the URL
      fixed_response = validate_and_fix_url(response, body_content)
      {:ok, fixed_response}
    end
  end

  defp validate_and_fix_url(response, body_content) do
    # If we have location information but no URL, extract it
    search_text = response.link_search_text || ""
    context = response.link_context || ""
    ai_url = response.unsubscribe_url

    # Only extract URL if we have location information but no URL yet
    if (String.length(search_text) > 5 or String.length(context) > 10) and
         (is_nil(ai_url) or String.length(ai_url || "") == 0) do
      Logger.info("[EMAIL_ANALYSIS] Using position-based URL extraction")
      Logger.info("[EMAIL_ANALYSIS] Search text: '#{search_text}'")
      Logger.info("[EMAIL_ANALYSIS] Context: '#{String.slice(context, 0, 100)}...'")

      extracted_url = extract_url_from_email(body_content, search_text, context, ai_url)

      # Also fix the context to be more accurate
      fixed_context =
        if String.length(search_text) > 5 do
          extract_actual_context_around_text(body_content, search_text)
        else
          context
        end

      Logger.info("[EMAIL_ANALYSIS] Fixed context: '#{String.slice(fixed_context, 0, 150)}...'")

      %{response | unsubscribe_url: extracted_url, link_context: fixed_context}
    else
      response
    end
  end

  # Extract the actual surrounding context for the search text
  defp extract_actual_context_around_text(body_content, search_text) do
    case String.split(body_content, search_text, parts: 2) do
      [before_text, after_text] ->
        # Get context before and after the search text
        before_context = String.slice(before_text, -300, 300) |> String.trim()
        after_context = String.slice(after_text, 0, 300) |> String.trim()

        # Combine into meaningful context
        "#{before_context} [#{search_text}] #{after_context}"
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      _ ->
        # Fallback: try to find the text in a different way
        search_words = String.split(search_text) |> Enum.take(3) |> Enum.join(" ")

        case String.split(body_content, search_words, parts: 2) do
          [before_text, after_text] ->
            before_context = String.slice(before_text, -200, 200) |> String.trim()
            after_context = String.slice(after_text, 0, 200) |> String.trim()
            "#{before_context} [#{search_words}] #{after_context}"

          _ ->
            "Context could not be extracted for: #{search_text}"
        end
    end
  end

  defp extract_url_from_email(body_content, search_text, context, fallback_url) do
    cond do
      # Use search text to find position and extract URL
      String.length(search_text) > 5 ->
        case extract_url_by_position(body_content, search_text) do
          {:ok, url} -> url
          :not_found -> extract_url_from_context_or_fallback(body_content, context, fallback_url)
        end

      # Use context to find and extract URL
      String.length(context) > 10 ->
        extract_url_from_context_or_fallback(body_content, context, fallback_url)

      # Use AI URL or try to find any unsubscribe URL
      true ->
        fallback_url || extract_any_unsubscribe_url(body_content)
    end
  end

  defp extract_url_by_position(body_content, search_text) do
    Logger.info("[EMAIL_ANALYSIS] [URL_EXTRACT] Searching for URL near: '#{search_text}'")

    case String.split(body_content, search_text, parts: 2) do
      [before_text, after_text] ->
        Logger.info("[EMAIL_ANALYSIS] [URL_EXTRACT] Found search text, looking around it...")

        # Look in a larger section BEFORE the search text (for href attributes)
        before_section = String.slice(before_text, -2000, 2000)
        # Look in a section AFTER the search text
        after_section = String.slice(after_text, 0, 1000)

        # Try HTML link extraction first (most common case)
        case extract_html_link_around_text(body_content, search_text) do
          {:ok, url} ->
            Logger.info(
              "[EMAIL_ANALYSIS] [URL_EXTRACT] Found URL in HTML link: #{String.slice(url, 0, 100)}"
            )

            {:ok, url}

          :not_found ->
            # Try looking for URLs in the sections around the search text
            case extract_url_from_section(before_section) do
              {:ok, url} ->
                Logger.info(
                  "[EMAIL_ANALYSIS] [URL_EXTRACT] Found URL before search text: #{String.slice(url, 0, 100)}"
                )

                {:ok, url}

              :not_found ->
                case extract_url_from_section(after_section) do
                  {:ok, url} ->
                    Logger.info(
                      "[EMAIL_ANALYSIS] [URL_EXTRACT] Found URL after search text: #{String.slice(url, 0, 100)}"
                    )

                    {:ok, url}

                  :not_found ->
                    Logger.warning("[EMAIL_ANALYSIS] [URL_EXTRACT] No URL found near search text")
                    :not_found
                end
            end
        end

      _ ->
        # Try searching with partial text if exact match fails
        search_words = String.split(search_text) |> Enum.take(3)
        partial_search = Enum.join(search_words, " ")

        Logger.info(
          "[EMAIL_ANALYSIS] [URL_EXTRACT] Exact match failed, trying partial: '#{partial_search}'"
        )

        case String.split(body_content, partial_search, parts: 2) do
          [before_text, after_text] ->
            before_section = String.slice(before_text, -1500, 1500)
            after_section = String.slice(after_text, 0, 1000)

            case extract_url_from_section(before_section) do
              {:ok, url} -> {:ok, url}
              :not_found -> extract_url_from_section(after_section)
            end

          _ ->
            Logger.warning("[EMAIL_ANALYSIS] [URL_EXTRACT] Partial search also failed")
            :not_found
        end
    end
  end

  defp extract_html_link_around_text(body_content, search_text) do
    html_link_patterns = [
      ~r/<a[^>]*href=["\']([^"']+)["\'][^>]*>.*?#{Regex.escape(search_text)}.*?<\/a>/is,
      ~r/<a[^>]*href=["\']([^"']+)["\'][^>]*>[^<]*#{Regex.escape(search_text)}[^<]*<\/a>/is,
      ~r/href=["\']([^"']*unsubscribe[^"']*)["\'][^>]*>.*?#{Regex.escape(search_text)}/is
    ]

    found_url =
      Enum.find_value(html_link_patterns, fn pattern ->
        case Regex.run(pattern, body_content) do
          [_full_match, url] ->
            cleaned = clean_extracted_url(url)

            if valid_unsubscribe_url?(cleaned) do
              cleaned
            else
              nil
            end

          _ ->
            nil
        end
      end)

    if found_url do
      {:ok, found_url}
    else
      :not_found
    end
  end

  defp extract_url_from_context_or_fallback(body_content, context, fallback_url) do
    case extract_url_from_context(body_content, context) do
      {:ok, url} -> url
      :not_found -> fallback_url || extract_any_unsubscribe_url(body_content)
    end
  end

  defp extract_url_from_context(body_content, context) do
    # Find the context in the email body
    context_words = String.split(context) |> Enum.take(10)
    search_phrase = Enum.join(context_words, " ")

    case String.split(body_content, search_phrase, parts: 2) do
      [_before, after_text] ->
        # Look for URL in the context area (before and after)
        context_section = String.slice(after_text, 0, 500)
        extract_url_from_section(context_section)

      _ ->
        :not_found
    end
  end

  defp extract_url_from_section(section_text) do
    url_patterns = [
      ~r/https?:\/\/[^\s<>"\'\])}]+/i,
      ~r/https?:\/\/[^<>\s"'\]\)]+/i,
      ~r/https?:\/\/[^<>\s"'\n\r]+/i
    ]

    all_urls =
      Enum.flat_map(url_patterns, fn pattern ->
        Regex.scan(pattern, section_text) |> Enum.map(&List.first/1)
      end)

    cleaned_urls =
      all_urls
      |> Enum.uniq()
      |> Enum.map(&clean_extracted_url/1)
      |> Enum.filter(&valid_unsubscribe_url?/1)

    case cleaned_urls do
      [] -> :not_found
      urls -> {:ok, Enum.max_by(urls, &String.length/1)}
    end
  end

  defp extract_any_unsubscribe_url(body_content) do
    # Last resort - find any URL that looks like an unsubscribe link
    unsubscribe_patterns = [
      ~r/https?:\/\/[^\s<>"']*unsubscribe[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*optout[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*opt-out[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*remove[^\s<>"']*/i
    ]

    found_url =
      Enum.find_value(unsubscribe_patterns, fn pattern ->
        case Regex.run(pattern, body_content) do
          [url] -> clean_extracted_url(url)
          _ -> nil
        end
      end)

    found_url || ""
  end

  defp clean_extracted_url(url) do
    url
    |> String.replace(~r/[>)\]}"\s]*$/, "")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/&quot;/, "\"")
    |> String.trim()
    |> resolve_redirect_url()
  end

  # Helper to resolve redirect URLs to final destination
  defp resolve_redirect_url(url) do
    # For tracking URLs, try to follow them to get the final destination
    if String.contains?(url, ["track_click", "redirect", "link.?"]) do
      case follow_redirect_chain(url) do
        {:ok, final_url} -> final_url
        # Fallback to original URL
        _ -> url
      end
    else
      url
    end
  end

  defp follow_redirect_chain(url) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (compatible; SmartSort Unsubscribe Bot)"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"}
    ]

    try do
      case HTTPoison.head(url, headers, follow_redirect: false, timeout: 5_000) do
        {:ok, %{status_code: code, headers: response_headers}} when code in 300..399 ->
          case Enum.find(response_headers, fn {name, _} -> String.downcase(name) == "location" end) do
            {_name, redirect_url} ->
              Logger.info(
                "[EMAIL_ANALYSIS] Following redirect: #{String.slice(redirect_url, 0, 100)}..."
              )

              {:ok, redirect_url}

            nil ->
              {:error, "No redirect location found"}
          end

        {:ok, %{status_code: 200}} ->
          # Not a redirect, return original URL
          {:ok, url}

        _ ->
          {:error, "Could not resolve redirect"}
      end
    rescue
      _ -> {:error, "HTTP request failed"}
    end
  end

  defp valid_unsubscribe_url?(url) do
    String.length(url) > 20 &&
      String.starts_with?(url, ["http://", "https://"]) &&
      (String.contains?(url, ["unsubscribe", "optout", "opt-out", "remove"]) ||
         String.length(url) > 50)
  end

  defp extract_headers(email) do
    [
      "From: #{email.from_name || "Unknown"} <#{email.from_email}>",
      "To: #{email.to_email || "Unknown"}",
      "Subject: #{email.subject || "(No subject)"}",
      "Date: #{email.received_at}",
      "Gmail ID: #{email.gmail_id}"
    ]
    |> Enum.join("\n")
  end

  defp log_analysis_details(response) do
    # Log URL information if found
    if response.unsubscribe_url && String.length(response.unsubscribe_url) > 0 do
      Logger.info("[EMAIL_ANALYSIS] Unsubscribe URL: #{response.unsubscribe_url}")
    end

    # Log if no unsubscribe information was found
    if is_nil(response.unsubscribe_url) or String.length(response.unsubscribe_url || "") == 0 do
      Logger.info("[EMAIL_ANALYSIS] No unsubscribe information found")
    end

    if response.link_search_text && String.length(response.link_search_text) > 0 do
      Logger.info("[EMAIL_ANALYSIS] Search text: '#{response.link_search_text}'")
    end

    if response.link_context && String.length(response.link_context) > 0 do
      Logger.info(
        "[EMAIL_ANALYSIS] Link context (#{String.length(response.link_context)} chars):"
      )

      Logger.info("[EMAIL_ANALYSIS] '#{String.slice(response.link_context, 0, 200)}...'")
    end

    Logger.info("[EMAIL_ANALYSIS] AI reasoning: #{response.reasoning}")
  end
end
