defmodule SmartSort.AI_Reactor.Steps.ExecuteFormAutomationStep do
  @moduledoc """
  Reactor step for executing form automation on unsubscribe pages.

  Handles complex unsubscribe forms that require interaction like:
  - Radio button selection (Off, Disable, Unsubscribe options)
  - Form submission
  - Page navigation
  - Browser session management
  """

  use Reactor.Step

  require Logger

  alias SmartSort.AI.FormAutomationAgent

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{form_data: page_analysis, user_email: user_email} = arguments

    # Data should now come as a proper map from AnalyzeUnsubscribePageStep
    normalized_analysis =
      case page_analysis do
        %{status: _} = data ->
          data

        data when is_map(data) ->
          Map.put_new(data, :status, :requires_form)

        _ ->
          %{status: :error, error: "Invalid page analysis format: #{inspect(page_analysis)}"}
      end

    # Check if automation is actually needed
    case normalized_analysis.status do
      :success ->
        Logger.info("[AUTOMATION_STEP] Page analysis already successful, no automation needed")

        automation_result = %{
          success: true,
          method: normalized_analysis[:method] || "simple_http",
          details:
            normalized_analysis[:message] || normalized_analysis[:details] ||
              "Simple unsubscribe completed",
          automation_type: "simple_http",
          timestamp: DateTime.utc_now()
        }

        {:ok, automation_result}

      :error ->
        Logger.warning("[AUTOMATION_STEP] Page analysis failed, cannot proceed with automation")

        automation_result = %{
          success: false,
          method: "page_analysis_failed",
          details: "Page analysis failed: #{normalized_analysis[:error]}",
          error: normalized_analysis[:error],
          automation_type: "failed_analysis",
          timestamp: DateTime.utc_now()
        }

        {:ok, automation_result}

      :requires_form ->
        Logger.info("[AUTOMATION_STEP] Starting form automation")

        url =
          normalized_analysis[:url] ||
            (normalized_analysis[:page_data] && normalized_analysis[:page_data][:url]) ||
            "unknown"

        Logger.info("[AUTOMATION_STEP] URL: #{url}")
        Logger.info("[AUTOMATION_STEP] User: #{user_email}")

        perform_form_automation(normalized_analysis, user_email)

      _ ->
        Logger.warning(
          "[AUTOMATION_STEP] Unknown page analysis status: #{normalized_analysis.status}"
        )

        automation_result = %{
          success: false,
          method: "unknown_status",
          details: "Unknown page analysis status: #{normalized_analysis.status}",
          automation_type: "unknown",
          timestamp: DateTime.utc_now()
        }

        {:ok, automation_result}
    end
  end

  defp perform_form_automation(normalized_analysis, _user_email) do
    # Track browser session for cleanup
    session_ref = make_ref()

    try do
      # Convert page analysis to the expected format for FormAutomationAgent
      analysis_data = prepare_form_analysis(normalized_analysis)

      Logger.info(
        "[AUTOMATION_STEP] Prepared analysis data with #{length(analysis_data.steps || [])} steps"
      )

      case FormAutomationAgent.execute_form_automation(analysis_data) do
        {:ok, %{success: true} = result} ->
          Logger.info("[AUTOMATION_STEP] Form automation successful!")
          Logger.info("[AUTOMATION_STEP] Method: #{result.method}")
          Logger.info("[AUTOMATION_STEP] Details: #{result.details}")

          automation_result = %{
            success: true,
            method: result.method,
            details: result.details,
            session_ref: session_ref,
            automation_type: "form_interaction",
            timestamp: DateTime.utc_now()
          }

          {:ok, automation_result}

        {:ok, %{success: false} = result} ->
          Logger.warning("[AUTOMATION_STEP] Form automation completed but failed")
          Logger.warning("[AUTOMATION_STEP] Method: #{result.method}")
          Logger.warning("[AUTOMATION_STEP] Details: #{result.details}")

          automation_result = %{
            success: false,
            method: result.method,
            details: result.details,
            session_ref: session_ref,
            automation_type: "form_interaction",
            timestamp: DateTime.utc_now()
          }

          {:ok, automation_result}

        {:error, reason} ->
          Logger.error("[AUTOMATION_STEP] Form automation failed: #{inspect(reason)}")

          automation_result = %{
            success: false,
            method: "form_automation",
            details: "Automation failed: #{inspect(reason)}",
            error: reason,
            session_ref: session_ref,
            automation_type: "form_interaction",
            timestamp: DateTime.utc_now()
          }

          {:ok, automation_result}
      end
    rescue
      error ->
        Logger.error("[AUTOMATION_STEP] Unexpected error during automation: #{inspect(error)}")

        automation_result = %{
          success: false,
          method: "form_automation",
          details: "Unexpected error: #{inspect(error)}",
          error: error,
          session_ref: session_ref,
          automation_type: "form_interaction",
          timestamp: DateTime.utc_now()
        }

        {:ok, automation_result}
    end
  end

  @impl Reactor.Step
  def compensate(reason, _arguments, _context, _options) do
    Logger.warning("[AUTOMATION_STEP] Compensating form automation")
    Logger.warning("[AUTOMATION_STEP] Compensation reason: #{inspect(reason)}")

    # Clean up any browser sessions that might be open
    cleanup_browser_sessions()

    # Clean up any screenshots or temporary files
    cleanup_automation_artifacts()

    :ok
  end

  # Private helper functions

  defp prepare_form_analysis(page_analysis) do
    # Handle both old format (with page_data) and new format (direct fields)
    if page_analysis[:page_data] do
      # Old format with nested page_data
      %{
        unsubscribe_url: page_analysis.page_data.url,
        html_content: page_analysis.page_data.html_content,
        method: page_analysis.page_data.method,
        steps: [],
        reasoning: "Prepared from reactor page analysis",
        extraction_context: page_analysis[:extraction_context] || %{}
      }
    else
      # New format where data comes directly from HttpUnsubscribeAgent
      %{
        unsubscribe_url: page_analysis[:url] || "unknown",
        html_content: page_analysis[:html_content] || "",
        method: "GET",
        steps: page_analysis[:steps] || [],
        reasoning: page_analysis[:reasoning] || "Prepared from reactor page analysis",
        extraction_context: page_analysis[:extraction_context] || %{}
      }
    end
  end

  defp cleanup_browser_sessions do
    Logger.info("🧹 [AUTOMATION_STEP] Cleaning up browser sessions...")

    try do
      # End any active Wallaby sessions
      case GenServer.whereis(Wallaby.SessionStore) do
        nil ->
          Logger.info("🧹 [AUTOMATION_STEP] No Wallaby session store found")

        pid when is_pid(pid) ->
          # Get active sessions and clean them up
          active_sessions = get_active_wallaby_sessions()
          Logger.info("🧹 [AUTOMATION_STEP] Found #{length(active_sessions)} active sessions")

          Enum.each(active_sessions, fn session ->
            try do
              Wallaby.end_session(session)
            rescue
              # Session might already be closed
              _ -> :ok
            end
          end)
      end
    rescue
      error ->
        Logger.warning("⚠️ [AUTOMATION_STEP] Error during session cleanup: #{inspect(error)}")
    end
  end

  defp cleanup_automation_artifacts do
    Logger.info("🧹 [AUTOMATION_STEP] Cleaning up automation artifacts...")

    # Clean up screenshots directory
    screenshots_dir = "screenshots/wallaby"

    if File.exists?(screenshots_dir) do
      case File.ls(screenshots_dir) do
        {:ok, files} ->
          # Clean up old screenshot files (older than 1 hour)
          cutoff_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

          Enum.each(files, fn filename ->
            file_path = Path.join(screenshots_dir, filename)

            case File.stat(file_path) do
              {:ok, %{mtime: mtime}} ->
                file_datetime =
                  mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

                if DateTime.compare(file_datetime, cutoff_time) == :lt do
                  File.rm(file_path)
                  Logger.info("🗑️ [AUTOMATION_STEP] Cleaned up old screenshot: #{filename}")
                end

              _ ->
                :ok
            end
          end)

        _ ->
          :ok
      end
    end
  end

  defp get_active_wallaby_sessions do
    # This is a simplified version - in practice you'd need to
    # interface with Wallaby's session management
    []
  end
end
