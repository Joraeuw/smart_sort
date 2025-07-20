defmodule SmartSort.AI_Reactor.Reactors.UnsubscribeReactor do
  @moduledoc """
  Main Reactor for orchestrating the email unsubscribe process.

  This reactor implements a saga pattern for unsubscribing from emails with:
  - Dependency resolution between steps
  - Concurrent execution where possible
  - Built-in error handling and compensation
  - Dynamic workflow based on email analysis

  Steps:
  1. Extract unsubscribe info from email (text patterns + AI)
  2. Analyze unsubscribe page (if URL found)
  3. Execute form automation (if form detected)
  4. Verify unsubscribe success
  """

  use Reactor

  require Logger

  # Main inputs for the reactor
  input(:email)
  input(:user_email)

  # Step 1: Extract unsubscribe information from email
  step :extract_unsubscribe_info, SmartSort.AI_Reactor.Steps.ExtractUnsubscribeInfoStep do
    argument(:email, input(:email))

    max_retries(2)
  end

  # Step 2: Analyze unsubscribe page (depends on URL from step 1)
  step :analyze_unsubscribe_page, SmartSort.AI_Reactor.Steps.AnalyzeUnsubscribePageStep do
    argument(:unsubscribe_url, result(:extract_unsubscribe_info, [:unsubscribe_url]))
    argument(:analysis_result, result(:extract_unsubscribe_info))

    # Only run if we have a valid URL
    wait_for(:extract_unsubscribe_info)
    max_retries(2)
  end

  # Step 3: Execute form automation (depends on page analysis)
  step :execute_form_automation, SmartSort.AI_Reactor.Steps.ExecuteFormAutomationStep do
    argument(:form_data, result(:analyze_unsubscribe_page))
    argument(:user_email, input(:user_email))

    wait_for(:analyze_unsubscribe_page)
    max_retries(3)
  end

  # Step 4: Verify unsubscribe success (runs after form automation)
  step :verify_unsubscribe_success, SmartSort.AI_Reactor.Steps.VerifyUnsubscribeSuccessStep do
    argument(:automation_result, result(:execute_form_automation))
    argument(:original_url, result(:extract_unsubscribe_info, [:unsubscribe_url]))

    wait_for(:execute_form_automation)
    max_retries(1)
  end

  # Helper step to gather failure context
  # Return the final result
  return(:verify_unsubscribe_success)

  @doc """
  Execute the unsubscribe process for a single email.

  ## Examples

      iex> email = %SmartSort.Accounts.Email{id: 123, from_email: "sender@example.com"}
      iex> SmartSort.AI_Reactor.Reactors.UnsubscribeReactor.run(%{
      ...>   email: email,
      ...>   user_email: "user@example.com"
      ...> })
      {:ok, %{success: true, method: "form_automation", details: "Successfully unsubscribed"}}
  """
  def execute_unsubscribe(email, user_email) do
    Logger.info("[UNSUBSCRIBE_REACTOR] Starting saga for email: #{email.id}")
    Logger.info("[UNSUBSCRIBE_REACTOR] From: #{email.from_name || email.from_email}")
    Logger.info("[UNSUBSCRIBE_REACTOR] User: #{user_email}")

    inputs = %{
      email: email,
      user_email: user_email
    }

    case Reactor.run(__MODULE__, inputs) do
      {:ok, result} ->
        Logger.info("[UNSUBSCRIBE_REACTOR] Saga completed successfully")
        {:ok, result}

      {:error, error} ->
        Logger.error("[UNSUBSCRIBE_REACTOR] Saga failed: #{inspect(error)}")
        {:error, inspect(error)}

      {:error, reason} ->
        Logger.error("[UNSUBSCRIBE_REACTOR] Unexpected error: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
