defmodule SmartSort.AI.FormAutomationAgent do
  @moduledoc """
  Agent responsible for browser automation and form interactions.
  Handles complex form analysis, screenshot capture, and automated form submission.
  """

  require Logger
  alias SmartSort.AI.FormTools.{Screenshot, ClickElement}
  import Wallaby.Query, only: [css: 1, css: 2]

  defmodule UnsubscribeStep do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :action, Ecto.Enum,
        values: [
          :fill,
          :click,
          :select,
          :multiselect,
          :check,
          :uncheck,
          :choose,
          :toggle,
          :clear,
          :submit,
          :wait,
          :navigate
        ]

      field :selector, :string
      field :value, :string
      field :description, :string
    end
  end

  defmodule FormAnalysisResponse do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    ## Field Descriptions:
    - steps: Array of form interaction steps needed to unsubscribe from the email list

    Each step should contain:
    - action: One of "fill", "click", "select", "multiselect", "check", "uncheck", "choose", "toggle", "clear", "submit", "wait"
    - selector: CSS selector to target the form element
    - value: Value to enter or select (optional for some actions)
    - description: Human-readable description of what this step accomplishes

    Action types and usage:
    - "fill": Fill text input, action="fill", selector="input[name='email']", value="user@example.com"
    - "click": Click buttons/links, action="click", selector="button[type='submit']"
    - "select": Single dropdown selection, action="select", selector="select[name='frequency']", value="never"
    - "multiselect": Multiple selections, action="multiselect", selector="select[multiple]", value="option1,option2"
    - "check": Check a checkbox, action="check", selector="input[name='newsletter']"
    - "uncheck": Uncheck a checkbox, action="uncheck", selector="input[name='marketing']"
    - "choose": Select radio button, action="choose", selector="input[name='preference']", value="off"
    - "toggle": Toggle checkbox state, action="toggle", selector="input[name='notifications']"
    - "clear": Clear input field, action="clear", selector="input[name='search']"
    - "submit": Submit form, action="submit", selector="form#unsubscribe-form"

    Return empty steps array if no actionable form elements are found.
    """

    @primary_key false
    embedded_schema do
      embeds_many :steps, UnsubscribeStep
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> Ecto.Changeset.validate_length(:steps, min: 0, max: 10)
    end
  end

  @doc """
  Executes browser automation to unsubscribe from a complex form.
  Handles navigation, form interaction, and success detection.
  """
  def execute_form_automation(analysis) do
    Logger.info("🤖 [FORM_AUTOMATION] Starting browser automation")
    Logger.info("🌐 Target URL: #{analysis.unsubscribe_url}")

    # Check if analysis already has steps, if not, analyze the page first
    form_analysis =
      case Map.get(analysis, :steps) do
        nil ->
          Logger.info("📋 No steps provided, analyzing page for form interactions...")

          # First navigate to the page to get HTML content for analysis
          case get_page_content(analysis.unsubscribe_url) do
            {:ok, html_content} ->
              case analyze_page_for_forms(analysis.unsubscribe_url, html_content) do
                {:form_detected, detected_analysis} ->
                  Logger.info(
                    "📝 Generated #{length(detected_analysis.steps || [])} automation steps"
                  )

                  detected_analysis

                :no_form_detected ->
                  Logger.info("⚠️ No forms detected, will try simple click interactions")
                  %{unsubscribe_url: analysis.unsubscribe_url, steps: []}
              end

            {:error, _reason} ->
              Logger.warning("⚠️ Could not fetch page content, proceeding with empty steps")
              %{unsubscribe_url: analysis.unsubscribe_url, steps: []}
          end

        steps ->
          Logger.info("📝 Steps to execute: #{length(steps)}")
          analysis
      end

    try do
      {:ok, session} = Wallaby.start_session()
      result = perform_automation_sequence(session, form_analysis)
      Wallaby.end_session(session)

      case result do
        {:ok, details} ->
          {:ok, %{success: true, method: "form_complex", details: details}}

        {:error, reason} ->
          {:ok,
           %{success: false, method: "form_complex", details: "Automation failed: #{reason}"}}
      end
    rescue
      error ->
        Logger.error("🚫 [FORM_AUTOMATION] Browser automation crashed: #{inspect(error)}")

        fallback_message = """
        Browser automation failed: #{inspect(error)}

        You can manually visit the unsubscribe URL: #{form_analysis.unsubscribe_url}

        Steps to follow:
        #{format_manual_steps(Map.get(form_analysis, :steps, []))}
        """

        {:ok, %{success: false, method: "form_complex", details: fallback_message}}
    end
  end

  @doc """
  Analyzes a webpage to detect if it contains forms requiring interaction.
  Returns analysis with required steps or indicates no form detected.
  """
  def analyze_page_for_forms(page_url, html_content) do
    Logger.info("🔍 [FORM_AUTOMATION] Analyzing page for form interactions")

    text_content = extract_text_from_html(html_content)
    has_form_indicators = detect_form_indicators(html_content, text_content)

    if has_form_indicators do
      Logger.info("📋 Form indicators detected, taking screenshot for visual analysis...")

      case analyze_with_screenshot(page_url, html_content, text_content) do
        {:ok, [_ | _] = form_steps} ->
          {:form_detected,
           %{unsubscribe_url: page_url, method: "form_complex", steps: form_steps}}

        {:ok, []} ->
          Logger.info("🤖 AI found no actionable form elements")
          analyze_with_html_fallback(html_content, text_content, page_url)

        {:error, reason} ->
          Logger.error("🚫 Screenshot analysis failed: #{reason}")
          analyze_with_html_fallback(html_content, text_content, page_url)
      end
    else
      Logger.info("📄 No form indicators found in HTML")
      :no_form_detected
    end
  end

  # Private functions

  defp get_page_content(url) do
    headers = [
      {"User-Agent", "Mozilla/5.0 (compatible; SmartSort Unsubscribe Bot)"},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"}
    ]

    Logger.info("🌐 Fetching page content from: #{url}")

    case HTTPoison.get(url, headers, follow_redirect: true, timeout: 10_000) do
      {:ok, %{status_code: code, body: body}} when code in 200..299 ->
        Logger.info("📄 Page content fetched (#{String.length(body)} chars)")
        {:ok, body}

      {:ok, %{status_code: code}} ->
        Logger.error("🌐 Failed to fetch page content: HTTP #{code}")
        {:error, "HTTP error #{code}"}

      {:error, reason} ->
        Logger.error("🌐 Failed to fetch page content: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_automation_sequence(session, analysis) do
    import Wallaby.Browser

    try do
      # Navigate to the unsubscribe URL
      session = visit(session, analysis.unsubscribe_url)

      # Take a full-page screenshot of the initial state
      case Screenshot.take_full_page_screenshot_named(
             analysis.unsubscribe_url,
             "step_0_initial_page"
           ) do
        {:ok, _path} ->
          Logger.info("[SCREENSHOT] Full-page initial screenshot captured")

        {:error, reason} ->
          Logger.warning(
            "[SCREENSHOT] Full-page screenshot failed, taking regular screenshot: #{reason}"
          )

          session = take_screenshot(session, name: "step_0_initial_page")
      end

      Logger.info("[SCREENSHOT] Initial page screenshot taken")

      # Execute each step with screenshots
      steps = Map.get(analysis, :steps, [])

      {final_session, _step_count} =
        case steps do
          [] ->
            Logger.info(
              "[FORM_AUTOMATION] No automation steps provided, attempting to find unsubscribe elements"
            )

            # Try to find and click obvious unsubscribe elements
            automated_session = attempt_simple_unsubscribe(session)
            {automated_session, 0}

          steps when is_list(steps) ->
            Enum.reduce(steps, {session, 1}, fn step, {current_session, step_num} ->
              Logger.info(
                "[FORM_AUTOMATION] Executing step #{step_num}: #{step.description || inspect(step)}"
              )

              step = Map.put(step, :action, String.to_atom(step.action_type))
              updated_session = execute_automation_step(current_session, step)

              screenshot_session =
                take_screenshot(updated_session, name: "step_#{step_num}_#{step.action}")

              Logger.info("[SCREENSHOT] Step #{step_num} screenshot taken")
              :timer.sleep(500)

              {screenshot_session, step_num + 1}
            end)
        end

      # Take final screenshot and detect success
      final_session = take_screenshot(final_session, name: "final_completion")
      success_message = detect_success_indicators(final_session)

      {:ok, "Successfully completed unsubscribe automation. #{success_message}"}
    rescue
      error ->
        Logger.error("[FORM_AUTOMATION] Step execution failed: #{inspect(error)}")
        {:error, "Step execution failed: #{inspect(error)}"}
    end
  end

  defp execute_automation_step(session, %{action: :navigate, selector: url}) do
    import Wallaby.Browser
    Logger.info("[FORM_AUTOMATION] Navigating to: #{url}")
    visit(session, url)
  end

  defp execute_automation_step(session, %{action: :wait, value: duration})
       when is_binary(duration) do
    duration_ms = String.to_integer(duration)
    Logger.info("[FORM_AUTOMATION] Waiting #{duration_ms}ms")
    :timer.sleep(duration_ms)
    session
  end

  defp execute_automation_step(session, %{action: :wait, value: duration})
       when is_integer(duration) do
    Logger.info("[FORM_AUTOMATION] Waiting #{duration}ms")
    :timer.sleep(duration)
    session
  end

  # Use ClickElement module for all form interactions

  defp execute_automation_step(session, %{action: :choose, selector: selector, value: value}) do
    Logger.info("[FORM_AUTOMATION] Choosing radio button: #{selector} with value: #{value}")

    # Log the full step for debugging
    Logger.info(
      "[FORM_AUTOMATION] Step details - action: :choose, selector: '#{selector}', value: '#{value}'"
    )

    # Try multiple selector strategies for radio buttons
    selectors_to_try = build_radio_selectors(selector, value)
    Logger.info("[FORM_AUTOMATION] Will try #{length(selectors_to_try)} selector strategies")

    result = try_radio_selectors(session, selectors_to_try, value)

    case result do
      {:ok, updated_session} ->
        Logger.info("[FORM_AUTOMATION] Radio button successfully selected")

        # Additional verification can be done here if needed
        case ClickElement.verify_radio_button_change(updated_session, selector, true) do
          {:ok, :changed_correctly} ->
            Logger.info("[FORM_AUTOMATION] Radio button change verified: correctly selected")
            updated_session

          {:ok, :unchanged_but_correct} ->
            Logger.info("[FORM_AUTOMATION] Radio button was already in correct state")
            updated_session

          {:ok, status} ->
            Logger.info("[FORM_AUTOMATION] Radio button verification status: #{status}")
            updated_session

          {:error, reason} ->
            Logger.warning("[FORM_AUTOMATION] Radio button verification failed: #{reason}")
            # Continue anyway since selection succeeded
            updated_session
        end

      {:error, reason} ->
        Logger.error(
          "[FORM_AUTOMATION] Failed to choose radio button with any selector: #{reason}"
        )

        # Debug what's actually on the page
        debug_page_radio_buttons(session)
        # Return original session to continue with other steps
        session
    end
  end

  defp execute_automation_step(session, %{action: action, selector: selector, value: value})
       when action in [
              :fill,
              :click,
              :select,
              :multiselect,
              :check,
              :uncheck,
              :choose,
              :toggle,
              :clear,
              :submit
            ] do
    case ClickElement.perform_action(session, action, selector, value) do
      {:ok, updated_session} ->
        updated_session

      {:error, reason} ->
        Logger.error("[FORM_AUTOMATION] [STEP] Action failed: #{reason}")
        # Continue with original session on error
        session
    end
  end

  defp execute_automation_step(session, step) do
    Logger.warning("[FORM_AUTOMATION] Unknown automation step: #{inspect(step)}")
    session
  end

  # Attempt to find and click obvious unsubscribe elements when no steps are provided
  defp attempt_simple_unsubscribe(session) do
    import Wallaby.Browser

    unsubscribe_selectors = [
      "a[href*='unsubscribe']",
      "button[text*='unsubscribe']",
      "a[text*='unsubscribe']",
      "input[value*='unsubscribe']",
      "button[text*='opt out']",
      "a[text*='opt out']",
      "button[text*='remove']",
      "a[text*='remove me']",
      ".unsubscribe",
      "#unsubscribe",
      "a[href*='optout']",
      "a[href*='opt-out']"
    ]

    Logger.info("[FORM_AUTOMATION] [STEP] Searching for unsubscribe elements...")

    Enum.reduce_while(unsubscribe_selectors, session, fn selector, current_session ->
      try do
        element_query = css(selector)

        if has?(current_session, element_query) do
          Logger.info("[FORM_AUTOMATION] [STEP] Found unsubscribe element: #{selector}")
          updated_session = click(current_session, element_query)
          # Wait for page response
          :timer.sleep(1000)
          {:halt, updated_session}
        else
          {:cont, current_session}
        end
      rescue
        _ ->
          {:cont, current_session}
      end
    end)
  end

  defp analyze_with_screenshot(page_url, _html_content, text_content) do
    case Screenshot.take_screenshot_with_cleanup(page_url, fn screenshot_path ->
           case File.read(screenshot_path) do
             {:ok, image_data} ->
               base64_image = Base.encode64(image_data)

               Logger.info(
                 "[FORM_AUTOMATION] [STEP] Screenshot captured (#{byte_size(image_data)} bytes)"
               )

               analyze_screenshot_with_ai(base64_image, page_url, text_content)

             {:error, reason} ->
               Logger.error("[FORM_AUTOMATION] Failed to read screenshot: #{reason}")
               {:error, "Screenshot capture failed"}
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp analyze_screenshot_with_ai(base64_image, page_url, text_content) do
    Logger.info("[FORM_AUTOMATION] Sending screenshot to GPT-4 Vision for analysis...")

    with {:ok, response} <-
           Instructor.chat_completion(
             model: "gpt-4o-2024-11-20",
             response_model: FormAnalysisResponse,
             max_retries: 3,
             messages: [
               %{
                 role: "system",
                 content: get_visual_analysis_prompt()
               },
               %{
                 role: "user",
                 content: [
                   %{
                     type: "text",
                     text: build_visual_analysis_prompt(page_url, text_content)
                   },
                   %{
                     type: "image_url",
                     image_url: %{url: "data:image/png;base64,#{base64_image}"}
                   }
                 ]
               }
             ]
           ) do
      {:ok, response.steps}
    end
  end

  defp analyze_with_html_fallback(html_content, text_content, page_url) do
    Logger.info("[FORM_AUTOMATION] Falling back to HTML text analysis...")

    case analyze_html_with_ai(html_content, text_content, page_url) do
      {:ok, [_ | _] = form_steps} ->
        {:form_detected, %{unsubscribe_url: page_url, method: "form_complex", steps: form_steps}}

      _ ->
        :no_form_detected
    end
  end

  defp analyze_html_with_ai(html_content, text_content, page_url) do
    Logger.info("[FORM_AUTOMATION] Sending HTML content for structured analysis...")

    with {:ok, response} <-
           Instructor.chat_completion(
             model: "gpt-4o-2024-11-20",
             response_model: FormAnalysisResponse,
             max_retries: 3,
             messages: [
               %{
                 role: "system",
                 content: get_html_analysis_prompt()
               },
               %{
                 role: "user",
                 content: build_html_analysis_prompt(page_url, text_content, html_content)
               }
             ]
           ) do
      {:ok, response.steps}
    end
  end

  defp detect_form_indicators(html_content, text_content) do
    form_patterns = [
      ~r/<form[^>]*>/i,
      ~r/<input[^>]*type=["\']checkbox["\'][^>]*>/i,
      ~r/<input[^>]*type=["\']radio["\'][^>]*>/i,
      ~r/<select[^>]*>/i,
      ~r/<button[^>]*>/i
    ]

    text_patterns = [
      ~r/email\s+preferences/i,
      ~r/unsubscribe/i,
      ~r/opt.?out/i,
      ~r/subscription/i,
      ~r/newsletter/i,
      ~r/marketing/i
    ]

    has_form_elements = Enum.any?(form_patterns, &Regex.match?(&1, html_content))
    has_relevant_text = Enum.any?(text_patterns, &Regex.match?(&1, text_content))

    has_form_elements && has_relevant_text
  end

  defp extract_text_from_html(html_content) do
    html_content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/s, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/s, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp detect_success_indicators(session) do
    import Wallaby.Browser

    success_patterns = [
      "unsubscribed",
      "removed from list",
      "no longer receive",
      "successfully unsubscribed",
      "opt out successful",
      "preference updated",
      "email preferences saved"
    ]

    try do
      page_text = page_source(session)

      found_pattern =
        Enum.find(success_patterns, fn pattern ->
          String.contains?(String.downcase(page_text), pattern)
        end)

      if found_pattern do
        "[FORM_AUTOMATION] Success message detected: '#{found_pattern}'"
      else
        "[FORM_AUTOMATION] Completed automation steps, but no clear success message detected."
      end
    rescue
      _ -> "[FORM_AUTOMATION] Automation completed."
    end
  end

  defp format_manual_steps(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, index} ->
      case step do
        %{action: :fill, selector: selector, value: value, description: desc} ->
          "#{index}. Fill field '#{selector}' with '#{value}' #{(desc && "(" <> desc <> ")") || ""}"

        %{action: :click, selector: selector, description: desc} ->
          "#{index}. Click '#{selector}' #{(desc && "(" <> desc <> ")") || ""}"

        %{action: :select, selector: selector, value: value, description: desc} ->
          "#{index}. Select '#{value}' from dropdown '#{selector}' #{(desc && "(" <> desc <> ")") || ""}"

        %{action: :wait, value: duration} ->
          "#{index}. Wait #{duration}ms"

        _ ->
          "#{index}. #{step.description || "Perform action: #{step.action}"}"
      end
    end)
    |> Enum.join("\n")
  end

  defp get_visual_analysis_prompt do
    """
    You are an expert at analyzing website screenshots to identify form elements for unsubscribing from emails.

    Look carefully at the screenshot and identify all interactive elements that could be used to unsubscribe:

    - **Radio buttons**: Use "choose" action for "On/Off", "Yes/No" options
    - **Checkboxes**: Use "check"/"uncheck" actions for subscription preferences
    - **Buttons**: Use "click" action for "Save", "Update", "Unsubscribe", "Submit" buttons
    - **Dropdowns**: Use "select" action for single selection, "multiselect" for multiple
    - **Text inputs**: Use "fill" action for email confirmation fields
    - **Forms**: Use "submit" action to submit the entire form

    Choose the most appropriate action type for each element:
    - "choose" for radio buttons with specific values
    - "check/uncheck" for explicit checkbox state changes
    - "toggle" when checkbox state is unknown
    - "click" for buttons and links
    - "fill" for text inputs
    - "select/multiselect" for dropdowns

    For each actionable element, provide a CSS selector that will reliably target it.
    Focus on elements that will help unsubscribe from email notifications.
    """
  end

  defp build_visual_analysis_prompt(page_url, text_content) do
    """
    Analyze this unsubscribe page screenshot and provide exact steps to unsubscribe:

    PAGE URL: #{page_url}

    TEXT CONTENT: #{String.slice(text_content, 0, 1000)}

    Focus on finding actionable form elements in the screenshot. Look for:
    - Radio buttons with options like "On/Off" or "Yes/No"
    - Checkboxes for email preferences that can be unchecked
    - Submit/Save buttons to apply changes
    - Dropdown menus for email frequency settings
    - Text inputs requiring email confirmation

    Provide precise CSS selectors and values for each step needed to complete the unsubscribe process.
    """
  end

  defp get_html_analysis_prompt do
    """
    You are an expert at analyzing unsubscribe web pages and determining the exact form interactions needed.

    Analyze the provided HTML content and identify actionable form elements that can be used to unsubscribe from emails.

    Look for:
    - Radio buttons with "On/Off" or "Yes/No" options
    - Checkboxes for subscription preferences
    - Submit/Save buttons to apply changes
    - Dropdown menus for email frequency
    - Text inputs for email confirmation

    Provide precise CSS selectors that will reliably target these elements.
    """
  end

  defp build_html_analysis_prompt(page_url, text_content, html_content) do
    """
    Analyze this unsubscribe page and provide the exact steps needed to unsubscribe:

    PAGE URL: #{page_url}

    TEXT CONTENT (#{String.length(text_content)} chars):
    #{String.slice(text_content, 0, 3000)}

    HTML CONTENT (#{String.length(html_content)} chars):
    #{String.slice(html_content, 0, 8000)}

    Focus on finding actionable form elements. If you see radio buttons like "On: Keep receiving emails" and "Off: Don't send me these emails", target the "Off" option.

    Provide steps to complete the unsubscribe process, including any final save/submit actions.
    """
  end

  # Helper function to build multiple selector strategies
  defp build_radio_selectors(original_selector, value) do
    # Extract possible radio button name and value from the original selector
    {name, extracted_value} = extract_radio_info(original_selector, value)

    selectors = [
      # Use the original selector as-is
      original_selector,

      # Build comprehensive selectors based on extracted info
      if(name && extracted_value, do: "input[name='#{name}'][value='#{extracted_value}']"),
      if(name && value, do: "input[name='#{name}'][value='#{value}']"),
      if(extracted_value, do: "input[type='radio'][value='#{extracted_value}']"),
      if(value, do: "input[type='radio'][value='#{value}']"),

      # Common patterns for unsubscribe radio buttons
      "input[name='email_notif_setting'][value='disabled']",
      "input[name='email_notif_setting'][value='off']",
      "input[name='email_notif_setting'][value='0']",
      "input[name='email_preferences'][value='disabled']",
      "input[name='email_preferences'][value='off']",
      "input[name='notifications'][value='disabled']",
      "input[name='notifications'][value='off']",

      # Generic patterns
      "input[type='radio'][value='disabled']",
      "input[type='radio'][value='off']",
      "input[type='radio'][value='0']",
      "input[type='radio'][value='false']"
    ]

    # Remove nils and duplicates
    selectors
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  # Helper to extract radio button name and value from selector
  defp extract_radio_info(selector, fallback_value) do
    name =
      case Regex.run(~r/name=['"]([^'"]+)['"]/, selector) do
        [_, name] -> name
        _ -> nil
      end

    value =
      case Regex.run(~r/value=['"]([^'"]+)['"]/, selector) do
        [_, value] -> value
        _ -> fallback_value
      end

    {name, value}
  end

  # Helper to try multiple radio button selectors
  defp try_radio_selectors(session, selectors, value) do
    Logger.info("[RADIO_SELECT] Trying #{length(selectors)} selector strategies...")

    Enum.reduce_while(selectors, {:error, "No selectors worked"}, fn selector, _acc ->
      Logger.info("[RADIO_SELECT] Trying selector: #{selector}")

      case ClickElement.perform_action(session, :choose, selector, value) do
        {:ok, updated_session} ->
          Logger.info("[RADIO_SELECT] Success with selector: #{selector}")
          {:halt, {:ok, updated_session}}

        {:error, reason} ->
          Logger.info("[RADIO_SELECT] Failed with selector '#{selector}': #{reason}")
          {:cont, {:error, reason}}
      end
    end)
  end

  # Helper to debug radio buttons on the page
  defp debug_page_radio_buttons(session) do
    Logger.warning("[DEBUG] Analyzing page for radio buttons...")

    try do
      script = """
      var radios = document.querySelectorAll('input[type="radio"]');
      var formElements = document.querySelectorAll('input, button, select');

      return {
        radioCount: radios.length,
        totalFormElements: formElements.length,
        radios: Array.from(radios).map(function(radio) {
          return {
            name: radio.name || '',
            value: radio.value || '',
            id: radio.id || '',
            checked: radio.checked,
            visible: radio.offsetParent !== null,
            textContent: (radio.parentElement ? radio.parentElement.textContent.trim().substring(0, 50) : ''),
            outerHTML: radio.outerHTML.substring(0, 150)
          };
        }),
        pageTitle: document.title,
        pageURL: window.location.href
      };
      """

      result = Wallaby.Browser.execute_script(session, script)

      # Handle the session vs result issue
      page_info =
        case result do
          %Wallaby.Session{} ->
            Logger.warning("[DEBUG] JavaScript execution returned session - debugging failed")
            nil

          info when is_map(info) ->
            info

          _ ->
            nil
        end

      if page_info do
        Logger.warning(
          "[DEBUG] Page: #{page_info["pageTitle"]} (#{page_info["radioCount"]} radios, #{page_info["totalFormElements"]} form elements)"
        )

        if page_info["radioCount"] > 0 do
          Logger.warning("[DEBUG] Found radio buttons:")

          Enum.each(page_info["radios"], fn radio ->
            Logger.warning(
              "[DEBUG]   - name='#{radio["name"]}' value='#{radio["value"]}' checked=#{radio["checked"]} text='#{radio["textContent"]}'"
            )
          end)
        else
          Logger.warning("[DEBUG] No radio buttons found on page")
        end
      end
    rescue
      error ->
        Logger.warning("[DEBUG] Failed to debug page: #{inspect(error)}")
    end
  end
end
