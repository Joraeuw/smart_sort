defmodule SmartSort.AI_Reactor.Steps.AnalyzeUnsubscribePageStep do
  @moduledoc """
  Reactor step for analyzing unsubscribe pages.

  Takes a URL from the extraction step and analyzes the unsubscribe page to determine
  what actions are needed (form automation, simple success, etc).
  """

  use Reactor.Step

  require Logger

  alias SmartSort.AI.HttpUnsubscribeAgent

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{unsubscribe_url: url, analysis_result: extraction_result} = arguments

    # Validate URL first
    if is_nil(url) or not is_binary(url) or byte_size(url) < 20 do
      Logger.warning("⚠️ [ANALYZE_STEP] Invalid or missing URL: #{inspect(url)}")

      result = %{
        status: :error,
        method: "url_validation",
        error: "No valid unsubscribe URL found",
        url: url,
        requires_automation: false
      }

      {:ok, result}
    else
      Logger.info("[ANALYZE_STEP] Analyzing unsubscribe page: #{url}")
      Logger.info("[ANALYZE_STEP] Extraction confidence: #{extraction_result.confidence_score}")

      case HttpUnsubscribeAgent.execute_http_unsubscribe(url) do
        {:ok, success_message} ->
          Logger.info("[ANALYZE_STEP] Simple unsubscribe successful: #{success_message}")

          result = %{
            status: :success,
            method: "simple_http",
            message: success_message,
            url: url,
            requires_automation: false
          }

          {:ok, result}

        {:requires_analysis, page_data} ->
          Logger.info("[ANALYZE_STEP] Page requires further analysis")

          Logger.info(
            "[ANALYZE_STEP] HTML length: #{String.length(page_data.html_content)} chars"
          )

          # This will be processed by the form automation step
          result = %{
            status: :requires_form,
            method: "form_automation",
            page_data: page_data,
            url: url,
            requires_automation: true,
            extraction_context: %{
              search_text: extraction_result.link_search_text,
              context: extraction_result.link_context,
              confidence: extraction_result.confidence_score
            }
          }

          {:ok, result}

        {:requires_form, form_data} ->
          Logger.info("[ANALYZE_STEP] Page analysis complete - form automation required")
          Logger.info("[ANALYZE_STEP] Found #{length(form_data.steps)} automation steps")

          # Merge the form data with our extraction context and pass through
          result =
            Map.merge(form_data, %{
              status: :requires_form,
              method: "form_automation",
              url: url,
              requires_automation: true,
              extraction_context: %{
                search_text: extraction_result.link_search_text,
                context: extraction_result.link_context,
                confidence: extraction_result.confidence_score
              }
            })

          {:ok, result}

        {:error, reason} ->
          Logger.error("[ANALYZE_STEP] Page analysis failed: #{inspect(reason)}")

          # Don't fail the entire reactor - return error info for handling
          result = %{
            status: :error,
            method: "http_request",
            error: reason,
            url: url,
            requires_automation: false
          }

          {:ok, result}
      end
    end
  end

  @impl Reactor.Step
  def compensate(reason, arguments, _context, _options) do
    %{unsubscribe_url: url} = arguments
    Logger.warning("[ANALYZE_STEP] Compensating page analysis for URL: #{url}")
    Logger.warning("[ANALYZE_STEP] Compensation reason: #{inspect(reason)}")

    :ok
  end
end
