defmodule SmartSort.AI_Reactor.UnsubscribeService do
  @moduledoc """
  Main service module for the Reactor-based unsubscribe system.

  Provides a simple interface for executing unsubscribe processes using the Reactor
  saga pattern with dependency resolution, error handling, and resource cleanup.

  This service can run alongside the existing unsubscribe system to allow for
  gradual migration and A/B testing.
  """

  require Logger

  alias SmartSort.AI_Reactor.Reactors.UnsubscribeReactor
  alias SmartSort.Accounts.Email

  @doc """
  Execute unsubscribe process using the Reactor-based system.

  ## Examples

      iex> email = %SmartSort.Accounts.Email{id: 123}
      iex> SmartSort.AI_Reactor.UnsubscribeService.unsubscribe(email, "user@example.com")
      {:ok, %{success: true, method: "form_automation", details: "Successfully unsubscribed"}}

      iex> SmartSort.AI_Reactor.UnsubscribeService.unsubscribe(email, "user@example.com")
      {:error, "No unsubscribe URL detected"}
  """
  def unsubscribe(email, user_email) when is_struct(email, Email) and is_binary(user_email) do
    Logger.info("[REACTOR_SERVICE] Starting Reactor-based unsubscribe")
    Logger.info("[REACTOR_SERVICE] Email: #{email.id} from #{email.from_email}")
    Logger.info("[REACTOR_SERVICE] User: #{user_email}")

    start_time = System.monotonic_time(:millisecond)

    try do
      case UnsubscribeReactor.execute_unsubscribe(email, user_email) do
        {:ok, result} ->
          duration = System.monotonic_time(:millisecond) - start_time
          log_success_metrics(email, user_email, result, duration)
          {:ok, result}

        {:error, reason} = error ->
          duration = System.monotonic_time(:millisecond) - start_time
          log_failure_metrics(email, user_email, reason, duration)
          error
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("[REACTOR_SERVICE] Unexpected error: #{inspect(error)}")
        log_failure_metrics(email, user_email, inspect(error), duration)
        {:error, "Unexpected system error during unsubscribe"}
    end
  end

  @doc """
  Execute bulk unsubscribe for multiple emails using the Reactor system.

  Processes emails concurrently while respecting rate limits and resource constraints.
  """
  def bulk_unsubscribe(email_ids, user_email) when is_list(email_ids) and is_binary(user_email) do
    Logger.info("[REACTOR_SERVICE] Starting bulk Reactor-based unsubscribe")

    Logger.info(
      "[REACTOR_SERVICE] Processing #{length(email_ids)} emails for user: #{user_email}"
    )

    start_time = System.monotonic_time(:millisecond)

    # Load emails and process them
    emails = Enum.map(email_ids, &Email.get!/1)

    # Process in parallel with controlled concurrency
    results =
      emails
      |> Task.async_stream(
        fn email -> unsubscribe(email, user_email) end,
        max_concurrency: get_max_concurrency(),
        # 1 minute per email
        timeout: 60_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, "Task timed out: #{inspect(reason)}"}
      end)

    # Analyze results
    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))

    duration = System.monotonic_time(:millisecond) - start_time

    bulk_result = %{
      total: length(emails),
      successful: length(successful),
      failed: length(failed),
      results: results,
      duration_ms: duration
    }

    log_bulk_completion_metrics(bulk_result, user_email)

    {:ok, bulk_result}
  end

  @doc """
  Check if the Reactor system is available and healthy.
  """
  def health_check do
    try do
      # For health check, just validate reactor structure without running it
      case validate_reactor_dependencies() do
        :ok ->
          %{
            status: :healthy,
            reactor_version: "1.0.0",
            dependencies: :available,
            checked_at: DateTime.utc_now()
          }

        {:error, reason} ->
          %{
            status: :unhealthy,
            reason: reason,
            reactor_version: "1.0.0",
            checked_at: DateTime.utc_now()
          }
      end
    rescue
      error ->
        %{
          status: :error,
          error: inspect(error),
          checked_at: DateTime.utc_now()
        }
    end
  end

  @doc """
  Get statistics about Reactor usage.
  """
  def get_stats do
    %{
      reactor_version: "1.0.0",
      max_concurrency: get_max_concurrency(),
      active_sessions: count_active_sessions(),
      system_memory: :erlang.memory(:total),
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    }
  end

  # Private helper functions

  defp get_max_concurrency do
    # Configure based on system resources
    case System.schedulers_online() do
      cores when cores >= 8 -> 4
      cores when cores >= 4 -> 2
      _ -> 1
    end
  end

  defp count_active_sessions do
    # Count active Wallaby sessions or other resources
    Process.list()
    |> Enum.count(fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} ->
          Enum.any?(dict, fn {key, _} ->
            key |> to_string() |> String.contains?("wallaby")
          end)

        _ ->
          false
      end
    end)
  end

  defp validate_reactor_dependencies do
    # Check that all required modules are available
    required_modules = [
      SmartSort.AI_Reactor.Reactors.UnsubscribeReactor,
      SmartSort.AI_Reactor.Steps.ExtractUnsubscribeInfoStep,
      SmartSort.AI_Reactor.Steps.AnalyzeUnsubscribePageStep,
      SmartSort.AI_Reactor.Steps.ExecuteFormAutomationStep,
      SmartSort.AI_Reactor.Steps.VerifyUnsubscribeSuccessStep,
      SmartSort.AI_Reactor.Steps.LogFailureDetailsStep
    ]

    missing_modules =
      required_modules
      |> Enum.reject(&Code.ensure_loaded?/1)

    case missing_modules do
      [] -> :ok
      modules -> {:error, "Missing modules: #{inspect(modules)}"}
    end
  end

  defp log_success_metrics(email, user_email, result, duration) do
    Logger.info("[REACTOR_METRICS] Unsubscribe success", %{
      email_id: email.id,
      user_email: hash_email(user_email),
      method: result.method,
      success: result.success,
      duration_ms: duration,
      automation_type: result[:automation_type],
      completed_at: DateTime.utc_now()
    })
  end

  defp log_failure_metrics(email, user_email, reason, duration) do
    Logger.error("[REACTOR_METRICS] Unsubscribe failure", %{
      email_id: email.id,
      user_email: hash_email(user_email),
      reason: reason,
      duration_ms: duration,
      failed_at: DateTime.utc_now()
    })
  end

  defp log_bulk_completion_metrics(bulk_result, user_email) do
    Logger.info("[REACTOR_METRICS] Bulk unsubscribe completion", %{
      user_email: hash_email(user_email),
      total: bulk_result.total,
      successful: bulk_result.successful,
      failed: bulk_result.failed,
      success_rate: bulk_result.successful / bulk_result.total,
      duration_ms: bulk_result.duration_ms,
      completed_at: DateTime.utc_now()
    })
  end

  defp hash_email(email) when is_binary(email) do
    # Hash email for privacy-safe logging
    :crypto.hash(:sha256, email) |> Base.encode16() |> String.slice(0, 8)
  end
end
