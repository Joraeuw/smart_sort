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
  alias SmartSort.AI.UnsubscribePageAnalyzer

  defmodule VisualVerificationResponse do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    Analysis of a full-page screenshot to determine if an unsubscribe process was successful.

    ## Field Descriptions:
    - success: Whether the unsubscribe appears to have been successful based on visual evidence
    - confidence: How confident you are in this assessment (high/medium/low)
    - success_indicators: Specific text or visual elements that indicate success
    - failure_indicators: Specific text or visual elements that indicate failure
    - location_details: Where on the page the key indicators were found
    - form_state: Description of any visible form elements and their states
    - overall_assessment: Brief summary of what the page shows

    Look for success indicators like:
    - "Successfully unsubscribed" or similar messages
    - "You have been removed from our mailing list"
    - "Your preferences have been updated"
    - Green checkmarks or success icons
    - Confirmation pages or thank you messages

    Look for failure indicators like:
    - Error messages, "Failed" or "Try again" text
    - Red error icons or text
    - Forms still needing to be filled out
    - Unchanged form states (wrong radio button selections)
    """

    @primary_key false
    embedded_schema do
      field :success, :boolean
      field :confidence, Ecto.Enum, values: [:high, :medium, :low]
      field :success_indicators, {:array, :string}, default: []
      field :failure_indicators, {:array, :string}, default: []
      field :location_details, :string
      field :form_state, :string
      field :overall_assessment, :string
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> Ecto.Changeset.validate_required([:success, :confidence, :overall_assessment])
      |> Ecto.Changeset.validate_length(:overall_assessment, min: 10, max: 200)
    end
  end

  @impl Reactor.Step
  def run(
        %{automation_result: %{success: true, method: "simple_http"} = automation_result},
        _context,
        _options
      ) do
    Logger.info("✅ [VERIFY_STEP] Automation already successful - skipping verification")
    {:ok, automation_result}
  end

  def run(arguments, _context, _options) do
    %{automation_result: automation_result, original_url: original_url} = arguments

    Logger.info("✅ [VERIFY_STEP] Verifying unsubscribe success")
    Logger.info("🌐 Original URL: #{String.slice(original_url || "unknown", 0, 100)}")
    Logger.info("🤖 Automation success: #{automation_result.success}")

    # Perform visual verification using Instructor
    visual_verification =
      analyze_screenshot_for_success(automation_result.final_screenshot.data, automation_result)

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

  defp analyze_screenshot_for_success(base64_image, automation_result) do
    Logger.info("[VERIFY_STEP] Analyzing screenshot for success indicators using Instructor...")

    content = """
    Analyze this FULL-PAGE screenshot of an unsubscribe page to determine if the unsubscribe was successful.

    This screenshot captures the entire page from top to bottom, so examine all areas carefully.

    Context:
    - Automation reported success: #{automation_result.success}
    - Automation method: #{automation_result.method}

    Please analyze the visual content throughout the entire page and determine:
    1. Does this page show successful unsubscribe completion anywhere?
    2. What specific text or visual elements indicate success or failure?
    3. Are there any confirmation messages, alerts, or status indicators?
    4. If there are form elements visible, what state are they in?

    Look carefully at:
    - Top of page (alerts, banners, notifications)
    - Form areas (radio button states, success messages)
    - Bottom of page (confirmation messages)
    - Any modal dialogs or overlays

    Focus on finding definitive success or failure messages anywhere on the full page.
    """

    messages = [
      %{
        role: "user",
        content: [
          %{type: "text", text: content},
          %{
            type: "image_url",
            image_url: %{url: "data:image/png;base64,#{base64_image}"}
          }
        ]
      }
    ]

    case Instructor.chat_completion(
           model: "gpt-4o-2024-11-20",
           response_model: VisualVerificationResponse,
           messages: messages,
           temperature: 0.1,
           max_tokens: 500
         ) do
      {:ok, analysis} ->
        Logger.info("[VERIFY_STEP] Visual analysis completed successfully")

        Logger.info(
          "[VERIFY_STEP] Success: #{analysis.success}, Confidence: #{analysis.confidence}"
        )

        # Convert Instructor response to our expected format
        convert_instructor_response(analysis, automation_result)

      {:error, reason} ->
        Logger.warning("[VERIFY_STEP] Visual analysis failed: #{inspect(reason)}")

        %{
          verified: false,
          error: "Visual analysis failed: #{inspect(reason)}",
          success: automation_result.success
        }
    end
  end

  defp convert_instructor_response(analysis, automation_result) do
    %{
      verified: true,
      success: analysis.success,
      confidence: analysis.confidence,
      details: analysis.overall_assessment,
      success_indicators: analysis.success_indicators,
      failure_indicators: analysis.failure_indicators,
      location_details: analysis.location_details,
      form_state: analysis.form_state,
      consistent_with_automation: analysis.success == automation_result.success,
      ai_analysis: analysis.overall_assessment
    }
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
      %{verified: true, success: true, details: details} ->
        "#{base_details}. Visual confirmation: #{details}"

      %{verified: true, success: false, details: details} ->
        "#{base_details}. Visual analysis: #{details}"

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
