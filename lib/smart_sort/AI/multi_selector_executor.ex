defmodule SmartSort.AI.MultiSelectorExecutor do
  @moduledoc """
  Executes steps using multiple selector strategies with intelligent fallback
  """

  require Logger
  alias SmartSort.AI.FormTools.Screenshot

  def execute_step_with_strategies(step, session) do
    Logger.info("[MULTI_SELECTOR] ========================================")
    Logger.info("[MULTI_SELECTOR] 🎯 EXECUTING STEP: #{step.description}")
    Logger.info("[MULTI_SELECTOR] Action: #{step.action_type} | Element: #{step.element_type}")

    strategies = step.selector_strategies || []

    with {:has_strategies, true} <- {:has_strategies, length(strategies) > 0},
         _ <- Logger.info("[MULTI_SELECTOR] Available strategies: #{length(strategies)}"),
         {:ok, success_result, final_session} <-
           try_strategies_in_order(session, step, strategies, 1) do
      {:ok, success_result, final_session}
    else
      {:has_strategies, false} ->
        Logger.error("[MULTI_SELECTOR] ❌ No selector strategies available!")
        {:error, "No selector strategies provided"}

      {:error, reason, error_session} ->
        Logger.error("[MULTI_SELECTOR] Step failed: #{reason}")
        {:error, reason, error_session}

      {:error, reason} ->
        Logger.error("[MULTI_SELECTOR] Step failed: #{reason}")
        {:error, reason}

      other ->
        Logger.error("[MULTI_SELECTOR] Unexpected error: #{inspect(other)}")
        {:error, "Unexpected error during step execution"}
    end
  end

  defp take_screenshot_safe(session, label) do
    case take_screenshot(session, label) do
      {screenshot_data, updated_session} ->
        {screenshot_data, updated_session}

      _error ->
        Logger.warning("[MULTI_SELECTOR] Screenshot failed for #{label}, continuing anyway")

        error_data = %{
          label: label,
          timestamp: DateTime.utc_now(),
          error: "Screenshot capture failed"
        }

        {error_data, session}
    end
  end

  defp try_strategies_in_order(session, step, [], attempt_count) do
    Logger.error(
      "[MULTI_SELECTOR] ❌ COMPLETE FAILURE: All #{attempt_count - 1} strategies exhausted"
    )

    {:error, "All #{attempt_count - 1} selector strategies failed", session}
  end

  defp try_strategies_in_order(session, step, [strategy | remaining], attempt_count) do
    Logger.info("[MULTI_SELECTOR] ----------------------------------------")

    Logger.info(
      "[MULTI_SELECTOR] ATTEMPT #{attempt_count}: #{String.upcase(strategy.strategy_type)}"
    )

    Logger.info("[MULTI_SELECTOR]   Selector: #{strategy.selector}")
    Logger.info("[MULTI_SELECTOR]   Reason: #{strategy.description || "No description"}")

    case execute_with_single_selector(session, step, strategy.selector, strategy.strategy_type) do
      {:ok, result, updated_session} ->
        Logger.info("[MULTI_SELECTOR] ✅ SUCCESS! Strategy worked: #{strategy.strategy_type}")
        Logger.info("[MULTI_SELECTOR] Successful selector: #{strategy.selector}")

        enhanced_result =
          Map.merge(result, %{
            successful_strategy: strategy,
            attempts_made: attempt_count,
            total_strategies: attempt_count + length(remaining)
          })

        {:ok, enhanced_result, updated_session}

      {:error, reason} ->
        Logger.warning("[MULTI_SELECTOR] ❌ Strategy failed: #{reason}")

        # Brief pause before trying next strategy to avoid overwhelming the browser
        :timer.sleep(300)

        try_strategies_in_order(session, step, remaining, attempt_count + 1)
    end
  end

  defp execute_with_single_selector(session, step, selector, strategy_type) do
    case step.action_type do
      "check" ->
        updated_session = Wallaby.Browser.click(session, build_query(selector, strategy_type))
        result = %{action: "checked", selector: selector, strategy_type: strategy_type}
        {:ok, result, updated_session}

      "click" ->
        updated_session = Wallaby.Browser.click(session, build_query(selector, strategy_type))
        result = %{action: "clicked", selector: selector, strategy_type: strategy_type}
        {:ok, result, updated_session}

      "choose" ->
        updated_session = Wallaby.Browser.click(session, build_query(selector, strategy_type))
        result = %{action: "chose", selector: selector, strategy_type: strategy_type}
        {:ok, result, updated_session}

      "fill" ->
        value = step.value || "User opts out from email notifications."

        updated_session =
          Wallaby.Browser.fill_in(session, build_query(selector, strategy_type), with: value)

        result = %{
          action: "filled",
          selector: selector,
          strategy_type: strategy_type,
          value: value
        }

        {:ok, result, updated_session}

      "select" ->
        value = step.value || ""

        updated_session =
          Wallaby.Browser.click(session, Wallaby.Query.option(value))

        result = %{
          action: "selected",
          selector: selector,
          strategy_type: strategy_type,
          value: value
        }

        {:ok, result, updated_session}

      "uncheck" ->
        updated_session = Wallaby.Browser.uncheck(session, build_query(selector, strategy_type))
        result = %{action: "unchecked", selector: selector, strategy_type: strategy_type}
        {:ok, result, updated_session}

      "toggle" ->
        query = build_query(selector, strategy_type)
        element = Wallaby.Browser.find(session, query)
        is_checked = Wallaby.Browser.Element.selected?(element)

        updated_session =
          if is_checked do
            Wallaby.Browser.uncheck(session, query)
          else
            Wallaby.Browser.check(session, query)
          end

        action_taken = if is_checked, do: "unchecked", else: "checked"

        result = %{
          action: "toggled_to_#{action_taken}",
          selector: selector,
          strategy_type: strategy_type
        }

        {:ok, result, updated_session}

      _ ->
        {:error, "Unknown action type: #{step.action_type}"}
    end
  end

  defp take_screenshot(session, label) do
    case Screenshot.take_screenshot_with_session(session, label) do
      {:ok, screenshot_data, updated_session} ->
        {screenshot_data, updated_session}

      {:error, reason, error_session} ->
        Logger.warning("[MULTI_SELECTOR] Screenshot failed: #{reason}")

        screenshot_data = %{
          label: label,
          timestamp: DateTime.utc_now(),
          error: reason
        }

        {screenshot_data, error_session}
    end
  end

  defp build_query(selector, strategy_type) do
    case strategy_type do
      "xpath" ->
        Wallaby.Query.xpath(selector)

      "text_content" ->
        # Convert button:contains('text') to XPath
        if String.contains?(selector, ":contains(") do
          text = Regex.run(~r/:contains\(['"]([^'"]+)['"]\)/, selector) |> List.last()
          element = String.split(selector, ":") |> List.first()
          xpath = "//#{element}[contains(text(), '#{text}')]"
          Wallaby.Query.xpath(xpath)
        else
          Wallaby.Query.css(selector)
        end

      "id" ->
        Wallaby.Query.css(selector)

      "css_name" ->
        Wallaby.Query.css(selector)

      "css_type" ->
        Wallaby.Query.css(selector)

      "css_class" ->
        Wallaby.Query.css(selector)

      "fallback" ->
        Wallaby.Query.css(selector)

      _ ->
        # Unknown strategy type - default to CSS
        Logger.warning("Unknown strategy_type: #{strategy_type}, defaulting to CSS")
        Wallaby.Query.css(selector)
    end
  end

  defp try_strategies_in_order(session, step, [], attempt_count) do
    Logger.error("[MULTI_SELECTOR] ❌ All #{attempt_count - 1} selector strategies failed!")
    {:error, "All selector strategies exhausted"}
  end
end
