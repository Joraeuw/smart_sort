defmodule SmartSort.AI.FormTools.ClickElement do
  @moduledoc """
  Comprehensive module for interacting with web form elements.
  Supports all essential user interactions including clicking, typing, selecting, and toggling.
  """

  require Logger
  import Wallaby.Browser
  import Wallaby.Query, except: [text: 1]

  @doc """
  Performs a form action based on the action type and parameters.

  ## Actions supported:
  - `:click` - Click buttons, links, or any clickable element
  - `:fill` - Fill text inputs, textareas, or content-editable elements
  - `:select` - Select option from dropdown (single select)
  - `:multiselect` - Select multiple options from multiselect dropdown
  - `:check` - Check a checkbox
  - `:uncheck` - Uncheck a checkbox
  - `:choose` - Choose a radio button option
  - `:toggle` - Toggle a checkbox state
  - `:clear` - Clear an input field
  - `:submit` - Submit a form

  ## Examples

      iex> perform_action(session, :click, "button[type='submit']")
      {:ok, updated_session}

      iex> perform_action(session, :fill, "input[name='email']", "user@example.com")
      {:ok, updated_session}

      iex> perform_action(session, :select, "select[name='frequency']", "never")
      {:ok, updated_session}
  """
  def perform_action(session, action, selector, value \\ nil, opts \\ [])

  # Click actions - buttons, links, generic elements
  def perform_action(session, :click, selector, _value, opts) do
    Logger.info("[CLICK] Clicking element: #{selector}")

    try do
      # Strategy 1: Try finding button by text content
      case try_button_by_text(session, selector, opts) do
        {:ok, updated_session} ->
          Logger.info("[CLICK] Successfully clicked by text: #{selector}")
          {:ok, updated_session}

        {:error, _} ->
          # Strategy 2: Try CSS selector
          case try_button_by_css(session, selector, opts) do
            {:ok, updated_session} ->
              Logger.info("[CLICK] Successfully clicked by CSS: #{selector}")
              {:ok, updated_session}

            {:error, _} ->
              # Strategy 3: Use JavaScript to force click (for complex nested buttons)
              case try_javascript_click(session, selector) do
                {:ok, updated_session} ->
                  Logger.info("[CLICK] Successfully clicked using JavaScript: #{selector}")
                  {:ok, updated_session}

                {:error, _} ->
                  # Strategy 4: Debug what buttons are available
                  debug_available_buttons(session)
                  raise "Button not found or not clickable: #{selector}"
              end
          end
      end
    rescue
      error ->
        Logger.error("[CLICK] Failed to click #{selector}: #{inspect(error)}")
        {:error, "Click failed: #{inspect(error)}"}
    end
  end

  # Fill text inputs
  def perform_action(session, :fill, selector, value, opts) when is_binary(value) do
    Logger.info(
      "[FILL] Filling field '#{selector}' with: #{String.slice(value, 0, 50)}#{if String.length(value) > 50, do: "...", else: ""}"
    )

    try do
      element = find_element(session, selector, :fillable, opts)
      updated_session = fill_in(session, element, with: value)
      Logger.info("[FILL] Successfully filled: #{selector}")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[FILL] Failed to fill #{selector}: #{inspect(error)}")
        {:error, "Fill failed: #{inspect(error)}"}
    end
  end

  # Select single option from dropdown
  def perform_action(session, :select, selector, value, opts) when is_binary(value) do
    Logger.info("[SELECT] Selecting '#{value}' from: #{selector}")

    try do
      # Method 1: Try direct option selection
      case select_option_direct(session, selector, value) do
        {:ok, updated_session} ->
          Logger.info("[SELECT] Successfully selected '#{value}' from: #{selector}")
          {:ok, updated_session}

        {:error, _} ->
          # Method 2: Try finding select element then option
          select_element = find_element(session, selector, :select, opts)
          option_query = css("option", text: value)
          updated_session = session |> find(select_element) |> click(option_query)
          Logger.info("[SELECT] Successfully selected '#{value}' using fallback method")
          {:ok, updated_session}
      end
    rescue
      error ->
        Logger.error("[SELECT] Failed to select '#{value}' from #{selector}: #{inspect(error)}")
        {:error, "Select failed: #{inspect(error)}"}
    end
  end

  # Select multiple options from multiselect dropdown
  def perform_action(session, :multiselect, selector, values, _opts) when is_list(values) do
    Logger.info("[MULTISELECT] Selecting #{length(values)} options from: #{selector}")

    try do
      updated_session =
        Enum.reduce(values, session, fn value, acc_session ->
          Logger.info("[MULTISELECT] Selecting: #{value}")

          case select_option_direct(acc_session, selector, value) do
            {:ok, new_session} ->
              new_session

            {:error, _} ->
              # Fallback to option clicking
              option_query = css("option", text: value)
              click(acc_session, option_query)
          end
        end)

      Logger.info("[MULTISELECT] Successfully selected #{length(values)} options")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[MULTISELECT] Failed to select options from #{selector}: #{inspect(error)}")

        {:error, "Multiselect failed: #{inspect(error)}"}
    end
  end

  # Check a checkbox
  def perform_action(session, :check, selector, _value, opts) do
    Logger.info("[CHECK] Checking checkbox: #{selector}")

    try do
      element = find_element(session, selector, :checkbox, opts)
      # Check if already checked to avoid double-clicking
      is_checked = element_checked?(session, element)

      updated_session =
        if is_checked do
          Logger.info("[CHECK] Checkbox already checked: #{selector}")
          session
        else
          click(session, element)
        end

      Logger.info("[CHECK] Successfully ensured checked: #{selector}")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[CHECK] Failed to check #{selector}: #{inspect(error)}")
        {:error, "Check failed: #{inspect(error)}"}
    end
  end

  # Uncheck a checkbox
  def perform_action(session, :uncheck, selector, _value, opts) do
    Logger.info("[UNCHECK] Unchecking checkbox: #{selector}")

    try do
      element = find_element(session, selector, :checkbox, opts)
      # Check if already unchecked to avoid double-clicking
      is_checked = element_checked?(session, element)

      updated_session =
        if is_checked do
          click(session, element)
        else
          Logger.info("[UNCHECK] Checkbox already unchecked: #{selector}")
          session
        end

      Logger.info("[UNCHECK] Successfully ensured unchecked: #{selector}")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[UNCHECK] Failed to uncheck #{selector}: #{inspect(error)}")
        {:error, "Uncheck failed: #{inspect(error)}"}
    end
  end

  # Choose radio button option
  def perform_action(session, :choose, selector, value, opts) when is_binary(value) do
    Logger.info("[CHOOSE] Choosing radio option '#{value}': #{selector}")

    try do
      # Wait a moment for dynamic content to load
      :timer.sleep(2000)

      # Strategy 1: Try clicking the label instead of hidden radio button
      case try_label_click(session, selector, value, opts) do
        {:ok, updated_session} ->
          Logger.info("[CHOOSE] Successfully chose '#{value}' by clicking label")
          {:ok, updated_session}

        {:error, _} ->
          # Strategy 2: Try direct radio button interaction (even if hidden)
          case try_hidden_radio_click(session, selector, value, opts) do
            {:ok, updated_session} ->
              Logger.info("[CHOOSE] Successfully chose '#{value}' by clicking hidden radio")
              {:ok, updated_session}

            {:error, _} ->
              # Strategy 3: Use JavaScript to directly set the radio value
              case try_javascript_radio_selection(session, selector, value) do
                {:ok, updated_session} ->
                  Logger.info("[CHOOSE] Successfully chose '#{value}' using JavaScript")
                  {:ok, updated_session}

                {:error, _} ->
                  # Strategy 4: Debug what's actually on the page
                  debug_available_radios(session)
                  raise "No radio button found for '#{value}' using selector '#{selector}'"
              end
          end
      end
    rescue
      error ->
        Logger.error("[CHOOSE] Failed to choose '#{value}' for #{selector}: #{inspect(error)}")
        {:error, "Choose failed: #{inspect(error)}"}
    end
  end

  # Toggle checkbox state
  def perform_action(session, :toggle, selector, _value, opts) do
    Logger.info("[TOGGLE] Toggling checkbox: #{selector}")

    try do
      element = find_element(session, selector, :checkbox, opts)
      # Simply click to toggle - browser will handle the state change
      updated_session = click(session, element)
      Logger.info("[TOGGLE] Successfully toggled: #{selector}")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[TOGGLE] Failed to toggle #{selector}: #{inspect(error)}")
        {:error, "Toggle failed: #{inspect(error)}"}
    end
  end

  # Clear input field
  def perform_action(session, :clear, selector, _value, opts) do
    Logger.info("[CLEAR] Clearing field: #{selector}")

    try do
      element = find_element(session, selector, :fillable, opts)
      updated_session = clear(session, element)
      Logger.info("[CLEAR] Successfully cleared: #{selector}")
      {:ok, updated_session}
    rescue
      error ->
        Logger.error("[CLEAR] Failed to clear #{selector}: #{inspect(error)}")
        {:error, "Clear failed: #{inspect(error)}"}
    end
  end

  # Submit form
  def perform_action(session, :submit, selector, _value, opts) do
    Logger.info("[SUBMIT] Submitting form: #{selector}")

    try do
      # Strategy 1: Try finding button by text first
      case try_submit_by_text(session, selector, opts) do
        {:ok, updated_session} ->
          Logger.info("[SUBMIT] Successfully submitted using text: #{selector}")
          {:ok, updated_session}

        {:error, _} ->
          # Strategy 2: Try finding submit elements by CSS selectors
          submit_button_selectors = [
            "#{selector} button[type='submit']",
            "#{selector} input[type='submit']",
            "#{selector} button",
            # Use the selector directly if it's already a button
            selector,
            # Common submit button patterns
            "button[type='submit']",
            "input[type='submit']",
            "button[value*='save']",
            "button[value*='submit']",
            "button[class*='submit']",
            "button[class*='save']",
            "input[value*='save']",
            "input[value*='submit']",
            # Try any button that might be a submit
            "button",
            "input[type='button']"
          ]

          case try_submit_selectors(session, submit_button_selectors, opts) do
            {:ok, updated_session} ->
              updated_session

            {:error, _} ->
              # Strategy 3: Debug what buttons are actually available
              debug_available_buttons(session)
              raise "No submit button found using selector '#{selector}'"
          end
      end

      {:ok, session}
    rescue
      error ->
        Logger.error("[SUBMIT] Failed to submit #{selector}: #{inspect(error)}")
        {:error, "Submit failed: #{inspect(error)}"}
    end
  end

  # Fallback for unknown actions
  def perform_action(_session, action, selector, value, _opts) do
    Logger.error(
      "[UNKNOWN] Unknown action '#{action}' for selector '#{selector}' with value '#{value}'"
    )

    {:error, "Unknown action: #{action}"}
  end

  @doc """
  Waits for an element to appear and become interactable.

  ## Examples

      iex> wait_for_element(session, "button[type='submit']", 5000)
      {:ok, element}
  """
  def wait_for_element(session, selector, timeout_ms \\ 5000) do
    Logger.info("[WAIT] Waiting for element: #{selector} (timeout: #{timeout_ms}ms)")

    try do
      element = Wallaby.Query.css(selector, count: 1, minimum: 1, timeout: timeout_ms)
      found_element = find(session, element)
      Logger.info("[WAIT] Element found: #{selector}")
      {:ok, found_element}
    rescue
      error ->
        Logger.error("[WAIT] Timeout waiting for #{selector}: #{inspect(error)}")
        {:error, "Element not found within timeout: #{inspect(error)}"}
    end
  end

  @doc """
  Checks if an element is visible and interactable.
  """
  def element_visible?(session, selector) do
    try do
      element = Wallaby.Query.css(selector, count: 1)
      find(session, element)
      true
    rescue
      _ -> false
    end
  end

  @doc """
  Gets the text content of an element.
  """
  def get_element_text(session, selector) do
    try do
      element = find_element(session, selector, :any, [])
      text = text(element)
      {:ok, text}
    rescue
      error ->
        {:error, "Failed to get text: #{inspect(error)}"}
    end
  end

  @doc """
  Gets an attribute value from an element.
  """
  def get_element_attribute(session, selector, attribute_name) do
    try do
      element = find_element(session, selector, :any, [])
      # Use JavaScript to get attribute value
      value =
        Wallaby.Browser.execute_script(
          session,
          "return arguments[0].getAttribute('#{attribute_name}');",
          [
            element
          ]
        )

      {:ok, value}
    rescue
      error ->
        {:error, "Failed to get attribute: #{inspect(error)}"}
    end
  end

  # Private helper functions

  defp find_element(session, selector, element_type, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)

    query =
      case element_type do
        :clickable -> get_clickable_query(selector, timeout)
        :fillable -> get_fillable_query(selector, timeout)
        :checkbox -> get_checkbox_query(selector, timeout)
        :radio -> get_radio_query(selector, timeout)
        :select -> get_select_query(selector, timeout)
        :form -> get_form_query(selector, timeout)
        :any -> Wallaby.Query.css(selector, timeout: timeout)
      end

    Wallaby.Browser.find(session, query)
  end

  defp get_clickable_query(selector, timeout) do
    Wallaby.Query.css(selector, timeout: timeout)
  end

  defp get_fillable_query(selector, timeout) do
    cond do
      String.starts_with?(selector, "#") || String.starts_with?(selector, ".") ||
          String.contains?(selector, "[") ->
        Wallaby.Query.css(selector, timeout: timeout)

      true ->
        try do
          Wallaby.Query.fillable_field(selector, timeout: timeout)
        rescue
          _ -> Wallaby.Query.css(selector, timeout: timeout)
        end
    end
  end

  defp get_checkbox_query(selector, timeout) do
    if String.contains?(selector, "checkbox") || String.contains?(selector, "[type=") do
      Wallaby.Query.css(selector, timeout: timeout)
    else
      Wallaby.Query.checkbox(selector, timeout: timeout)
    end
  end

  defp get_radio_query(selector, timeout) do
    if String.contains?(selector, "radio") || String.contains?(selector, "[type=") ||
         String.contains?(selector, "[value=") do
      Wallaby.Query.css(selector, timeout: timeout)
    else
      Wallaby.Query.radio_button(selector, timeout: timeout)
    end
  end

  defp get_select_query(selector, timeout) do
    if String.starts_with?(selector, "select") || String.contains?(selector, "[") do
      Wallaby.Query.css(selector, timeout: timeout)
    else
      Wallaby.Query.select(selector, timeout: timeout)
    end
  end

  defp get_form_query(selector, timeout) do
    if String.starts_with?(selector, "form") || String.contains?(selector, "[") do
      Wallaby.Query.css(selector, timeout: timeout)
    else
      Wallaby.Query.css("form", timeout: timeout)
    end
  end

  defp select_option_direct(session, selector, value) do
    try do
      # Find the select element
      select_element = find_element(session, selector, :select, [])
      # Find the option within the select
      option_query = css("option", text: value)
      updated_session = session |> find(select_element) |> click(option_query)
      {:ok, updated_session}
    rescue
      error -> {:error, error}
    end
  end

  # Helper function to check if element is checked
  defp element_checked?(session, element) do
    try do
      # Use JavaScript to check if checkbox/radio is checked
      result = execute_script(session, "return arguments[0].checked;", [element])
      # Handle various return types
      case result do
        true -> true
        "true" -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  # Helper function to find submit elements
  defp find_submit_element(session, selectors, opts) do
    Enum.reduce_while(selectors, nil, fn selector, _acc ->
      try do
        element = find_element(session, selector, :clickable, opts)
        {:halt, element}
      rescue
        _ -> {:cont, nil}
      end
    end) || raise("No submit element found")
  end

  # Helper function to try to submit by text
  defp try_submit_by_text(session, selector, opts) do
    try do
      # Find the button by its text content
      element = find_element(session, selector, :clickable, opts)
      updated_session = click(session, element)
      {:ok, updated_session}
    rescue
      _ -> {:error, "Failed to submit by text: #{selector}"}
    end
  end

  # Helper function to try clicking button by text content
  defp try_button_by_text(session, selector, opts) do
    import Wallaby.Browser

    try do
      # Try Wallaby's built-in button finding by text
      button_query = Wallaby.Query.button(selector, timeout: 3000)

      if has?(session, button_query) do
        updated_session = click(session, button_query)
        {:ok, updated_session}
      else
        {:error, "Button text not found"}
      end
    rescue
      _ -> {:error, "Button by text failed"}
    end
  end

  defp try_button_by_css(session, selector, opts) do
    try do
      css_selectors = [
        selector,
        "button[type='submit']",
        ".q-click-wrapper",
        "button.q-click-wrapper",
        "button",
        "input[type='submit']",
        "[type='submit']"
      ]

      Enum.reduce_while(css_selectors, {:error, "No CSS selector worked"}, fn css_sel, _acc ->
        try do
          element = find_element(session, css_sel, :clickable, opts)
          updated_element = Wallaby.Element.click(element)
          {:halt, {:ok, updated_element.parent}}
        rescue
          _ -> {:cont, {:error, "CSS selector failed"}}
        end
      end)
    rescue
      _ -> {:error, "CSS click failed"}
    end
  end

  defp try_javascript_click(session, selector) do
    import Wallaby.Browser

    try do
      script = """
      // Try multiple approaches to find and click the button
      var button = null;

      // Strategy 1: Try exact selector
      button = document.querySelector('#{selector}');

      // Strategy 2: Try finding by text content "Save Preferences"
      if (!button) {
        var buttons = document.querySelectorAll('button, [role="button"], .q-click-wrapper');
        for (var i = 0; i < buttons.length; i++) {
          if (buttons[i].textContent.trim().includes('#{selector}')) {
            button = buttons[i];
            break;
          }
        }
      }

      // Strategy 3: Try submit type and Quora-specific patterns
      if (!button && '#{selector}' === 'Save Preferences') {
        button = document.querySelector('button[type="submit"]');
        if (!button) {
          button = document.querySelector('.q-click-wrapper');
        }
      }

      if (button) {
        // Scroll into view
        button.scrollIntoView({ behavior: 'smooth', block: 'center' });

        // Try multiple click approaches
        button.focus();
        button.click();

        // Also fire mouse events in case needed
        button.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
        button.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
        button.dispatchEvent(new MouseEvent('click', { bubbles: true }));

        return {
          success: true,
          text: button.textContent.trim().substring(0, 50),
          tagName: button.tagName,
          className: button.className
        };
      }

      return { success: false, error: 'Button not found' };
      """

      result = execute_script(session, script)

      script_result =
        case result do
          %Wallaby.Session{} ->
            nil

          actual_result when is_map(actual_result) ->
            actual_result

          _ ->
            nil
        end

      if script_result && script_result["success"] do
        Logger.info(
          "[JS] Successfully clicked button: #{script_result["text"]} (#{script_result["tagName"]})"
        )

        :timer.sleep(1000)
        {:ok, session}
      else
        error_msg =
          if script_result, do: script_result["error"], else: "JavaScript execution failed"

        Logger.warning("[JS] Failed to click button: #{error_msg}")
        {:error, error_msg}
      end
    rescue
      error ->
        Logger.error("[JS] JavaScript click failed: #{inspect(error)}")
        {:error, "JavaScript click failed"}
    end
  end

  defp try_label_click(session, selector, value, opts) do
    import Wallaby.Browser

    try do
      label_selectors = [
        "label:has(#{selector})",
        "label[for] input#{selector}",
        "label input#{selector}",
        "label:has(input[name='email_notif_setting'][value='#{value}'])",
        "label input[name='email_notif_setting'][value='#{value}'] ~ .."
      ]

      Enum.reduce_while(label_selectors, {:error, "No label found"}, fn label_selector, _acc ->
        try do
          element = css(label_selector, timeout: 1000)

          if has?(session, element) do
            updated_session = click(session, element)
            {:halt, {:ok, updated_session}}
          else
            {:cont, {:error, "Label not found"}}
          end
        rescue
          _ -> {:cont, {:error, "Label selector failed"}}
        end
      end)
    rescue
      _ -> {:error, "Label click failed"}
    end
  end

  # Helper function to try clicking hidden radio buttons
  defp try_hidden_radio_click(session, selector, value, opts) do
    import Wallaby.Browser

    try do
      # Get initial state before making changes
      initial_state = get_radio_button_state(session, selector)

      # Force interaction with hidden elements using JavaScript
      script = """
      var radio = document.querySelector('#{selector}');
      if (radio) {
        var initialChecked = radio.checked;
        radio.checked = true;
        radio.dispatchEvent(new Event('change', { bubbles: true }));
        radio.dispatchEvent(new Event('click', { bubbles: true }));
        return {
          success: true,
          initialChecked: initialChecked,
          newChecked: radio.checked
        };
      }
      return { success: false };
      """

      result = execute_script(session, script)

      case result do
        %{"success" => true, "initialChecked" => initial, "newChecked" => new_state} ->
          Logger.info("[CLICK_ELEMENT] Radio state change: #{initial} → #{new_state}")

          # Verify the change was successful
          case verify_radio_button_change(session, selector, true) do
            {:ok, :changed_correctly} ->
              Logger.info("[CLICK_ELEMENT] Radio button successfully selected")
              {:ok, session}

            {:ok, :unchanged_but_correct} ->
              Logger.info("[CLICK_ELEMENT] Radio button was already selected")
              {:ok, session}

            {:ok, status} ->
              Logger.warning("[CLICK_ELEMENT] Radio button state verification: #{status}")
              # Continue anyway
              {:ok, session}

            {:error, reason} ->
              Logger.error("[CLICK_ELEMENT] State verification failed: #{reason}")
              # Continue anyway
              {:ok, session}
          end

        %{"success" => false} ->
          Logger.error("[CLICK_ELEMENT] Failed to interact with radio button")
          {:error, "Radio button interaction failed"}

        _ ->
          Logger.error("[CLICK_ELEMENT] Unexpected script result: #{inspect(result)}")
          {:error, "Radio button not found or not clickable"}
      end
    rescue
      _ -> {:error, "Hidden radio click failed"}
    end
  end

  # Helper function to use JavaScript to directly select radio button
  defp try_javascript_radio_selection(session, selector, value) do
    import Wallaby.Browser

    try do
      script = """
      // Try multiple approaches to select the radio button
      var radio = document.querySelector('#{selector}');
      if (!radio) {
        // Try alternative selectors
        radio = document.querySelector('input[name="email_notif_setting"][value="#{value}"]');
      }

      if (radio) {
        // Uncheck all radio buttons in the same group first
        var group = document.querySelectorAll('input[name="' + radio.name + '"]');
        group.forEach(function(r) { r.checked = false; });

        // Check our target radio button
        radio.checked = true;

        // Fire events that the application might be listening for
        radio.dispatchEvent(new Event('change', { bubbles: true }));
        radio.dispatchEvent(new Event('input', { bubbles: true }));
        radio.dispatchEvent(new Event('click', { bubbles: true }));

        return { success: true, value: radio.value, checked: radio.checked };
      }

      return { success: false, error: 'Radio button not found' };
      """

      result = execute_script(session, script)

      # Handle case where result might be a session or actual result
      script_result =
        case result do
          %Wallaby.Session{} ->
            # If it returns a session, JavaScript execution failed
            nil

          actual_result when is_map(actual_result) ->
            actual_result

          _ ->
            nil
        end

      if script_result && script_result["success"] do
        Logger.info(
          "[JS] Successfully selected radio: value=#{script_result["value"]}, checked=#{script_result["checked"]}"
        )

        {:ok, session}
      else
        error_msg =
          if script_result, do: script_result["error"], else: "JavaScript execution failed"

        Logger.warning("[JS] Failed to select radio: #{error_msg}")
        {:error, error_msg}
      end
    rescue
      error ->
        Logger.error("[JS] JavaScript radio selection failed: #{inspect(error)}")
        {:error, "JavaScript selection failed"}
    end
  end

  # Helper function to try to submit using multiple selectors
  defp try_submit_selectors(session, selectors, opts) do
    Enum.reduce_while(selectors, {:error, "No submit button found"}, fn selector, _acc ->
      try do
        element = find_element(session, selector, :clickable, opts)
        updated_session = click(session, element)
        Logger.info("[SUBMIT] Successfully submitted using: #{selector}")
        {:halt, {:ok, updated_session}}
      rescue
        _ -> {:cont, {:error, "No submit button found"}}
      end
    end)
  end

  # Helper function to debug available buttons
  defp debug_available_buttons(session) do
    import Wallaby.Browser
    Logger.warning("[DEBUG] Debugging available buttons:")

    try do
      # Find all buttons on the page using JavaScript
      script = """
      var buttons = document.querySelectorAll('button, input[type="submit"], input[type="button"]');
      if (buttons.length === 0) {
        return [];
      }
      return Array.from(buttons).map(function(btn) {
        return {
          text: btn.textContent || btn.value || '',
          type: btn.type || '',
          id: btn.id || '',
          className: btn.className || '',
          visible: btn.offsetParent !== null,
          outerHTML: btn.outerHTML.substring(0, 150)
        };
      });
      """

      button_info = execute_script(session, script)

      # Handle case where script returns null/undefined or not a list
      button_list =
        case button_info do
          list when is_list(list) -> list
          _ -> []
        end

      if length(button_list) > 0 do
        Logger.warning("[DEBUG] Found #{length(button_list)} buttons:")

        Enum.each(button_list, fn button ->
          Logger.warning(
            "[DEBUG] - Text: '#{button["text"]}', Type: '#{button["type"]}', ID: '#{button["id"]}', Class: '#{button["className"]}', Visible: #{button["visible"]}"
          )

          Logger.warning("[DEBUG]   HTML: #{button["outerHTML"]}")
        end)
      else
        Logger.warning("[DEBUG] No buttons found on the page.")
      end
    rescue
      error -> Logger.warning("[DEBUG] Could not debug buttons: #{inspect(error)}")
    end
  end

  # Helper function to debug available radio buttons
  defp debug_available_radios(session) do
    import Wallaby.Browser
    Logger.warning("⚙️ [DEBUG] Debugging available radio buttons:")

    try do
      # Find all radio buttons on the page using JavaScript
      script = """
      var radios = document.querySelectorAll('input[type="radio"]');
      if (radios.length === 0) {
        return [];
      }
      return Array.from(radios).map(function(radio) {
        return {
          value: radio.value || '',
          id: radio.id || '',
          name: radio.name || '',
          checked: radio.checked || false,
          visible: radio.offsetParent !== null,
          outerHTML: radio.outerHTML.substring(0, 100)
        };
      });
      """

      radio_info = execute_script(session, script)

      # Handle case where script returns session instead of result
      radio_list =
        case radio_info do
          %Wallaby.Session{} ->
            Logger.warning("⚙️ [DEBUG] JavaScript execution returned session - script failed")
            []

          list when is_list(list) ->
            list

          nil ->
            []

          _ ->
            Logger.warning("[DEBUG] Unexpected script result type: #{inspect(radio_info)}")
            []
        end

      if length(radio_list) > 0 do
        Logger.warning("[DEBUG] Found #{length(radio_list)} radio buttons:")

        Enum.each(radio_list, fn radio ->
          Logger.warning(
            "[DEBUG] - Value: '#{radio["value"]}', Name: '#{radio["name"]}', ID: '#{radio["id"]}', Checked: #{radio["checked"]}, Visible: #{radio["visible"]}"
          )

          Logger.warning("[DEBUG]   HTML: #{radio["outerHTML"]}")
        end)
      else
        Logger.warning("[DEBUG] No radio buttons found on the page.")

        # Try to debug what's actually on the page
        debug_page_content(session)
      end
    rescue
      error -> Logger.warning("[DEBUG] Could not debug radio buttons: #{inspect(error)}")
    end
  end

  # Helper to debug general page content when no radio buttons found
  defp debug_page_content(session) do
    try do
      script = """
      var allInputs = document.querySelectorAll('input');
      var allButtons = document.querySelectorAll('button');
      return {
        inputs: allInputs.length,
        buttons: allButtons.length,
        title: document.title,
        url: window.location.href,
        bodyText: document.body ? document.body.innerText.substring(0, 200) : 'No body'
      };
      """

      page_info = execute_script(session, script)

      Logger.warning(
        "[DEBUG] Page info: #{page_info["inputs"]} inputs, #{page_info["buttons"]} buttons"
      )

      Logger.warning("[DEBUG] Title: #{page_info["title"]}")
      Logger.warning("[DEBUG] URL: #{page_info["url"]}")
      Logger.warning("[DEBUG] Body text: #{page_info["bodyText"]}")
    rescue
      error -> Logger.warning("[DEBUG] Could not debug page content: #{inspect(error)}")
    end
  end

  @doc """
  Checks if a radio button state has changed by comparing before/after states.
  Returns {:ok, :changed} or {:ok, :unchanged} or {:error, reason}
  """
  def verify_radio_button_change(session, selector, expected_value \\ true) do
    try do
      # Get initial state
      initial_state = get_radio_button_state(session, selector)

      case initial_state do
        {:ok, initial_checked} ->
          Logger.info("[CLICK_ELEMENT] Initial radio state: #{selector} = #{initial_checked}")

          # Wait a moment for any async changes
          :timer.sleep(200)

          # Get current state
          current_state = get_radio_button_state(session, selector)

          case current_state do
            {:ok, current_checked} ->
              Logger.info("[CLICK_ELEMENT] Current radio state: #{selector} = #{current_checked}")

              cond do
                initial_checked != current_checked ->
                  Logger.info(
                    "[CLICK_ELEMENT] Radio button state changed: #{initial_checked} → #{current_checked}"
                  )

                  if current_checked == expected_value do
                    {:ok, :changed_correctly}
                  else
                    {:ok, :changed_incorrectly}
                  end

                current_checked == expected_value ->
                  Logger.info(
                    "[CLICK_ELEMENT] Radio button already in correct state: #{current_checked}"
                  )

                  {:ok, :unchanged_but_correct}

                true ->
                  Logger.warning("[CLICK_ELEMENT] Radio button state unchanged and incorrect")
                  {:ok, :unchanged_and_incorrect}
              end

            {:error, reason} ->
              Logger.error("[CLICK_ELEMENT] Failed to get current radio state: #{reason}")
              {:error, "Cannot verify current state: #{reason}"}
          end

        {:error, reason} ->
          Logger.error("[CLICK_ELEMENT] Failed to get initial radio state: #{reason}")
          {:error, "Cannot get initial state: #{reason}"}
      end
    rescue
      error ->
        Logger.error("[CLICK_ELEMENT] Radio state verification failed: #{inspect(error)}")
        {:error, "State verification exception: #{inspect(error)}"}
    end
  end

  @doc """
  Gets the current checked state of a radio button.
  """
  def get_radio_button_state(session, selector) do
    try do
      script = """
      var radio = document.querySelector('#{selector}');
      if (radio) {
        return {
          exists: true,
          checked: radio.checked,
          value: radio.value,
          name: radio.name,
          disabled: radio.disabled
        };
      }
      return { exists: false };
      """

      result = execute_script(session, script)

      case result do
        %{"exists" => true, "checked" => checked} ->
          {:ok, checked}

        %{"exists" => false} ->
          {:error, "Radio button not found"}

        nil ->
          {:error, "Script returned null"}

        _ ->
          {:error, "Unexpected script result: #{inspect(result)}"}
      end
    rescue
      error ->
        {:error, "Script execution failed: #{inspect(error)}"}
    end
  end

  @doc """
  Checks if any radio button in a group has changed state.
  Useful for radio button groups where only one can be selected.
  """
  def verify_radio_group_change(session, group_name, expected_value \\ nil) do
    try do
      script = """
      var radios = document.querySelectorAll('input[type="radio"][name="#{group_name}"]');
      var result = {
        groupExists: radios.length > 0,
        radios: []
      };

      for (var i = 0; i < radios.length; i++) {
        var radio = radios[i];
        result.radios.push({
          value: radio.value,
          checked: radio.checked,
          id: radio.id,
          selector: radio.tagName.toLowerCase() +
                    (radio.id ? '#' + radio.id : '') +
                    (radio.className ? '.' + radio.className.split(' ').join('.') : '') +
                    '[value="' + radio.value + '"]'
        });
      }

      return result;
      """

      result = execute_script(session, script)

      case result do
        %{"groupExists" => true, "radios" => radios} ->
          checked_radio = Enum.find(radios, fn radio -> radio["checked"] == true end)

          case checked_radio do
            nil ->
              Logger.info("[CLICK_ELEMENT] No radio selected in group '#{group_name}'")
              {:ok, :none_selected}

            radio ->
              selected_value = radio["value"]

              Logger.info(
                "[CLICK_ELEMENT] Radio group '#{group_name}' selected value: '#{selected_value}'"
              )

              if expected_value && selected_value == expected_value do
                {:ok, :correct_selection, selected_value}
              else
                {:ok, :selection_found, selected_value}
              end
          end

        %{"groupExists" => false} ->
          {:error, "Radio group '#{group_name}' not found"}

        _ ->
          {:error, "Unexpected script result: #{inspect(result)}"}
      end
    rescue
      error ->
        {:error, "Radio group verification failed: #{inspect(error)}"}
    end
  end

  @doc """
  Waits for a radio button state change and verifies it.
  Useful for async form updates.
  """
  def wait_for_radio_change(session, selector, expected_value, timeout_ms \\ 3000) do
    Logger.info("[CLICK_ELEMENT] Waiting for radio change: #{selector}")

    end_time = System.monotonic_time(:millisecond) + timeout_ms
    initial_state = get_radio_button_state(session, selector)

    wait_loop(session, selector, expected_value, initial_state, end_time)
  end

  defp wait_loop(session, selector, expected_value, initial_state, end_time) do
    current_time = System.monotonic_time(:millisecond)

    if current_time >= end_time do
      Logger.warning("[CLICK_ELEMENT] Timeout waiting for radio change")
      {:error, :timeout}
    else
      current_state = get_radio_button_state(session, selector)

      case {initial_state, current_state} do
        {{:ok, initial}, {:ok, current}} when initial != current ->
          Logger.info("[CLICK_ELEMENT] Radio state changed: #{initial} → #{current}")

          if current == expected_value do
            {:ok, :changed_correctly}
          else
            {:ok, :changed_incorrectly}
          end

        {{:ok, _initial}, {:ok, current}} when current == expected_value ->
          Logger.info("[CLICK_ELEMENT] Radio already in correct state")
          {:ok, :already_correct}

        _ ->
          # Wait 100ms and try again
          :timer.sleep(100)
          wait_loop(session, selector, expected_value, initial_state, end_time)
      end
    end
  end
end
