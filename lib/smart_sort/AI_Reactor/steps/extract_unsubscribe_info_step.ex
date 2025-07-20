defmodule SmartSort.AI_Reactor.Steps.ExtractUnsubscribeInfoStep do
  @moduledoc """
  Reactor step for extracting unsubscribe information from emails.

  Wraps the existing TextExtractor functionality but in a Reactor-compatible way
  with proper error handling and structured outputs.
  """

  use Reactor.Step

  require Logger

  alias SmartSort.AI.TextExtractor

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{email: email} = arguments

    Logger.info("[EXTRACT_STEP] Extracting unsubscribe info from email: #{email.id}")
    Logger.info("[EXTRACT_STEP] From: #{email.from_name || email.from_email}")
    Logger.info("[EXTRACT_STEP] Subject: #{email.subject}")

    case TextExtractor.extract_unsubscribe_info(email) do
      {:ok, analysis} ->
        Logger.info("[EXTRACT_STEP] Successfully extracted unsubscribe info")
        log_extraction_results(analysis)

        # Return structured result for the reactor
        result = %{
          unsubscribe_url: analysis.unsubscribe_url,
          user_email: analysis.user_email,
          link_search_text: analysis.link_search_text,
          link_context: analysis.link_context,
          confidence_score: analysis.confidence_score,
          reasoning: analysis.reasoning,
          extraction_method: determine_extraction_method(analysis),
          original_email: email
        }

        {:ok, result}

      {:error, reason} ->
        Logger.error("[EXTRACT_STEP] Failed to extract unsubscribe info: #{inspect(reason)}")
        {:error, "Failed to extract unsubscribe information: #{inspect(reason)}"}
    end
  end

  @impl Reactor.Step
  def compensate(_reason, arguments, _context, _options) do
    %{email: email} = arguments

    Logger.warning("[EXTRACT_STEP] Compensating - cleaning up extraction for email: #{email.id}")

    # No cleanup needed for extraction step, but log for audit
    :ok
  end

  # Private helper functions

  defp log_extraction_results(analysis) do
    Logger.info("[EXTRACT_STEP] Confidence: #{analysis.confidence_score}")

    if analysis.unsubscribe_url && String.length(analysis.unsubscribe_url) > 0 do
      Logger.info("[EXTRACT_STEP] URL: #{String.slice(analysis.unsubscribe_url, 0, 100)}...")
    else
      Logger.info("[EXTRACT_STEP] No URL found")
    end

    if analysis.link_search_text && String.length(analysis.link_search_text) > 0 do
      Logger.info("[EXTRACT_STEP] Search text: '#{analysis.link_search_text}'")
    end

    if analysis.reasoning && String.length(analysis.reasoning) > 0 do
      Logger.info("[EXTRACT_STEP] Reasoning: #{analysis.reasoning}")
    end
  end

  defp determine_extraction_method(analysis) do
    cond do
      # Check if this looks like it came from AI analysis (more detailed reasoning)
      analysis.reasoning &&
          String.contains?(analysis.reasoning, ["footer", "clickable", "signature"]) ->
        "ai_analysis"

      # Check if this looks like text pattern extraction (simpler reasoning)
      analysis.reasoning &&
          String.contains?(analysis.reasoning, ["text patterns", "Found unsubscribe URL"]) ->
        "text_patterns"

      # Fallback
      true ->
        "unknown"
    end
  end
end
