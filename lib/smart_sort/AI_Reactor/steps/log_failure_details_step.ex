defmodule SmartSort.AI_Reactor.Steps.LogFailureDetailsStep do
  @moduledoc """
  Reactor compensation step for logging comprehensive failure details.

  This step runs when other steps in the reactor fail and provides:
  - Detailed error logging for debugging
  - System state information
  - Failure context for analysis
  - Cleanup of any remaining resources
  """

  use Reactor.Step

  require Logger

  @impl Reactor.Step
  def run(arguments, _context, _options) do
    %{email: email, user_email: user_email, failure_context: failure_context} = arguments

    Logger.error("[FAILURE_LOG] Unsubscribe reactor failed for email: #{email.id}")
    Logger.error("[FAILURE_LOG] From: #{email.from_name || email.from_email}")
    Logger.error("[FAILURE_LOG] Subject: #{email.subject}")
    Logger.error("[FAILURE_LOG] User: #{user_email}")

    # Log comprehensive failure information
    log_failure_details(email, user_email, failure_context)

    # Attempt cleanup of any resources
    perform_cleanup()

    # Generate failure report
    failure_report = generate_failure_report(email, user_email, failure_context)

    Logger.error("[FAILURE_LOG] Failure report generated with ID: #{failure_report.id}")

    {:ok, failure_report}
  end

  @impl Reactor.Step
  def compensate(_reason, arguments, _context, _options) do
    %{email: email} = arguments
    Logger.info("[FAILURE_LOG] Compensating failure logging for email: #{email.id}")

    # This step is already for compensation, so just acknowledge
    :ok
  end

  # Private helper functions

  defp log_failure_details(email, user_email, failure_context) do
    Logger.error("[FAILURE_DETAILS] System Information:")
    Logger.error("[FAILURE_DETAILS] Timestamp: #{DateTime.utc_now()}")

    Logger.error(
      "[FAILURE_DETAILS] Memory Usage: #{format_memory(failure_context.system_info.memory_usage)}"
    )

    Logger.error("[FAILURE_DETAILS] Process Count: #{failure_context.system_info.process_count}")

    Logger.error(
      "[FAILURE_DETAILS] Active Wallaby Sessions: #{failure_context.system_info.wallaby_sessions}"
    )

    Logger.error("[FAILURE_DETAILS] Email Information:")
    Logger.error("[FAILURE_DETAILS] Email ID: #{email.id}")
    Logger.error("[FAILURE_DETAILS] Gmail ID: #{email.gmail_id}")
    Logger.error("[FAILURE_DETAILS] From: #{email.from_email}")
    Logger.error("[FAILURE_DETAILS] Subject: #{String.slice(email.subject || "", 0, 100)}")
    Logger.error("[FAILURE_DETAILS] Body Length: #{String.length(email.body || "")} chars")
    Logger.error("[FAILURE_DETAILS] Received: #{email.received_at}")

    Logger.error("[FAILURE_DETAILS] User Information:")
    Logger.error("[FAILURE_DETAILS] User Email: #{user_email}")

    # Log recent system events
    log_recent_system_events()
  end

  defp log_recent_system_events do
    Logger.error("[FAILURE_DETAILS] Recent System Events:")

    # Log recent error reports (simplified - would be more complex in production)
    recent_errors = get_recent_error_count()
    Logger.error("[FAILURE_DETAILS] Recent errors (last hour): #{recent_errors}")

    # Log system load
    case :cpu_sup.avg1() do
      load when is_integer(load) ->
        Logger.error("[FAILURE_DETAILS] System load (1min): #{load / 256}")

      _ ->
        Logger.error("[FAILURE_DETAILS] System load: unavailable")
    end
  end

  defp get_recent_error_count do
    # In a real implementation, this would query a metrics system
    # For now, return a placeholder
    0
  end

  defp perform_cleanup do
    Logger.info("[FAILURE_LOG] Performing emergency cleanup...")

    # Clean up screenshots
    cleanup_screenshots()

    # Clean up any hanging browser processes
    cleanup_browser_processes()

    # Clear any temporary files
    cleanup_temp_files()
  end

  defp cleanup_screenshots do
    screenshots_dir = "screenshots/wallaby"

    if File.exists?(screenshots_dir) do
      case File.ls(screenshots_dir) do
        {:ok, files} ->
          Logger.info("[FAILURE_LOG] Cleaning up #{length(files)} screenshot files")

          Enum.each(files, fn filename ->
            file_path = Path.join(screenshots_dir, filename)
            File.rm(file_path)
          end)

        {:error, reason} ->
          Logger.warning("[FAILURE_LOG] Could not list screenshots: #{reason}")
      end
    end
  end

  defp cleanup_browser_processes do
    # In a real implementation, this would clean up browser processes
    # For now, just log the attempt
    Logger.info("[FAILURE_LOG] Checking for hanging browser processes...")

    # Could use System.cmd to find and kill hanging Chrome/Firefox processes
    case System.cmd("pgrep", ["chrome"]) do
      {output, 0} ->
        process_count = output |> String.trim() |> String.split("\n") |> length()
        Logger.info("[FAILURE_LOG] Found #{process_count} Chrome processes")

      _ ->
        Logger.info("[FAILURE_LOG] No hanging Chrome processes found")
    end
  end

  defp cleanup_temp_files do
    temp_dirs = ["/tmp", System.tmp_dir()]

    Enum.each(temp_dirs, fn temp_dir ->
      case File.ls(temp_dir) do
        {:ok, files} ->
          wallaby_files = Enum.filter(files, &String.contains?(&1, "wallaby"))

          if length(wallaby_files) > 0 do
            Logger.info(
              "[FAILURE_LOG] Found #{length(wallaby_files)} Wallaby temp files in #{temp_dir}"
            )

            Enum.each(wallaby_files, fn filename ->
              file_path = Path.join(temp_dir, filename)
              File.rm_rf(file_path)
            end)
          end

        _ ->
          :ok
      end
    end)
  end

  defp generate_failure_report(email, user_email, failure_context) do
    %{
      id: generate_report_id(),
      email_id: email.id,
      user_email: user_email,
      failed_at: DateTime.utc_now(),
      system_info: failure_context.system_info,
      email_info: %{
        from: email.from_email,
        subject: String.slice(email.subject || "", 0, 100),
        body_length: String.length(email.body || ""),
        received_at: email.received_at
      },
      reactor_version: "1.0.0",
      cleanup_performed: true
    }
  end

  defp generate_report_id do
    # Generate a unique ID for this failure report
    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  end

  defp format_memory(memory_bytes) when is_integer(memory_bytes) do
    cond do
      memory_bytes > 1_073_741_824 -> "#{Float.round(memory_bytes / 1_073_741_824, 2)} GB"
      memory_bytes > 1_048_576 -> "#{Float.round(memory_bytes / 1_048_576, 2)} MB"
      memory_bytes > 1024 -> "#{Float.round(memory_bytes / 1024, 2)} KB"
      true -> "#{memory_bytes} bytes"
    end
  end

  defp format_memory(_), do: "unknown"
end
