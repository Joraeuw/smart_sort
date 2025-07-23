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
  alias SmartSort.AI.FormTools.Screenshot
  alias SmartSort.AI.MultiSelectorExecutor

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{form_data: page_analysis, user_email: user_email} = arguments
    {:ok, new_session} = Wallaby.start_session()
    new_session = Wallaby.Browser.visit(new_session, page_analysis[:url])
    :timer.sleep(2000)

    case page_analysis.status do
      :success ->
        {:ok, build_success_result(page_analysis)}

      :error ->
        {:ok, build_error_result(page_analysis)}

      :requires_form ->
        Logger.info("[AUTOMATION_STEP] Starting multi-selector automation")

        url = page_analysis[:url] || "unknown"
        steps = page_analysis[:steps] || []

        execute_steps_with_multi_selectors(steps, url, user_email, new_session)
    end
  end

  defp execute_steps_with_multi_selectors(steps, url, user_email, wallaby_session) do
    Logger.info("[AUTOMATION_STEP] Executing #{length(steps)} steps with multi-selector strategy")

    case execute_all_steps(steps, wallaby_session) do
      {:ok, execution_results, final_session} ->
        automation_result = build_automation_result(execution_results, url, steps)

        # wait for contents to load
        :timer.sleep(1000)

        {:ok, final_screenshot, ending_session} =
          Screenshot.take_screenshot_with_session(final_session, "final_screenshot")

        Wallaby.end_session(ending_session)

        {:ok, Map.put(automation_result, :final_screenshot, final_screenshot)}

      {:error, execution_results, error_session} ->
        automation_result = %{
          success: false,
          method: "multi_selector_failed",
          details:
            "Failed at step: #{execution_results.failed_step[:step][:description] || "unknown"}. Completed #{length(execution_results.completed_steps)}/#{execution_results.total_steps} steps.",
          automation_type: "multi_selector_with_fallback",
          timestamp: DateTime.utc_now(),
          url: url,
          error: execution_results.failed_step[:error],
          execution_results: execution_results
        }

        {:ok, automation_result}
    end
  end

  defp execute_all_steps(steps, initial_session) do
    Logger.info("[AUTOMATION_STEP] Starting sequential execution of #{length(steps)} steps")

    {completed_steps, failed_step, final_status, final_session} =
      Enum.reduce_while(steps, {[], nil, :success, initial_session}, fn step,
                                                                        {completed, _failed,
                                                                         _status,
                                                                         current_session} ->
        Logger.info("[AUTOMATION_STEP] ========================================")
        Logger.info("[AUTOMATION_STEP] Executing: #{step.description}")

        case MultiSelectorExecutor.execute_step_with_strategies(step, current_session) do
          {:ok, result, updated_session} ->
            Logger.info("[AUTOMATION_STEP] ✅ Step completed successfully")

            completed_step = %{
              step: step,
              result: result,
              status: :success,
              timestamp: DateTime.utc_now()
            }

            {:cont, {[completed_step | completed], nil, :success, updated_session}}

          {:error, reason, error_session} ->
            Logger.error("[AUTOMATION_STEP] ❌ Step failed: #{reason}")

            failed_step = %{
              step: step,
              error: reason,
              status: :failed,
              timestamp: DateTime.utc_now()
            }

            {:halt, {completed, failed_step, :failed, error_session}}

          {:error, reason} ->
            Logger.error("[AUTOMATION_STEP] ❌ Step failed without session: #{reason}")

            failed_step = %{
              step: step,
              error: reason,
              status: :failed,
              timestamp: DateTime.utc_now()
            }

            {:halt, {completed, failed_step, :failed, current_session}}
        end
      end)

    # FIXED: Return both execution results AND final session
    execution_results = %{
      completed_steps: Enum.reverse(completed_steps),
      failed_step: failed_step,
      final_status: final_status,
      total_steps: length(steps),
      execution_time: 0
    }

    # Return tuple with results and session for proper cleanup
    case final_status do
      :success ->
        {:ok, execution_results, final_session}

      :failed ->
        {:error, execution_results, final_session}
    end
  end

  defp build_automation_result(execution_results, url, original_steps) do
    success = execution_results.final_status == :success
    completed_count = length(execution_results.completed_steps)
    total_count = execution_results.total_steps

    details =
      if success do
        "Successfully completed all #{completed_count}/#{total_count} steps using multi-selector strategy"
      else
        failed_step_desc = execution_results.failed_step[:step][:description] || "unknown step"
        "Failed at step: #{failed_step_desc}. Completed #{completed_count}/#{total_count} steps."
      end

    %{
      success: success,
      method: if(success, do: "multi_selector_automation", else: "multi_selector_failed"),
      details: details,
      automation_type: "multi_selector_with_fallback",
      timestamp: DateTime.utc_now(),
      url: url,
      completed_steps: completed_count,
      total_steps: total_count,
      execution_results: execution_results,
      failed_step: execution_results.failed_step
    }
  end

  defp start_wallaby_session(url) do
    try do
      {:ok, session} = Wallaby.start_session()
      session = Wallaby.Browser.visit(session, url)

      # Wait for page load
      Logger.info("[AUTOMATION_STEP] Waiting for page to load...")
      :timer.sleep(2000)

      {:ok, session}
    rescue
      error ->
        {:error, "Failed to start session: #{inspect(error)}"}
    end
  end

  defp build_success_result(page_analysis) do
    %{
      success: true,
      method: page_analysis[:method] || "simple_http",
      details: page_analysis[:message] || "Simple unsubscribe completed",
      automation_type: "simple_http",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_error_result(page_analysis) do
    %{
      success: false,
      method: "page_analysis_failed",
      details: "Page analysis failed: #{page_analysis[:error]}",
      error: page_analysis[:error],
      automation_type: "failed_analysis",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_review_result(page_analysis) do
    %{
      success: false,
      method: "step_review_required",
      details: "Execution paused - please review the generated steps above",
      automation_type: "paused_for_review",
      timestamp: DateTime.utc_now(),
      steps_generated: length(page_analysis[:steps] || []),
      review_required: true
    }
  end

  defp build_session_error_result(reason) do
    %{
      success: false,
      method: "session_failed",
      details: "Failed to start browser session: #{reason}",
      error: reason,
      automation_type: "session_error",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_success_result(page_analysis) do
    %{
      success: true,
      method: page_analysis[:method] || "simple_http",
      details: page_analysis[:message] || "Simple unsubscribe completed",
      automation_type: "simple_http",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_error_result(page_analysis) do
    %{
      success: false,
      method: "page_analysis_failed",
      details: "Page analysis failed: #{page_analysis[:error]}",
      error: page_analysis[:error],
      automation_type: "failed_analysis",
      timestamp: DateTime.utc_now()
    }
  end

  defp start_wallaby_session(url) do
    try do
      {:ok, session} = Wallaby.start_session()
      session = Wallaby.Browser.visit(session, url)
      # Wait for page load
      :timer.sleep(2000)
      {:ok, session}
    rescue
      error ->
        {:error, "Failed to start session: #{inspect(error)}"}
    end
  end

  defp convert_execution_result(execution_result, url) do
    %{
      success: execution_result.success,
      method: if(execution_result.success, do: "enhanced_automation", else: "automation_failed"),
      details: build_execution_details(execution_result),
      automation_type: "step_by_step_with_recovery",
      timestamp: DateTime.utc_now(),
      url: url,
      execution_time: execution_result.execution_time,
      completed_steps: length(execution_result.completed_steps),
      total_steps: execution_result.total_steps,
      # Include screenshots for debugging
      final_screenshot: execution_result.final_screenshot,
      error_details: execution_result.error_details
    }
  end

  defp build_execution_details(execution_result) do
    if execution_result.success do
      "Successfully completed #{length(execution_result.completed_steps)}/#{execution_result.total_steps} steps in #{execution_result.execution_time}ms"
    else
      failed_step = execution_result.failed_step

      "Failed at step #{failed_step.step_id}: #{failed_step.description}. Completed #{length(execution_result.completed_steps)}/#{execution_result.total_steps} steps."
    end
  end

  defp build_success_result(page_analysis) do
    %{
      success: true,
      method: page_analysis[:method] || "simple_http",
      details: page_analysis[:message] || "Simple unsubscribe completed",
      automation_type: "simple_http",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_error_result(page_analysis) do
    %{
      success: false,
      method: "page_analysis_failed",
      details: "Page analysis failed: #{page_analysis[:error]}",
      error: page_analysis[:error],
      automation_type: "failed_analysis",
      timestamp: DateTime.utc_now()
    }
  end

  defp build_session_error_result(reason) do
    %{
      success: false,
      method: "session_failed",
      details: "Failed to start browser session: #{reason}",
      error: reason,
      automation_type: "session_error",
      timestamp: DateTime.utc_now()
    }
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
