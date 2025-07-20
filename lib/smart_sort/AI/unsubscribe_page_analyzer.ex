defmodule SmartSort.AI.UnsubscribePageAnalyzer do
  @moduledoc """
  Agent that analyzes unsubscribe pages using both HTML content and screenshots
  to determine if unsubscribe was successful or what next steps are needed.
  """

  require Logger

  defmodule UnsubscribeStep do
    use Ecto.Schema
    import Ecto.Changeset

    @llm_doc """
    ## Step Field Descriptions:
    - action_type: Type of action to perform ("click", "choose", "fill", "select", "check", "uncheck")
    - element_type: Type of HTML element ("radio", "button", "input", "checkbox", "select", "link")
    - tag_name: HTML tag name from the actual HTML ("input", "button", "a", "select")
    - element_id: ID attribute if present (without #)
    - element_class: CSS class if present (without .)
    - element_name: Name attribute if present
    - value: Value attribute if present (important for radio buttons)
    - element_text: Visible text content of the element
    - selector: Complete CSS selector to target this element
    - description: Human-readable description of what this step does
    """

    @primary_key false
    embedded_schema do
      field :action_type, :string
      field :element_type, :string
      field :tag_name, :string
      field :element_id, :string
      field :element_class, :string
      field :element_name, :string
      field :value, :string
      field :element_text, :string
      field :selector, :string
      field :description, :string
    end

    def changeset(step, params \\ %{}) do
      step
      |> cast(params, [
        :action_type,
        :element_type,
        :tag_name,
        :element_id,
        :element_class,
        :element_name,
        :value,
        :element_text,
        :selector,
        :description
      ])
      |> validate_required([:action_type, :element_type, :selector, :description])
      |> validate_inclusion(:action_type, [
        "click",
        "choose",
        "fill",
        "select",
        "check",
        "uncheck"
      ])
      |> validate_inclusion(:element_type, [
        "radio",
        "button",
        "input",
        "checkbox",
        "select",
        "link"
      ])
    end
  end

  defmodule PageAnalysisResponse do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    ## Field Descriptions:
    - status: The current status of the unsubscribe process ("success", "needs_action", "failed", "unclear")
    - confidence_score: Your confidence in the status assessment (0.0 to 1.0)
    - success_message: Success message text if status is "success"
    - error_message: Error message text if status is "failed"
    - reasoning: Brief explanation of your analysis
    - steps: Detailed steps to complete the unsubscribe process (required when status is "needs_action")

    ## For "steps" field:
    When status is "needs_action", provide detailed steps by analyzing the actual HTML:

    1. FIND ACTUAL ELEMENTS: Look at the provided HTML content and identify real elements
    2. EXTRACT DETAILS: For each element, extract:
       - tag_name: actual HTML tag ("input", "button", "select", etc.)
       - element_id: id attribute value if present
       - element_class: class attribute value if present
       - element_name: name attribute value if present
       - value: value attribute (crucial for radio buttons)
       - element_text: visible text content
    3. BUILD SELECTORS: Create precise CSS selectors using the extracted attributes
    4. DETERMINE ACTIONS: Choose appropriate action_type based on element_type

    Example for <input type="radio" id="email-off" name="emails" value="0">Off</input>:
    - action_type: "choose"
    - element_type: "radio"
    - tag_name: "input"
    - element_id: "email-off"
    - element_name: "emails"
    - value: "0"
    - element_text: "Off"
    - selector: "input[name='emails'][value='0']" or "#email-off"
    """

    @primary_key false
    embedded_schema do
      field :status, :string
      field :confidence_score, :float
      field :success_message, :string
      field :error_message, :string
      field :reasoning, :string
      embeds_many :steps, UnsubscribeStep
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> Ecto.Changeset.validate_number(:confidence_score,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
      |> Ecto.Changeset.validate_inclusion(:status, [
        "success",
        "needs_action",
        "failed",
        "unclear"
      ])
      |> validate_steps_when_needed()
    end

    defp validate_steps_when_needed(changeset) do
      status = Ecto.Changeset.get_field(changeset, :status)

      if status == "needs_action" do
        changeset
        |> Ecto.Changeset.validate_length(:steps,
          min: 1,
          max: 10,
          message: "must provide 1-10 steps when action is needed"
        )
        |> validate_embedded_steps()
      else
        changeset
      end
    end

    defp validate_embedded_steps(changeset) do
      # Validate each embedded step
      case Ecto.Changeset.get_field(changeset, :steps) do
        steps when is_list(steps) ->
          Enum.reduce(steps, changeset, fn step, acc_changeset ->
            # Log what we're trying to validate for debugging
            Logger.info(
              "[PAGE_ANALYZER] [VALIDATION] Validating step: action_type=#{inspect(step.action_type)}, element_type=#{inspect(step.element_type)}"
            )

            step_changeset = UnsubscribeStep.changeset(%UnsubscribeStep{}, Map.from_struct(step))

            if step_changeset.valid? do
              acc_changeset
            else
              Logger.error(
                "[PAGE_ANALYZER] [VALIDATION] Invalid step: #{inspect(step_changeset.errors)}"
              )

              Logger.error("[PAGE_ANALYZER] [VALIDATION] Step data: #{inspect(step)}")

              Ecto.Changeset.add_error(
                acc_changeset,
                :steps,
                "invalid step: #{inspect(step_changeset.errors)}"
              )
            end
          end)

        _ ->
          changeset
      end
    end
  end

  @doc """
  Analyzes an unsubscribe page using HTML and optional screenshot.
  Returns analysis with status and next steps.
  """
  def analyze_page(html_content, screenshot_base64, url, request_method) do
    Logger.info("[PAGE_ANALYZER] Analyzing unsubscribe page: #{url}")
    Logger.info("[PAGE_ANALYZER] HTML length: #{String.length(html_content)} chars")

    Logger.info(
      "[PAGE_ANALYZER] Screenshot: #{if screenshot_base64, do: "provided", else: "none"}"
    )

    # Clean HTML content to prevent encoding errors
    cleaned_html = clean_html_content(html_content)
    Logger.info("[PAGE_ANALYZER] Cleaned HTML length: #{String.length(cleaned_html)} chars")

    # Always try JavaScript element discovery (not dependent on screenshot)
    discovered_elements = discover_elements_with_javascript(url)

    with {:ok, response} <-
           perform_analysis(
             cleaned_html,
             screenshot_base64,
             url,
             request_method,
             discovered_elements
           ) do
      Logger.info(
        "[PAGE_ANALYZER] Analysis complete: #{response.status} (confidence: #{response.confidence_score})"
      )

      log_analysis_results(response)

      case response.status do
        "success" ->
          {:ok, response.success_message || "Successfully unsubscribed"}

        "needs_action" ->
          form_data = %{
            url: url,
            html_content: cleaned_html,
            steps: response.steps,
            reasoning: response.reasoning,
            discovered_elements: discovered_elements
          }

          {:requires_form, form_data}

        "failed" ->
          {:error, response.error_message || "Unsubscribe failed"}

        "unclear" ->
          {:error, "Could not determine unsubscribe status"}
      end
    else
      {:error, reason} = error ->
        Logger.error("[PAGE_ANALYZER] Failed to analyze page: #{inspect(reason)}")
        error
    end
  end

  defp perform_analysis(html_content, screenshot_base64, url, request_method, discovered_elements) do
    messages =
      build_analysis_messages(
        html_content,
        screenshot_base64,
        url,
        request_method,
        discovered_elements
      )

    Instructor.chat_completion(
      # Use latest GPT-4o for maximum capability in HTML parsing and vision
      model: "gpt-4o-2024-11-20",
      response_model: PageAnalysisResponse,
      # Increased retries for better reliability
      max_retries: 3,
      messages: messages
    )
  end

  defp build_analysis_messages(
         html_content,
         screenshot_base64,
         url,
         request_method,
         discovered_elements
       ) do
    base_messages = [
      %{
        role: "system",
        content: """
        You are an expert at analyzing unsubscribe pages to determine their current state and next required actions.

        Your job is to look at the HTML content and screenshot (if provided) to determine:

        STATUS OPTIONS:
        - "success": Unsubscribe completed successfully (confirmation messages, "you've been unsubscribed")
        - "needs_action": Page requires user interaction (buttons to click, forms to fill, choices to make)
        - "failed": Unsubscribe failed (error messages, expired links, broken pages)
        - "unclear": Cannot determine the current state

        CRITICAL: USE JAVASCRIPT ELEMENT DISCOVERY
        Instead of parsing HTML strings, use JavaScript to discover elements by their text content and extract reliable selectors.
        For buttons with text like "Save", "Save Preferences", "Submit", "Unsubscribe":
        - Find elements containing this text
        - Extract the best selector (type="submit", id, simple class, etc.)
        - Prefer simple, reliable selectors like button[type="submit"] over complex class chains

        ANALYSIS PRIORITIES:
        1. Look for clear success indicators first
        2. Check for error states and broken pages
        3. Use JavaScript to find interactive elements by text content
        4. Extract reliable selectors from discovered elements
        5. Use screenshot to understand visual layout and current state
        """
      },
      %{
        role: "user",
        content:
          build_user_content_with_js_discovery(
            html_content,
            url,
            request_method,
            discovered_elements
          )
      }
    ]

    if screenshot_base64 do
      # Add screenshot to the user message if available
      List.update_at(base_messages, -1, fn message ->
        Map.update!(message, :content, fn content ->
          [
            %{
              type: "text",
              text: content
            },
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/png;base64,#{screenshot_base64}"
              }
            }
          ]
        end)
      end)
    else
      base_messages
    end
  end

  defp build_user_content_with_js_discovery(
         html_content,
         url,
         request_method,
         discovered_elements
       ) do
    # Safely extract and clean text content
    safe_text_content =
      try do
        extract_text_content(html_content)
        |> safe_slice(0, 2000)
      rescue
        _ -> "[Text content could not be extracted]"
      end

    # Format discovered elements or provide fallback instructions
    discovery_content =
      if has_discovered_elements?(discovered_elements) do
        format_discovered_elements(discovered_elements)
      else
        get_fallback_instructions()
      end

    """
    Analyze this unsubscribe page to determine its current state and next required actions:

    PAGE INFO:
    - URL: #{url}
    - Request Method: #{request_method}
    - HTML Length: #{String.length(html_content)} characters

    KEY TEXT CONTENT:
    #{safe_text_content}

    #{discovery_content}

    INSTRUCTIONS:
    Generate reliable steps for unsubscribing. Focus on:
    1. Radio buttons with "Off", "Disable", "Don't send" options
    2. Submit buttons - prefer "button[type='submit']" selector when possible
    3. Use discovered selectors when available, otherwise use reliable patterns

    Use both the analysis above and screenshot (if provided) to make your assessment.
    """
  end

  # Check if we have meaningful discovered elements
  defp has_discovered_elements?(discovered_elements) do
    length(discovered_elements.radio_buttons) > 0 or length(discovered_elements.save_buttons) > 0
  end

  # Fallback instructions when JS discovery isn't available
  defp get_fallback_instructions() do
    """
    ANALYSIS APPROACH (No JS Discovery Available):
    Look for these patterns in the text content:
    - Radio button text with "Off", "Don't send", "Disable" options
    - Button text with "Save", "Submit", "Update", "Confirm"
    - Use reliable selectors:
      * Radio: input[name="email_notif_setting"][value="disabled"]
      * Submit: button[type="submit"] or "Save Preferences" (text)
    """
  end

  defp clean_html_content(html_content) do
    html_content
    |> ensure_valid_utf8()
    |> remove_problematic_characters()
    # Keep HTML structure but normalize excessive whitespace
    |> String.replace(~r/\s+/, " ")
    # Remove whitespace between tags
    |> String.replace(~r/>\s+</, "><")
    |> String.trim()
  end

  defp ensure_valid_utf8(binary) do
    case String.valid?(binary) do
      true ->
        binary

      false ->
        # More aggressive cleaning for invalid UTF-8
        Logger.warning("[PAGE_ANALYZER] Cleaning invalid UTF-8 content")

        try do
          # Try to convert from different encodings
          case :unicode.characters_to_binary(binary, :latin1, :utf8) do
            result when is_binary(result) ->
              # Check if result is valid UTF-8 after conversion
              if String.valid?(result) do
                result
              else
                # If still invalid, do aggressive cleaning
                aggressive_utf8_clean(binary)
              end

            _ ->
              aggressive_utf8_clean(binary)
          end
        rescue
          _ ->
            aggressive_utf8_clean(binary)
        end
    end
  end

  # Aggressive UTF-8 cleaning for problematic content
  defp aggressive_utf8_clean(binary) do
    binary
    |> :binary.bin_to_list()
    # Keep only printable ASCII characters to avoid encoding issues
    |> Enum.filter(&(&1 >= 32 && &1 <= 126))
    |> :binary.list_to_bin()
    |> String.replace(~r/[^\x20-\x7E\s]/, "", global: true)
    |> case do
      cleaned when byte_size(cleaned) > 0 -> cleaned
      _ -> "[Content could not be safely processed due to encoding issues]"
    end
  end

  defp remove_problematic_characters(content) do
    content
    # Remove control characters including potential compression markers
    |> String.replace(~r/[\x00-\x1F\x7F-\x9F\x8B]/, "")
    # Remove any remaining non-printable characters
    |> String.replace(~r/[^\x20-\x7E\s]/, "")
    # Remove potential binary markers
    |> String.replace(~r/\x8B/, "")
    # Ensure we have valid content
    |> case do
      "" -> "[Content removed due to encoding issues]"
      cleaned -> cleaned
    end
  end

  defp extract_text_content(html_content) do
    # Extract text content while preserving some HTML structure for analysis
    html_content
    |> String.replace(~r/<script[^>]*>.*?<\/script>/mis, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/mis, "")
    # Keep input and button tags visible in text for AI analysis
    |> String.replace(~r/<(input|button|select)[^>]*>/i, " [\\1] ")
    |> String.replace(~r/<\/?(input|button|select)[^>]*>/i, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp log_analysis_results(response) do
    Logger.info("[PAGE_ANALYZER] Status: #{response.status}")
    Logger.info("[PAGE_ANALYZER] Confidence: #{response.confidence_score}")

    case response.status do
      "success" ->
        Logger.info("[PAGE_ANALYZER] Success: #{response.success_message}")

      "needs_action" ->
        if response.steps && length(response.steps) > 0 do
          Logger.info("[PAGE_ANALYZER] Found #{length(response.steps)} automation steps:")

          Enum.with_index(response.steps, 1)
          |> Enum.each(fn {step, index} ->
            Logger.info(
              "   Step #{index}: #{step.action_type} → #{step.selector} (#{step.description})"
            )
          end)
        else
          Logger.info("[PAGE_ANALYZER] Needs action but no steps provided")
        end

      "failed" ->
        Logger.info("[PAGE_ANALYZER] Error: #{response.error_message}")

      "unclear" ->
        Logger.info("[PAGE_ANALYZER] Status unclear")
    end

    Logger.info("[PAGE_ANALYZER] Reasoning: #{response.reasoning}")
  end

  # JavaScript-based element discovery
  defp discover_elements_with_javascript(url) do
    Logger.info("[PAGE_ANALYZER] [JS_DISCOVERY] Discovering elements with JavaScript")

    try do
      {:ok, session} = Wallaby.start_session()
      Logger.info("[PAGE_ANALYZER] [JS_DISCOVERY] Session started, visiting: #{url}")
      session = Wallaby.Browser.visit(session, url)

      # Wait for page to load
      Logger.info("[PAGE_ANALYZER] [JS_DISCOVERY] Waiting for page load...")
      :timer.sleep(3000)

      # Check if page loaded successfully
      current_url = Wallaby.Browser.current_url(session)
      Logger.info("[PAGE_ANALYZER] [JS_DISCOVERY] Current URL: #{current_url}")

      discovery_script = """
      try {
        var result = { radio_buttons: [], save_buttons: [], debug_info: [] };

        result.debug_info.push('Script started');
        result.debug_info.push('Document ready state: ' + document.readyState);
        result.debug_info.push('Total inputs: ' + document.querySelectorAll('input').length);
        result.debug_info.push('Total buttons: ' + document.querySelectorAll('button').length);

        // 1. Find ALL radio buttons first
        var allRadios = document.querySelectorAll('input[type="radio"]');
        result.debug_info.push('Found ' + allRadios.length + ' radio buttons');

        allRadios.forEach(function(radio, index) {
          var label = radio.parentElement || radio.nextElementSibling || radio.previousElementSibling;
          var text = '';

          // Try to find associated text
          if (label && label.textContent) {
            text = label.textContent.trim();
          } else {
            var parent = radio.parentElement;
            while (parent && !text && parent !== document.body) {
              text = parent.textContent.trim();
              parent = parent.parentElement;
            }
          }

          result.debug_info.push('Radio ' + index + ': name=' + radio.name + ', value=' + radio.value + ', text=' + text.substring(0, 50));

          // Look for "off", "disable", "unsubscribe" options
          if (text.toLowerCase().includes('off') ||
              text.toLowerCase().includes('dont send') ||
              text.toLowerCase().includes('disable') ||
              text.toLowerCase().includes('unsubscribe') ||
              radio.value.toLowerCase() === 'disabled' ||
              radio.value.toLowerCase() === 'off' ||
              radio.value === '0') {
            result.radio_buttons.push({
              selector: 'input[name="' + radio.name + '"][value="' + radio.value + '"]',
              fallback_selector: 'input[type="radio"][value="' + radio.value + '"]',
              text: text.substring(0, 100),
              name: radio.name,
              value: radio.value,
              id: radio.id || ''
            });
            result.debug_info.push('[PAGE_ANALYZER] Added radio: ' + radio.name + '=' + radio.value);
          }
        });

        // 2. Find ALL buttons and inputs
        var allButtons = document.querySelectorAll('button, input[type="submit"], input[type="button"], [role="button"]');
        result.debug_info.push('Found ' + allButtons.length + ' button elements');

        ['Save', 'Save Preferences', 'Submit', 'Update', 'Confirm', 'Apply'].forEach(function(searchText) {
          Array.from(allButtons).forEach(function(el, index) {
            var buttonText = el.textContent || el.value || '';
            result.debug_info.push('Button ' + index + ': text="' + buttonText.substring(0, 30) + '", type=' + (el.type || 'none'));

            if (buttonText.toLowerCase().includes(searchText.toLowerCase())) {
              var selector = null;
              if (el.type === 'submit') {
                selector = 'button[type="submit"]';
              } else if (el.id) {
                selector = '#' + el.id;
              } else if (el.className && el.className.split(' ')[0]) {
                selector = '.' + el.className.split(' ')[0];
              } else {
                selector = el.tagName.toLowerCase();
              }

              result.save_buttons.push({
                selector: selector,
                text: buttonText.trim().substring(0, 100),
                type: el.type || '',
                tagName: el.tagName,
                id: el.id || '',
                className: el.className || ''
              });
              result.debug_info.push('[PAGE_ANALYZER] Added button: ' + buttonText.substring(0, 30));
            }
          });
        });

        result.debug_info.push('Final count: ' + result.radio_buttons.length + ' radios, ' + result.save_buttons.length + ' buttons');
        return result;
      } catch (error) {
        return {
          radio_buttons: [],
          save_buttons: [],
          debug_info: ['Error: ' + error.message]
        };
      }
      """

      result = Wallaby.Browser.execute_script(session, discovery_script)
      Wallaby.end_session(session)

      # Log debug information
      debug_info = Map.get(result, "debug_info", [])

      Enum.each(debug_info, fn info ->
        Logger.info("[PAGE_ANALYZER] [JS_DEBUG] #{info}")
      end)

      # Safely access the result - it should be a map/object
      radio_buttons =
        case result do
          %{"radio_buttons" => radios} -> radios
          _ -> []
        end

      save_buttons =
        case result do
          %{"save_buttons" => buttons} -> buttons
          _ -> []
        end

      Logger.info(
        "[PAGE_ANALYZER] [JS_DISCOVERY] Found #{length(radio_buttons)} radio buttons, #{length(save_buttons)} save buttons"
      )

      %{
        radio_buttons: radio_buttons,
        save_buttons: save_buttons
      }
    rescue
      error ->
        Logger.warning("[PAGE_ANALYZER] [JS_DISCOVERY] Failed: #{inspect(error)}")
        %{radio_buttons: [], save_buttons: []}
    end
  end

  # Format discovered elements for AI analysis
  defp format_discovered_elements(discovered_elements) do
    radio_text =
      case discovered_elements.radio_buttons do
        radios when is_list(radios) and length(radios) > 0 ->
          radio_list =
            Enum.map(radios, fn radio ->
              # Safely access map values
              text = Map.get(radio, "text", "")
              selector = Map.get(radio, "selector", "")
              name = Map.get(radio, "name", "")
              value = Map.get(radio, "value", "")
              "- Radio: #{text} | Selector: #{selector} | Name: #{name} | Value: #{value}"
            end)

          "DISCOVERED RADIO BUTTONS:\n" <> Enum.join(radio_list, "\n")

        _ ->
          "DISCOVERED RADIO BUTTONS: None found"
      end

    button_text =
      case discovered_elements.save_buttons do
        buttons when is_list(buttons) and length(buttons) > 0 ->
          button_list =
            Enum.map(buttons, fn button ->
              # Safely access map values
              text = Map.get(button, "text", "")
              selector = Map.get(button, "selector", "")
              type = Map.get(button, "type", "")
              tag = Map.get(button, "tagName", "")
              "- Button: #{text} | Selector: #{selector} | Type: #{type} | Tag: #{tag}"
            end)

          "DISCOVERED SAVE BUTTONS:\n" <> Enum.join(button_list, "\n")

        _ ->
          "DISCOVERED SAVE BUTTONS: None found"
      end

    "#{radio_text}\n\n#{button_text}"
  end

  defp safe_slice(content, start, length) do
    try do
      String.slice(content, start, length)
    rescue
      _ ->
        # Fallback to binary slicing if String.slice fails
        case content do
          binary when is_binary(binary) ->
            # UTF-8 can be up to 4 bytes per char
            max_bytes = min(byte_size(binary), length * 4)
            safe_binary = binary_part(binary, start, min(max_bytes, byte_size(binary) - start))
            # Try to make it valid UTF-8
            case String.valid?(safe_binary) do
              true ->
                safe_binary

              false ->
                # Remove invalid bytes
                safe_binary
                |> :binary.bin_to_list()
                # Keep ASCII and valid UTF-8 start bytes
                |> Enum.filter(&(&1 < 128 || &1 > 191))
                |> :binary.list_to_bin()
            end

          _ ->
            "[Content could not be safely extracted]"
        end
    end
  end
end
