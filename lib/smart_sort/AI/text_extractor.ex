defmodule SmartSort.AI.TextExtractor do
  @moduledoc """
  Fast text-based extraction of unsubscribe information using regex patterns.
  Falls back to AI analysis only when simple extraction fails.
  """

  require Logger
  alias SmartSort.AI.EmailAnalysisAgent

  @doc """
  Extracts unsubscribe information using text patterns first, AI as fallback.
  Returns the same format as EmailAnalysisAgent for consistency.
  """
  def extract_unsubscribe_info(email) do
    Logger.info("[TEXT_EXTRACTOR] Attempting fast text extraction for email: #{email.id}")

    body_content = email.body || email.snippet || ""

    case attempt_text_extraction(body_content, email.to_email) do
      {:ok, result} ->
        Logger.info("[TEXT_EXTRACTOR] Successfully extracted via text patterns")
        log_extraction_result(result)
        {:ok, result}

      {:not_found} ->
        Logger.info("[TEXT_EXTRACTOR] Text extraction failed, falling back to AI analysis")
        EmailAnalysisAgent.analyze_email(email)
    end
  end

  defp attempt_text_extraction(body_content, user_email) do
    # Only try to find URL patterns
    url_result = extract_url_patterns(body_content)

    case url_result do
      nil ->
        {:not_found}

      url ->
        # Build response structure matching EmailAnalysisAgent
        result = %{
          confidence_score: calculate_confidence(nil, url),
          unsubscribe_url: url,
          user_email: user_email,
          link_search_text: extract_search_text(body_content, url),
          link_context: extract_context(body_content, url),
          reasoning: build_reasoning(nil, url)
        }

        {:ok, result}
    end
  end

  defp extract_url_patterns(body_content) do
    # Focus on footer area for unsubscribe links
    footer_section = extract_footer_section(body_content)

    # Look for unsubscribe URLs specifically
    unsubscribe_patterns = [
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?unsubscribe.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*unsubscribe[^"']*)["\'][^>]*>.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>unsubscribe<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*unsubscribe\s*<\/a>/i,
      ~r/<a[^>]*class=["\'][^"']*unsubscribe[^"']*["\'][^>]*href=["\']([^"']*)["\'][^>]*>/i,
      ~r/<a[^>]*id=["\'][^"']*unsubscribe[^"']*["\'][^>]*href=["\']([^"']*)["\'][^>]*>/i,
      ~r/<a[^>]*href=["\']([^"']*opt-?out[^"']*)["\'][^>]*>.*?opt[^<]*out.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?opt[^<]*out.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*opt\s*out\s*<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*opt-out\s*<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*remove[^"']*)["\'][^>]*>.*?remove.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?remove.*?list.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?remove.*?me.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?stop.*?email.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?stop.*?receiving.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?stop.*?notification.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*preference[^"']*)["\'][^>]*>.*?preference.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*manage[^"']*)["\'][^>]*>.*?manage.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*settings[^"']*)["\'][^>]*>.*?setting.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?email.*?preference.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?manage.*?subscription.*?<\/a>/i,
      ~r/<button[^>]*onclick=["\'][^"']*([^"']*unsubscribe[^"']*)["\'][^>]*>.*?unsubscribe.*?<\/button>/i,
      ~r/<input[^>]*type=["\']button["\'][^>]*onclick=["\'][^"']*([^"']*unsubscribe[^"']*)["\'][^>]*>/i,
      ~r/<input[^>]*type=["\']submit["\'][^>]*formaction=["\']([^"']*unsubscribe[^"']*)["\'][^>]*>/i,
      ~r/https?:\/\/[^\/]*\.?klclick\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?mailchimp\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?constantcontact\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?sendgrid\.net\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?aweber\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?getresponse\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?campaignmonitor\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?hubspot\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?mailjet\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?sendinblue\.com\/[^>\s"']*unsubscribe[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?[a-z0-9-]+\.com\/[^>\s"']*[ul]\/[a-zA-Z0-9_-]+/i,
      ~r/https?:\/\/[^\/]*\.?[a-z0-9-]+\.com\/[^>\s"']*unsub[^>\s"']*/i,
      ~r/https?:\/\/[^\/]*\.?[a-z0-9-]+\.com\/[^>\s"']*optout[^>\s"']*/i,
      ~r/https?:\/\/[^\s<>"']*unsubscribe[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*opt-?out[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*remove[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*stop[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*preference[^\s<>"']*/i,
      ~r/https?:\/\/[^\s<>"']*manage[^\s<>"']*/i,
      ~r/https?:\/\/unsubscribe\.[^\s<>"']+/i,
      ~r/https?:\/\/optout\.[^\s<>"']+/i,
      ~r/https?:\/\/preferences\.[^\s<>"']+/i,
      ~r/https?:\/\/manage\.[^\s<>"']+/i,
      ~r/<form[^>]*action=["\']([^"']*unsubscribe[^"']*)["\'][^>]*>/i,
      ~r/<form[^>]*action=["\']([^"']*opt-?out[^"']*)["\'][^>]*>/i,
      ~r/<form[^>]*action=["\']([^"']*remove[^"']*)["\'][^>]*>/i,
      ~r/unsubscribe[^:]*:?\s*<?(?:https?:\/\/)?([^\s<>"']+)/i,
      ~r/opt[^:]*out[^:]*:?\s*<?(?:https?:\/\/)?([^\s<>"']+)/i,
      ~r/remove[^:]*:?\s*<?(?:https?:\/\/)?([^\s<>"']+)/i,
      ~r/stop\s+receiving[^:]*:?\s*<?(?:https?:\/\/)?([^\s<>"']+)/i,
      ~r/email\s+preferences[^:]*:?\s*<?(?:https?:\/\/)?([^\s<>"']+)/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*UNSUBSCRIBE\s*<\/a>/,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*OPT\s*OUT\s*<\/a>/,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*REMOVE\s*<\/a>/,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*un-?subscribe\s*<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*un\s+subscribe\s*<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*\[\s*unsubscribe\s*\]\s*<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>\s*\(\s*unsubscribe\s*\)\s*<\/a>/i,
      ~r/<a[^>]*href=3D["\']([^"']*unsubscribe[^"']*)["\'][^>]*>.*?unsubscribe.*?<\/a>/i,
      ~r/<a[^>]*href=3D["\']([^"']*)["\'][^>]*>.*?unsubscribe.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*(?:unsubscribe|opt-?out|remove|stop|manage|preference)[^"']*)["\'][^>]*>.*?<\/a>/i,
      ~r/<a[^>]*href=["\']([^"']*)["\'][^>]*>.*?(?:unsubscribe|opt-?out|remove.*?(?:list|me)|stop.*?(?:email|receiving)|manage.*?(?:subscription|preference)).*?<\/a>/i,
      ~r/https?:\/\/[^?\s<>"']*\?[^#\s<>"']*(?:unsubscribe|opt-?out|remove|stop)[^#\s<>"']*/i,
      ~r/https?:\/\/[^?\s<>"']*\?[^#\s<>"']*(?:action|cmd|task)=(?:unsubscribe|opt-?out|remove)[^#\s<>"']*/i,
      ~r/https?:\/\/[^#\s<>"']*#(?:unsubscribe|opt-?out|remove|stop)[^\s<>"']*/i
    ]

    found_url =
      Enum.find_value(unsubscribe_patterns, fn pattern ->
        case Regex.run(pattern, footer_section) do
          [_full, url] -> clean_url(url)
          [url] -> clean_url(url)
          _ -> nil
        end
      end)

    if found_url && valid_unsubscribe_url?(found_url) do
      found_url
    else
      nil
    end
  end

  defp extract_footer_section(body_content) do
    String.slice(body_content, -10_000, 10_000)
  end

  defp clean_url(url) do
    url
    |> String.trim()
    |> ensure_protocol()
    |> String.replace(~r/[>)\]}"\s]*$/, "")
    |> String.replace(~r/&amp;/, "&")
  end

  defp ensure_protocol(url) do
    if String.starts_with?(url, ["http://", "https://"]) do
      url
    else
      "https://#{url}"
    end
  end

  defp valid_unsubscribe_url?(url) do
    String.length(url) > 20 and
      String.starts_with?(url, ["http://", "https://"]) and
      not String.contains?(url, ["track_link", "analytics", "pixel", "beacon"]) and
      (String.contains?(String.downcase(url), ["unsubscribe", "opt-out", "optout", "remove"]) or
         String.length(url) > 50)
  end

  defp extract_search_text(body_content, url) when is_binary(url) do
    # Try to find the text that appears before the URL
    case String.split(body_content, url, parts: 2) do
      [before, _after_text] ->
        # Get last 50 characters before the URL
        before_text = String.slice(before, -50, 50) |> String.trim()
        # Look for common unsubscribe text patterns
        if String.contains?(String.downcase(before_text), ["unsubscribe", "opt out", "click here"]) do
          before_text
        else
          "unsubscribe"
        end

      _ ->
        "unsubscribe"
    end
  end

  defp extract_search_text(_body_content, _url), do: nil

  defp extract_context(body_content, url) when is_binary(url) do
    # Extract surrounding context for the URL
    case String.split(body_content, url, parts: 2) do
      [before, after_text] ->
        before_context = String.slice(before, -100, 100)
        after_context = String.slice(after_text, 0, 100)
        "#{before_context}[UNSUBSCRIBE_LINK]#{after_context}"

      _ ->
        nil
    end
  end

  defp extract_context(_body_content, _url), do: nil

  defp calculate_confidence(nil, url) when is_binary(url) do
    # Base confidence on URL quality
    base_confidence = 0.6

    confidence =
      if String.contains?(String.downcase(url), "unsubscribe") do
        base_confidence + 0.3
      else
        base_confidence
      end

    confidence =
      if String.length(url) > 50 do
        confidence + 0.1
      else
        confidence
      end

    min(1.0, confidence)
  end

  defp calculate_confidence(nil, nil), do: 0.0

  defp build_reasoning(nil, url) when is_binary(url) do
    "Found unsubscribe URL via text patterns"
  end

  defp build_reasoning(nil, nil) do
    "No unsubscribe information found in email content"
  end

  defp log_extraction_result(result) do
    Logger.info("[TEXT_EXTRACTOR] Confidence: #{result.confidence_score}")

    if result.unsubscribe_url do
      Logger.info("[TEXT_EXTRACTOR] URL: #{String.slice(result.unsubscribe_url, 0, 100)}...")
    end

    Logger.info("[TEXT_EXTRACTOR] Reasoning: #{result.reasoning}")
  end
end
