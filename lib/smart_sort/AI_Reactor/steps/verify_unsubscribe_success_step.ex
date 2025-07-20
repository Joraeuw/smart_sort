defmodule SmartSort.AI_Reactor.Steps.VerifyUnsubscribeSuccessStep do
  @moduledoc """
  Reactor step for verifying and finalizing unsubscribe success.

  This is the final step that:
  - Takes a screenshot of the final page state
  - Uses AI to analyze the page for success messages
  - Validates the automation result
  - Formats the final response
  - Logs success/failure metrics
  - Provides structured output for the calling system
  """

  use Reactor.Step

  require Logger
  alias SmartSort.AI.FormTools.Screenshot
  alias SmartSort.AI.UnsubscribePageAnalyzer

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{automation_result: automation_result, original_url: original_url} = arguments

    Logger.info("✅ [VERIFY_STEP] Verifying unsubscribe success")
    Logger.info("🌐 Original URL: #{String.slice(original_url || "unknown", 0, 100)}")
    Logger.info("🤖 Automation success: #{automation_result.success}")

    # Perform visual verification by taking a screenshot and analyzing it
    visual_verification = perform_visual_verification(original_url, automation_result)

    # Build final result structure combining automation and visual verification
    final_result = build_final_result(automation_result, original_url, visual_verification)

    # Log metrics for monitoring
    log_completion_metrics(final_result)

    # Log final status
    if final_result.success do
      Logger.info("🎉 [VERIFY_STEP] Unsubscribe process completed successfully!")
      Logger.info("📊 Method: #{final_result.method}")
      Logger.info("📝 Details: #{final_result.details}")

      if final_result[:visual_confirmation] do
        Logger.info("👁️ Visual confirmation: #{final_result.visual_confirmation}")
      end
    else
      Logger.warning("⚠️ [VERIFY_STEP] Unsubscribe process completed with issues")
      Logger.warning("📊 Method: #{final_result.method}")
      Logger.warning("📝 Details: #{final_result.details}")

      if final_result[:visual_details] do
        Logger.warning("👁️ Visual analysis: #{final_result.visual_details}")
      end
    end

    {:ok, final_result}
  end

  @impl Reactor.Step
  def compensate(_reason, arguments, _context, _options) do
    %{original_url: original_url} = arguments
    Logger.warning("🔄 [VERIFY_STEP] Compensating verification step")
    Logger.warning("🌐 URL: #{String.slice(original_url || "unknown", 0, 100)}")

    # Log compensation for audit trail
    log_compensation_event(original_url)

    :ok
  end

  # Private helper functions

  defp perform_visual_verification(original_url, automation_result) do
    Logger.info("👁️ [VERIFY_STEP] Performing visual verification...")

    # Only try visual verification if we have a URL and automation was attempted
    if is_binary(original_url) and String.length(original_url) > 20 do
      case Screenshot.take_full_page_screenshot_with_cleanup(original_url, fn screenshot_path ->
             case File.read(screenshot_path) do
               {:ok, image_data} ->
                 base64_image = Base.encode64(image_data)

                 Logger.info(
                   "[VERIFY_STEP] Full-page screenshot captured (#{byte_size(image_data)} bytes)"
                 )

                 # Use AI to analyze the screenshot for success indicators
                 analyze_screenshot_for_success(base64_image, original_url, automation_result)

               {:error, reason} ->
                 Logger.warning("[VERIFY_STEP] Failed to read screenshot: #{reason}")
                 %{verified: false, error: "Screenshot read failed"}
             end
           end) do
        {:ok, result} ->
          Logger.info("[VERIFY_STEP] Visual verification completed")
          result

        {:error, reason} ->
          Logger.warning("[VERIFY_STEP] Visual verification failed: #{inspect(reason)}")
          %{verified: false, error: "Screenshot capture failed: #{inspect(reason)}"}
      end
    else
      Logger.info("[VERIFY_STEP] Skipping visual verification - no valid URL")
      %{verified: false, skipped: true, reason: "No valid URL for verification"}
    end
  end

  defp analyze_screenshot_for_success(base64_image, url, automation_result) do
    Logger.info("[VERIFY_STEP] Analyzing screenshot for success indicators...")

    # Use a simplified prompt focused on success detection
    messages = [
      %{
        role: "system",
        content: """
        You are analyzing a FULL-PAGE screenshot to determine if an unsubscribe process was successful.

        This screenshot captures the entire page from top to bottom, so examine the whole image carefully.

        Look for clear indicators of success such as:
        - "Successfully unsubscribed" or similar messages
        - "You have been removed from our mailing list"
        - "Your preferences have been updated"
        - "Email notifications disabled"
        - "Settings saved" or "Changes applied"
        - Green checkmarks or success icons
        - Confirmation text indicating the action was completed
        - Thank you messages or confirmation pages

        Also look for failure indicators:
        - Error messages anywhere on the page
        - "Failed" or "Try again" messages
        - Red error icons or text
        - Forms that still need to be filled out
        - Unchanged form states (radio buttons still in wrong position)

        Since this is a full-page screenshot, success/failure messages might appear:
        - At the top of the page (alerts/banners)
        - Near the form elements that were interacted with
        - At the bottom of the page
        - In modal dialogs or popup notifications

        Return a simple assessment of whether the unsubscribe appears successful based on what you can see throughout the entire page.
        """
      },
      %{
        role: "user",
        content: [
          %{
            type: "text",
            text: """
            Analyze this FULL-PAGE screenshot of an unsubscribe page to determine if the unsubscribe was successful.

            This screenshot captures the entire page from top to bottom, so examine all areas carefully.

            Context:
            - URL: #{String.slice(url, 0, 100)}...
            - Automation reported success: #{automation_result.success}
            - Automation method: #{automation_result.method}

            Please analyze the visual content throughout the entire page and tell me:
            1. Does this page show successful unsubscribe completion anywhere on the page?
            2. What specific text or visual elements indicate success or failure (and where are they located)?
            3. Are there any confirmation messages, alerts, or status indicators?
            4. If there are form elements visible, what state are they in?
            5. Is this consistent with the automation result?

            Look carefully at:
            - Top of page (alerts, banners, notifications)
            - Form areas (radio button states, success messages)
            - Bottom of page (confirmation messages)
            - Any modal dialogs or overlays

            Focus on finding definitive success or failure messages anywhere on the full page.
            """
          },
          %{
            type: "image_url",
            image_url: %{url: "data:image/png;base64,#{base64_image}"}
          }
        ]
      }
    ]

    case make_ai_request(messages) do
      {:ok, analysis} ->
        Logger.info("[VERIFY_STEP] AI visual analysis: #{String.slice(analysis, 0, 200)}...")
        parse_success_analysis(analysis, automation_result)

      {:error, reason} ->
        Logger.warning("[VERIFY_STEP] AI analysis failed: #{inspect(reason)}")
        %{verified: false, error: "AI analysis failed"}
    end
  end

  defp make_ai_request(messages) do
    try do
      case HTTPoison.post(
             "https://api.openai.com/v1/chat/completions",
             Jason.encode!(%{
               model: "gpt-4o-2024-11-20",
               messages: messages,
               max_tokens: 300,
               temperature: 0.1
             }),
             [
               {"Authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"},
               {"Content-Type", "application/json"}
             ],
             timeout: 30_000
           ) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
              {:ok, content}

            {:ok, response} ->
              {:error, "Unexpected response format: #{inspect(response)}"}

            {:error, reason} ->
              {:error, "JSON decode failed: #{reason}"}
          end

        {:ok, %{status_code: status}} ->
          {:error, "API request failed with status: #{status}"}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Request exception: #{inspect(error)}"}
    end
  end

  defp parse_success_analysis(analysis_text, automation_result) do
    # Look for success indicators in the AI response
    analysis_lower = String.downcase(analysis_text)

    success_indicators = [
      "successfully unsubscribed",
      "successfully removed",
      "unsubscribe successful",
      "preferences updated",
      "notifications disabled",
      "removed from list",
      "opt out successful",
      "successfully opted out"
    ]

    failure_indicators = [
      "failed",
      "error",
      "try again",
      "not successful",
      "still subscribed",
      "form needs",
      "please complete"
    ]

    has_success =
      Enum.any?(success_indicators, fn indicator ->
        String.contains?(analysis_lower, indicator)
      end)

    has_failure =
      Enum.any?(failure_indicators, fn indicator ->
        String.contains?(analysis_lower, indicator)
      end)

    cond do
      has_success ->
        %{
          verified: true,
          success: true,
          confidence: :high,
          details: "Visual confirmation of successful unsubscribe",
          ai_analysis: String.slice(analysis_text, 0, 200),
          consistent_with_automation: automation_result.success
        }

      has_failure ->
        %{
          verified: true,
          success: false,
          confidence: :high,
          details: "Visual indication of unsubscribe failure",
          ai_analysis: String.slice(analysis_text, 0, 200),
          consistent_with_automation: !automation_result.success
        }

      true ->
        %{
          verified: true,
          success: automation_result.success,
          confidence: :low,
          details: "No clear success/failure indicators found - relying on automation result",
          ai_analysis: String.slice(analysis_text, 0, 200),
          consistent_with_automation: true
        }
    end
  end

  defp build_final_result(automation_result, original_url, visual_verification) do
    # Determine final success status based on both automation and visual verification
    final_success = determine_final_success(automation_result, visual_verification)

    # Build enhanced details including visual verification info
    enhanced_details = build_enhanced_details(automation_result, visual_verification)

    base_result = %{
      success: final_success,
      method: automation_result.method,
      details: enhanced_details,
      original_url: original_url,
      completed_at: DateTime.utc_now(),
      reactor_version: "1.0.0",
      visual_verification: visual_verification
    }

    # Add additional context based on automation type and visual verification
    enhanced_result =
      case automation_result do
        %{automation_type: "form_interaction", timestamp: timestamp} ->
          Map.merge(base_result, %{
            automation_type: "form_interaction",
            automation_duration: calculate_duration(timestamp),
            session_ref: automation_result[:session_ref]
          })

        %{error: error} ->
          Map.merge(base_result, %{
            error_details: inspect(error),
            failure_reason: categorize_failure(automation_result)
          })

        _ ->
          base_result
      end

    # Add visual verification fields for easy access in logging
    case visual_verification do
      %{verified: true, success: true, details: details} ->
        Map.merge(enhanced_result, %{
          visual_confirmation: details,
          verification_confidence: visual_verification[:confidence] || :unknown
        })

      %{verified: true, success: false, details: details} ->
        Map.merge(enhanced_result, %{
          visual_details: details,
          verification_confidence: visual_verification[:confidence] || :unknown
        })

      %{error: error} ->
        Map.merge(enhanced_result, %{
          visual_details: "Visual verification failed: #{error}"
        })

      _ ->
        enhanced_result
    end
  end

  defp determine_final_success(automation_result, visual_verification) do
    case visual_verification do
      %{verified: true, success: true, confidence: :high} ->
        # High confidence visual confirmation overrides automation result
        Logger.info("[VERIFY_STEP] High confidence visual success - overriding automation result")

        true

      %{verified: true, success: false, confidence: :high} ->
        # High confidence visual failure overrides automation result
        Logger.warning(
          "[VERIFY_STEP] High confidence visual failure - overriding automation result"
        )

        false

      %{verified: true, consistent_with_automation: true} ->
        # Visual verification agrees with automation
        Logger.info("[VERIFY_STEP] Visual verification consistent with automation")
        automation_result.success

      %{verified: true, consistent_with_automation: false} ->
        # Conflicting results - log warning but default to automation
        Logger.warning(
          "🤔 [VERIFY_STEP] Visual verification conflicts with automation - keeping automation result"
        )

        automation_result.success

      %{verified: false} ->
        # Visual verification failed - rely on automation
        Logger.info("📋 [VERIFY_STEP] Visual verification unavailable - using automation result")
        automation_result.success

      _ ->
        # Fallback to automation result
        automation_result.success
    end
  end

  defp build_enhanced_details(automation_result, visual_verification) do
    base_details = automation_result.details || "Automation completed"

    case visual_verification do
      %{verified: true, success: true, details: visual_details} ->
        "#{base_details}. Visual confirmation: #{visual_details}"

      %{verified: true, success: false, details: visual_details} ->
        "#{base_details}. Visual analysis: #{visual_details}"

      %{verified: true, confidence: :low} ->
        "#{base_details}. Visual verification inconclusive"

      %{error: error} ->
        "#{base_details}. Visual verification failed: #{error}"

      %{skipped: true} ->
        "#{base_details}. Visual verification skipped"

      _ ->
        base_details
    end
  end

  defp calculate_duration(start_timestamp) when is_struct(start_timestamp, DateTime) do
    DateTime.diff(DateTime.utc_now(), start_timestamp, :millisecond)
  end

  defp calculate_duration(_), do: nil

  defp categorize_failure(automation_result) do
    cond do
      String.contains?(automation_result.details || "", ["timeout", "Timeout"]) ->
        "timeout"

      String.contains?(automation_result.details || "", ["element not found", "not found"]) ->
        "element_not_found"

      String.contains?(automation_result.details || "", ["network", "connection"]) ->
        "network_error"

      String.contains?(automation_result.details || "", ["invalid", "Invalid"]) ->
        "invalid_data"

      automation_result[:error] ->
        "automation_error"

      true ->
        "unknown"
    end
  end

  defp log_completion_metrics(final_result) do
    # Log structured metrics for monitoring/alerting
    Logger.info("📊 [METRICS] Unsubscribe completion", %{
      success: final_result.success,
      method: final_result.method,
      automation_type: final_result[:automation_type],
      duration_ms: final_result[:automation_duration],
      failure_reason: final_result[:failure_reason],
      completed_at: final_result.completed_at,
      url_hash: hash_url(final_result.original_url)
    })
  end

  defp log_compensation_event(original_url) do
    Logger.warning("📊 [METRICS] Reactor compensation triggered", %{
      step: "verify_unsubscribe_success",
      url_hash: hash_url(original_url),
      compensated_at: DateTime.utc_now()
    })
  end

  defp hash_url(nil), do: nil

  defp hash_url(url) when is_binary(url) do
    # Create a hash of the URL for privacy-safe logging
    :crypto.hash(:sha256, url) |> Base.encode16() |> String.slice(0, 8)
  end
end
