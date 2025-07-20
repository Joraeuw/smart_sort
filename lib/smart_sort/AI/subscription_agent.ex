defmodule SmartSort.AI.SubscriptionAgent do
  @moduledoc """
  Coordinator agent for the unsubscribe process.
  Orchestrates between EmailAnalysisAgent and FormAutomationAgent to handle email unsubscriptions.
  """

  require Logger

  alias SmartSort.Accounts.Email

  alias SmartSort.AI.{
    TextExtractor,
    HttpUnsubscribeAgent,
    FormAutomationAgent
  }

  @doc """
  Executes unsubscribe process for multiple emails in bulk.
  """
  def execute_unsubscribe(email_ids, user_email) when is_list(email_ids) do
    Logger.info("[COORDINATOR] Starting bulk unsubscribe for #{length(email_ids)} emails")

    results =
      email_ids
      |> Enum.map(&Email.get!/1)
      |> Enum.map(&execute_single_unsubscribe(&1, user_email))

    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))

    Logger.info(
      "[COORDINATOR] Bulk unsubscribe complete: #{length(successful)} successful, #{length(failed)} failed"
    )

    %{
      successful: length(successful),
      failed: length(failed),
      results: results
    }
  end

  @doc """
  Executes unsubscribe process for a single email using fast text extraction first.
  """
  def execute_single_unsubscribe(email, user_email) do
    Logger.info("[COORDINATOR] Starting unsubscribe for email ID: #{email.id}")
    Logger.info("[COORDINATOR] Email from: #{email.from_name || email.from_email}")
    Logger.info("[COORDINATOR] Subject: #{email.subject}")
    Logger.info("[COORDINATOR] User email: #{user_email}")

    with {:ok, analysis} <- TextExtractor.extract_unsubscribe_info(email),
         {:ok, result} <- determine_and_execute_method(analysis, user_email) do
      Logger.info("[COORDINATOR] Unsubscribe completed for email #{email.id}")
      Logger.info("[COORDINATOR] Method: #{result.method}")
      Logger.info("[COORDINATOR] Result: #{result.details}")

      {:ok, result}
    else
      error ->
        Logger.error("[COORDINATOR] Unsubscribe failed for email #{email.id}: #{inspect(error)}")

        error
    end
  end

  # Determine the best method based on what was extracted
  defp determine_and_execute_method(analysis, user_email) do
    url = analysis.unsubscribe_url || ""

    cond do
      # Only use URL-based unsubscribe
      String.length(url) > 20 ->
        Logger.info("[COORDINATOR] Using URL-based unsubscribe")
        execute_url_unsubscribe(analysis, user_email)

      # No valid unsubscribe method found
      true ->
        Logger.info("[COORDINATOR] No valid unsubscribe URL available")
        {:ok, %{success: false, method: "none", details: "No unsubscribe URL detected"}}
    end
  end

  defp execute_url_unsubscribe(analysis, user_email) do
    Logger.info("[COORDINATOR] Attempting URL-based unsubscribe")

    case HttpUnsubscribeAgent.execute_http_unsubscribe(analysis.unsubscribe_url) do
      {:ok, response} ->
        Logger.info("[COORDINATOR] HTTP unsubscribe successful: #{response}")
        {:ok, %{success: true, method: "url_simple", details: response}}

      {:requires_form, form_analysis} ->
        Logger.info(
          "[COORDINATOR] HTTP agent detected form requirement - delegating to FormAutomationAgent"
        )

        # Convert page analysis into automation steps
        automation_steps = convert_page_analysis_to_steps(form_analysis)

        # Add the extracted URL and steps to the form analysis
        enhanced_analysis =
          Map.merge(form_analysis, %{
            unsubscribe_url: analysis.unsubscribe_url,
            steps: automation_steps
          })

        FormAutomationAgent.execute_form_automation(enhanced_analysis)

      {:error, reason} ->
        Logger.error("[COORDINATOR] HTTP unsubscribe failed: #{inspect(reason)}")
        {:ok, %{success: false, method: "url_simple", details: inspect(reason)}}
    end
  end

  defp convert_page_analysis_to_steps(form_analysis) do
    # Use the structured steps from the page analyzer
    case Map.get(form_analysis, :steps) do
      steps when is_list(steps) and length(steps) > 0 ->
        Logger.info(
          "[COORDINATOR] Converting #{length(steps)} structured steps from page analyzer"
        )

        # Filter out unnecessary steps and convert
        steps
        |> filter_relevant_steps()
        |> Enum.map(fn step ->
          %{
            action: convert_action_type(step.action_type),
            selector: determine_best_selector(step),
            value: step.element_value,
            description: step.description
          }
        end)

      _ ->
        Logger.error("[COORDINATOR] No structured steps provided by page analyzer")
        []
    end
  end

  # Filter out steps we don't need (like selecting the "enabled" option)
  defp filter_relevant_steps(steps) do
    steps
    |> Enum.filter(fn step ->
      case step.action_type do
        "choose" ->
          # Only keep radio button selections that disable/unsubscribe
          value = String.downcase(step.element_value || "")
          value in ["disabled", "off", "false", "0", "unsubscribe", "optout", "no"]

        "click" ->
          # Keep all click actions (save buttons, etc)
          true

        _ ->
          # Keep other action types
          true
      end
    end)
    |> tap(fn filtered ->
      if length(filtered) < length(steps) do
        Logger.info(
          "[COORDINATOR] Filtered #{length(steps) - length(filtered)} unnecessary steps"
        )
      end
    end)
  end

  # Convert action type to atom and validate
  defp convert_action_type(action_type) when is_binary(action_type) do
    valid_actions = ["click", "choose", "fill", "select", "check", "uncheck"]

    if action_type in valid_actions do
      String.to_atom(action_type)
    else
      Logger.warning("[COORDINATOR] Invalid action type '#{action_type}', defaulting to :click")
      :click
    end
  end

  defp convert_action_type(_), do: :click

  # Determine the best selector to use based on the step information
  defp determine_best_selector(step) do
    cond do
      # Prefer ID if available
      step.element_id && step.element_id != "" ->
        "##{step.element_id}"

      # Use the provided CSS selector if it looks complete
      step.css_selector && step.css_selector != "" ->
        step.css_selector

      # For radio buttons, build a specific selector
      step.element_type == "radio" && step.element_name && step.element_value ->
        "input[name='#{step.element_name}'][value='#{step.element_value}']"

      # For buttons with text, use the text
      step.element_type == "button" && step.element_text && step.element_text != "" ->
        step.element_text

      # Use class if available
      step.element_class && step.element_class != "" ->
        ".#{step.element_class}"

      # Use name attribute
      step.element_name && step.element_name != "" ->
        "#{step.tag_name}[name='#{step.element_name}']"

      # Fallback to generic tag selector
      step.tag_name && step.tag_name != "" ->
        step.tag_name

      true ->
        "button"
    end
  end
end
