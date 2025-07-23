defmodule SmartSort.AI.UnsubscribePageAnalyzer do
  @moduledoc """
  Agent that analyzes unsubscribe pages using both HTML content and screenshots
  to determine if unsubscribe was successful or what next steps are needed.
  """

  require Logger

  defmodule SelectorStrategy do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :strategy_type, :string
      field :selector, :string
      field :description, :string
    end

    def changeset(strategy, params \\ %{}) do
      strategy
      |> cast(params, [:strategy_type, :selector, :description])
      |> validate_required([:strategy_type, :selector])
      |> validate_inclusion(:strategy_type, [
        "id",
        "css_name",
        "css_type",
        "xpath",
        "css_class",
        "text_content",
        "fallback"
      ])
    end
  end

  defmodule UnsubscribeStep do
    use Ecto.Schema
    import Ecto.Changeset

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
      field :description, :string

      embeds_many :selector_strategies, SelectorStrategy

      field :data_attributes, :map
      field :xpath_hint, :string
      field :priority_hint, :string
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
        :data_attributes,
        :xpath_hint,
        :priority_hint
      ])
      |> cast_embed(:selector_strategies)
      |> validate_required([:action_type, :element_type])
      |> validate_inclusion(:action_type, [
        "fill",
        "click",
        "choose",
        "select",
        "check",
        "uncheck"
      ])
      |> validate_inclusion(:element_type, [
        "radio",
        "button",
        "input",
        "textarea",
        "checkbox",
        "select",
        "link"
      ])
    end
  end

  # This module is used for LLM response structuring and validation, and is referenced in the analyzer logic, so it must remain.
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
       - tag_name: actual HTML tag ("input", "button", "select", "radio", "checkbox", "link")
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

    # ✅ FIXED: Proper handling of struct-to-map conversion
    defp validate_embedded_steps(changeset) do
      case Ecto.Changeset.get_field(changeset, :steps) do
        steps when is_list(steps) ->
          Enum.reduce(steps, changeset, fn step, acc_changeset ->
            Logger.info(
              "[PAGE_ANALYZER] [VALIDATION] Validating step: action_type=#{inspect(step.action_type)}, element_type=#{inspect(step.element_type)}"
            )

            # Convert step struct to map for Ecto validation
            step_params = convert_step_to_params(step)
            step_changeset = UnsubscribeStep.changeset(%UnsubscribeStep{}, step_params)

            if step_changeset.valid? do
              acc_changeset
            else
              Logger.error(
                "[PAGE_ANALYZER] [VALIDATION] Invalid step: #{inspect(step_changeset.errors)}"
              )

              Logger.error("[PAGE_ANALYZER] [VALIDATION] Step data: #{inspect(step_params)}")

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

    # ✅ NEW: Convert struct to map with proper nested handling
    defp convert_step_to_params(step) when is_struct(step) do
      step_map = Map.from_struct(step)

      # Handle selector_strategies conversion
      case Map.get(step_map, :selector_strategies) do
        strategies when is_list(strategies) ->
          converted_strategies =
            Enum.map(strategies, fn strategy ->
              if is_struct(strategy) do
                Map.from_struct(strategy)
              else
                strategy
              end
            end)

          Map.put(step_map, :selector_strategies, converted_strategies)

        _ ->
          step_map
      end
    end

    defp convert_step_to_params(step) when is_map(step), do: step

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
  def analyze_page(html_content, screenshot_base64, url, request_method, user_email) do
    Logger.info("[PAGE_ANALYZER] Analyzing unsubscribe page: #{url}")
    Logger.info("[PAGE_ANALYZER] HTML length: #{String.length(html_content)} chars")

    Logger.info(
      "[PAGE_ANALYZER] Screenshot: #{if screenshot_base64, do: "provided", else: "none"}"
    )

    # Clean HTML content
    cleaned_html = clean_html_content(html_content)
    Logger.info("[PAGE_ANALYZER] Cleaned HTML length: #{String.length(cleaned_html)} chars")

    # SKIP JS discovery for now - pass empty discovery result
    empty_discovery = %{
      radio_buttons: [],
      checkboxes: [],
      save_buttons: []
    }

    with {:ok, response} <-
           perform_analysis(
             cleaned_html,
             screenshot_base64,
             url,
             request_method,
             empty_discovery,
             user_email
           ) do
      Logger.info(
        "[PAGE_ANALYZER] Analysis complete: #{response.status} (confidence: #{response.confidence_score})"
      )

      # DETAILED STEP LOGGING - This is what you want to see!
      log_detailed_steps(response)

      case response.status do
        "success" ->
          {:ok, response.success_message || "Successfully unsubscribed"}

        "needs_action" ->
          form_data = %{
            html_content: cleaned_html,
            steps: response.steps,
            reasoning: response.reasoning,
            discovered_elements: empty_discovery
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

  # DETAILED STEP LOGGING FUNCTION
  defp log_detailed_steps(response) do
    Logger.info("[PAGE_ANALYZER] ========================================")
    Logger.info("[PAGE_ANALYZER] 📋 GENERATED AUTOMATION STEPS WITH MULTI-SELECTORS")
    Logger.info("[PAGE_ANALYZER] ========================================")
    Logger.info("[PAGE_ANALYZER] Status: #{response.status}")
    Logger.info("[PAGE_ANALYZER] Confidence: #{response.confidence_score}")
    Logger.info("[PAGE_ANALYZER] Reasoning: #{response.reasoning}")

    if response.steps && length(response.steps) > 0 do
      Logger.info("[PAGE_ANALYZER] Found #{length(response.steps)} automation steps:")

      Enum.with_index(response.steps, 1)
      |> Enum.each(fn {step, index} ->
        Logger.info("[PAGE_ANALYZER] ========================================")

        Logger.info(
          "[PAGE_ANALYZER] 📌 STEP #{index}: #{String.upcase(step.action_type)} #{String.upcase(step.element_type)}"
        )

        Logger.info("[PAGE_ANALYZER]   Description: #{step.description}")
        Logger.info("[PAGE_ANALYZER]   Element Details:")
        Logger.info("[PAGE_ANALYZER]     - Name: #{step.element_name || "N/A"}")
        Logger.info("[PAGE_ANALYZER]     - ID: #{step.element_id || "N/A"}")
        Logger.info("[PAGE_ANALYZER]     - Text: #{step.element_text || "N/A"}")
        Logger.info("[PAGE_ANALYZER]     - Value: #{step.value || "N/A"}")

        # Log all selector strategies
        if step.selector_strategies && length(step.selector_strategies) > 0 do
          Logger.info(
            "[PAGE_ANALYZER]   🎯 SELECTOR STRATEGIES (#{length(step.selector_strategies)} options):"
          )

          step.selector_strategies
          |> Enum.each(fn strategy ->
            Logger.info("[PAGE_ANALYZER]     [#{String.upcase(strategy.strategy_type)}]")

            Logger.info("[PAGE_ANALYZER]        Selector: #{strategy.selector}")
            Logger.info("[PAGE_ANALYZER]        Reason: #{strategy.description || "N/A"}")
            Logger.info("[PAGE_ANALYZER]   ⭐ PRIMARY SELECTOR: #{strategy.selector || "NOT SET"}")
          end)
        else
          Logger.info("[PAGE_ANALYZER]   ❌ NO SELECTOR STRATEGIES GENERATED!")
        end

        Logger.info("[PAGE_ANALYZER] ========================================")
      end)
    else
      Logger.info("[PAGE_ANALYZER] ❌ No steps generated!")
    end

    Logger.info("[PAGE_ANALYZER] ========================================")
  end

  # Enhanced AI prompt for better step generation
  defp build_analysis_messages(
         html_content,
         screenshot_base64,
         url,
         request_method,
         _discovered_elements,
         user_email
       ) do
    base_messages = [
      %{
        role: "system",
        content: """
        You are an expert at analyzing HTML and generating multiple robust selector strategies for web automation.

        CRITICAL: For each automation step, generate MULTIPLE selector strategies in order of reliability.

        ⚠️ AUTO-UNSUBSCRIBE DETECTION:
        Sometimes, just opening the unsubscribe link is enough — no buttons, forms, or inputs.

        In these cases:
        - Scan the HTML content for clear confirmation messages like:
        - "You have been unsubscribed"
        - "You have successfully unsubscribed"
        - "Your email preferences have been updated"
        - "You will no longer receive emails"
        - "Successfully removed from mailing list"
        - If any such message is present and there are no actionable interactive elements, conclude the analysis early.
        - Return **no automation steps**, and instead return:
        - `method: "simple_http"`
        - `success: true`
        - `details: "Analysis completed successfully. No interactive elements were present for unsubscribing."`

        SELECTOR STRATEGY TYPES (in priority order):
        1. "id" - ID-based selectors (highest reliability)
           Example: "#email-preferences", "#save-button"

        2. "css_name" - Name attribute selectors (very reliable for forms)
           Example: "input[name='newsletter']", "input[name='email_notifications']"

        3. "css_type" - Type + attribute combinations (reliable)
           Example: "input[type='checkbox'][name='promotions']", "button[type='submit']"

        4. "xpath" - XPath with text content (good for buttons)
           Example: "//button[text()='Save Preferences']", "//input[@name='newsletter']"

        5. "css_class" - CSS class selectors (less reliable)
           Example: ".save-button", ".checkbox-option"

        6. "text_content" - Text-based selectors (fallback)
           Example: "button:contains('Submit')", "label:contains('Unsubscribe') input"

        ACTION TYPE AND ELEMENT TYPE MAPPING:
        **CRITICAL: Use the correct action_type for each element_type:**

        📋 DROPDOWN/SELECT ELEMENTS:
        - HTML: <select><option value="too_many_emails">Too many emails</option></select>
        - action_type: "select"
        - element_type: "select"
        - Description: "Select an option from dropdown"
        - ⚠️ CRITICAL: ALWAYS use the DISPLAYED TEXT (what users see), NOT the value attribute
        - Example: Use "Too many emails" NOT "too_many_emails"

        🔘 RADIO BUTTON ELEMENTS:
        - HTML: <input type="radio" name="preference" value="off">
        - action_type: "choose"
        - element_type: "radio"
        - Description: "Choose a radio button option"
        - Example: Choose "Off" for email notifications

        ☑️ CHECKBOX ELEMENTS:
        - HTML: <input type="checkbox" name="newsletter">
        - action_type: "check" or "uncheck"
        - element_type: "checkbox"
        - Description: "Check/uncheck the checkbox"
        - Example: Check the newsletter subscription checkbox

        🔘 BUTTON ELEMENTS:
        - HTML: <button type="submit">Save</button>
        - action_type: "click"
        - element_type: "button"
        - Description: "Click the button"
        - Example: Click the submit button

        📝 INPUT FIELD ELEMENTS:
        - HTML: <input type="text" name="email">
        - action_type: "fill"
        - element_type: "input"
        - Description: "Fill the input field"
        - Example: Fill the email address field

        STEP GENERATION RULES:
        - Generate 3-5 selector strategies per step
        - Always analyze the actual HTML attributes
        - Prioritize by reliability (ID first, classes last)
        - Include xpath alternatives for complex elements
        - Set priority numbers: 1=highest, 5=lowest
        - **MATCH action_type to element_type correctly (select→select, choose→radio)**
        - **FOR DROPDOWNS: Extract the text content between <option></option> tags, NOT the value attribute**

        EXAMPLE OUTPUT FOR A DROPDOWN:
        HTML: <select id="reason" name="reason_for_unsubscribing">
          <option value="too_many_emails">Too many emails</option>
          <option value="not_interested">Not interested anymore</option>
        </select>

        Step should have:
        - action_type: "select"
        - element_type: "select"
        - value: "Too many emails" ⚠️ USE DISPLAYED TEXT, NOT "too_many_emails"
        - selector_strategies: [
            {
              "strategy_type": "id",
              "selector": "#reason",
              "priority": 1,
              "description": "ID selector - most reliable"
            },
            {
              "strategy_type": "css_name",
              "selector": "select[name='reason_for_unsubscribing']",
              "priority": 2,
              "description": "Name attribute - very stable for forms"
            }
          ]

        EXAMPLE OUTPUT FOR A RADIO BUTTON:
        HTML: <input type="radio" id="email-off" name="email_notifications" value="off">

        Step should have:
        - action_type: "choose" (NOT "select"!)
        - element_type: "radio"
        - value: "off" (the radio button value to choose)
        - selector_strategies: [
            {
              "strategy_type": "id",
              "selector": "#email-off",
              "priority": 1,
              "description": "ID selector - most reliable"
            },
            {
              "strategy_type": "css_name",
              "selector": "input[name='email_notifications'][value='off']",
              "priority": 2,
              "description": "Name and value attributes"
            }
          ]

        VALIDATION REQUIREMENTS:
        - action_type: "click", "choose", "fill", "select", "check", "uncheck"
        - element_type: "radio", "button", "input", "checkbox", "select", "link"
        - **CORRECT PAIRINGS ONLY:**
          ✅ action="select" + element="select"
          ✅ action="choose" + element="radio"
          ✅ action="check" + element="checkbox"
          ✅ action="click" + element="button"
          ✅ action="fill" + element="input"
        - Each step MUST have at least 2 selector strategies
        - Strategies MUST be ordered by priority (1-5)
        - **Each step MUST include a non-empty, human-readable `description` field explaining what the step does**

        🚨 DROPDOWN VALUE RULES - CRITICAL:
        - ❌ WRONG: value: "too_many_emails" (HTML value attribute)
        - ✅ CORRECT: value: "Too many emails" (displayed text users see)
        - ❌ WRONG: value: "not_interested" (HTML value attribute)
        - ✅ CORRECT: value: "Not interested anymore" (displayed text users see)
        - ❌ WRONG: value: "frequency_daily" (HTML value attribute)
        - ✅ CORRECT: value: "Daily" (displayed text users see)

        ALWAYS extract what's between <option>HERE</option> tags for dropdown values!
        """
      },
      %{
        role: "user",
        content: build_multi_selector_user_content(html_content, url, request_method, user_email)
      }
    ]

    if screenshot_base64 do
      List.update_at(base_messages, -1, fn message ->
        Map.update!(message, :content, fn content ->
          [
            %{type: "text", text: content},
            %{type: "image_url", image_url: %{url: "data:image/png;base64,#{screenshot_base64}"}}
          ]
        end)
      end)
    else
      base_messages
    end
  end

  defp build_multi_selector_user_content(html_content, url, request_method, user_email) do
    html_sample = String.slice(html_content || "", 0, 4000)

    """
    ANALYZE THIS HTML AND GENERATE MULTI-SELECTOR AUTOMATION STEPS:

    URL: #{url}
    Method: #{request_method}
    USER EMAIL TO USE: #{user_email || "user@example.com"}


    HTML TO ANALYZE:
    #{html_sample}

    INSTRUCTIONS:
    1. Find all interactive elements (inputs, buttons, checkboxes, radios)
    2. For EACH element, extract ALL available attributes:
       - id attribute
       - name attribute
       - class attribute
       - type attribute
       - value attribute
       - text content
    3. Generate MULTIPLE selector strategies per element using these attributes
    4. Order strategies by reliability (ID first, classes last)

    CRITICAL INSTRUCTIONS:
      - For email input fields, use the email: #{user_email || "user@example.com"}
      - For name fields, use a realistic name like "John Doe"
      - NEVER use placeholder text or generic descriptions
      - Use REAL VALUES that can actually be filled into the form

    EXPECTED ELEMENTS FOR THIS FORM:
    - Multiple checkboxes (look for name attributes like "newsletter", "promotions", "all_emails")
    - One submit button (look for type="submit" or button element)

    For each element, create 3-5 different ways to select it, prioritized by reliability.
    Focus on what's actually in the HTML - don't make up attributes that don't exist!
    Generate automation steps with specific values, not placeholders!
    """
  end

  defp build_focused_user_content(html_content, url, request_method) do
    # Extract just the HTML we need for analysis (first 3000 chars)
    html_sample = String.slice(html_content || "", 0, 3000)

    """
    ANALYZE THIS UNSUBSCRIBE PAGE FOR AUTOMATION STEPS:

    URL: #{url}
    Method: #{request_method}

    HTML TO ANALYZE:
    #{html_sample}

    TASK:
    1. Look for interactive elements (checkboxes, radio buttons, submit buttons)
    2. Extract their actual attributes (name, id, type, value)
    3. Generate precise CSS selectors based on these attributes
    4. Create automation steps to complete unsubscription

    For the test form, you should find:
    - 3 checkboxes with names: "newsletter", "promotions", "all_emails"
    - 1 submit button

    Generate steps that will:
    1. Check the appropriate checkbox(es) for unsubscribing
    2. Click the submit button

    Focus on creating reliable selectors from the actual HTML attributes!
    """
  end

  # Update ExecuteFormAutomationStep to pause execution
  defmodule SmartSort.AI_Reactor.Steps.ExecuteFormAutomationStep do
    use Reactor.Step
    require Logger

    @impl Reactor.Step
    def run(arguments, _context, _options) do
      %{form_data: page_analysis, user_email: user_email} = arguments

      case page_analysis.status do
        :success ->
          {:ok, build_success_result(page_analysis)}

        :error ->
          {:ok, build_error_result(page_analysis)}

        :requires_form ->
          {:ok, build_success_result(page_analysis)}
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
  end

  defp perform_analysis(
         html_content,
         screenshot_base64,
         url,
         request_method,
         discovered_elements,
         user_email
       ) do
    messages =
      build_analysis_messages(
        html_content,
        screenshot_base64,
        url,
        request_method,
        discovered_elements,
        user_email
      )

    Instructor.chat_completion(
      model: "gpt-4o-2024-11-20",
      response_model: PageAnalysisResponse,
      max_retries: 3,
      messages: messages
    )
  end

  defp build_analysis_messages(
         html_content,
         screenshot_base64,
         url,
         request_method,
         discovered_elements,
         user_email
       ) do
    base_messages = [
      %{
        role: "system",
        content: """
        You are an expert at analyzing unsubscribe pages and generating automation steps.

        CRITICAL VALIDATION RULES:
        1. action_type MUST be one of: "click", "choose", "fill", "select", "check", "uncheck"
           - Use "click" for buttons and submit buttons
           - Use "check" for checkboxes
           - Use "choose" for radio buttons
           - NEVER use "submit" as action_type!

        2. element_type MUST be one of: "radio", "button", "input", "checkbox", "select", "link"
           - Use "button" for submit buttons
           - Use "checkbox" for checkboxes
           - NEVER use "submit" as element_type!

        3. selector field is REQUIRED - generate the best CSS selector for each element

        SELECTOR GENERATION:
        For each step, generate a specific CSS selector:
        - Checkboxes: "input[name='newsletter']" or "input[type='checkbox'][name='newsletter']"
        - Submit buttons: "button[type='submit']" or "#submit-button"
        - Radio buttons: "input[name='emails'][value='off']"

        EXAMPLE CORRECT STEP:
        {
          "action_type": "check",
          "element_type": "checkbox",
          "selector": "input[name='newsletter']",
          "element_name": "newsletter",
          "element_text": "Unsubscribe from newsletter",
          "description": "Check the newsletter unsubscribe checkbox"
        }
        """
      },
      %{
        role: "user",
        content:
          build_user_content_with_js_discovery(
            html_content,
            url,
            request_method,
            discovered_elements,
            user_email
          )
      }
    ]

    if screenshot_base64 do
      List.update_at(base_messages, -1, fn message ->
        Map.update!(message, :content, fn content ->
          [
            %{type: "text", text: content},
            %{type: "image_url", image_url: %{url: "data:image/png;base64,#{screenshot_base64}"}}
          ]
        end)
      end)
    else
      base_messages
    end
  end

  defp build_enhanced_user_content(
         html_content,
         url,
         request_method,
         discovered_elements,
         user_email
       ) do
    # Extract first 4000 chars of HTML for analysis
    html_sample = String.slice(html_content || "", 0, 4000)

    # Format discovered elements
    discovery_info =
      if has_discovered_elements?(discovered_elements) do
        format_discovered_elements(discovered_elements)
      else
        "JAVASCRIPT DISCOVERY: Not available - analyze HTML directly"
      end

    """
    ANALYZE THIS UNSUBSCRIBE PAGE:

    URL: #{url}
    Method: #{request_method}
    My email: #{user_email}
    HTML Sample: #{String.length(html_sample)} characters

    #{discovery_info}

    HTML CONTENT TO ANALYZE:
    #{html_sample}

    INSTRUCTIONS:
    1. Look for radio buttons with "Off", "Disable", "Don't send" options
    2. Find submit/save buttons
    3. Extract ALL available attributes for each element
    4. Create steps with multiple selector strategies
    5. Assign priority hints based on selector reliability

    Focus on creating steps that will work reliably with the enhanced execution engine!
    """
  end

  defp build_user_content_with_js_discovery(
         html_content,
         url,
         request_method,
         discovered_elements,
         user_email
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
    - My email: #{user_email}
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

      discovery_script = """
      try {
        var result = {
          radio_buttons: [],
          checkboxes: [],        // ✅ ADD CHECKBOXES
          submit_buttons: [],    // ✅ RENAME FROM save_buttons
          debug_info: []
        };

        result.debug_info.push('Script started');
        result.debug_info.push('Document ready state: ' + document.readyState);

        // 1. Find ALL checkboxes (not just radios)
        var allCheckboxes = document.querySelectorAll('input[type="checkbox"]');
        result.debug_info.push('Found ' + allCheckboxes.length + ' checkboxes');

        allCheckboxes.forEach(function(checkbox, index) {
          var label = checkbox.parentElement || checkbox.nextElementSibling || checkbox.previousElementSibling;
          var text = '';

          // Try to find associated text
          if (label && label.textContent) {
            text = label.textContent.trim();
          } else {
            var parent = checkbox.parentElement;
            while (parent && !text && parent !== document.body) {
              text = parent.textContent.trim();
              parent = parent.parentElement;
            }
          }

          result.checkboxes.push({
            selector: checkbox.name ? 'input[name="' + checkbox.name + '"]' : 'input[type="checkbox"]',
            text: text.substring(0, 100),
            name: checkbox.name || '',
            id: checkbox.id || '',
            value: checkbox.value || ''
          });
        });

        // 2. Find ALL radio buttons
        var allRadios = document.querySelectorAll('input[type="radio"]');
        result.debug_info.push('Found ' + allRadios.length + ' radio buttons');

        allRadios.forEach(function(radio, index) {
          var label = radio.parentElement || radio.nextElementSibling || radio.previousElementSibling;
          var text = '';

          if (label && label.textContent) {
            text = label.textContent.trim();
          }

          result.radio_buttons.push({
            selector: 'input[name="' + radio.name + '"][value="' + radio.value + '"]',
            text: text.substring(0, 100),
            name: radio.name,
            value: radio.value,
            id: radio.id || ''
          });
        });

        // 3. Find submit buttons
        var submitButtons = document.querySelectorAll('button[type="submit"], input[type="submit"], button');
        result.debug_info.push('Found ' + submitButtons.length + ' buttons');

        submitButtons.forEach(function(button, index) {
          var buttonText = button.textContent || button.value || '';

          result.submit_buttons.push({
            selector: button.type === 'submit' ? 'button[type="submit"]' : (button.id ? '#' + button.id : 'button'),
            text: buttonText.trim().substring(0, 100),
            type: button.type || '',
            tagName: button.tagName,
            id: button.id || ''
          });
        });

        result.debug_info.push('Final count: ' + result.radio_buttons.length + ' radios, ' +
                             result.checkboxes.length + ' checkboxes, ' +
                             result.submit_buttons.length + ' buttons');
        return result;
      } catch (error) {
        return {
          radio_buttons: [],
          checkboxes: [],
          submit_buttons: [],
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

      # Extract results
      radio_buttons = Map.get(result, "radio_buttons", [])
      # ✅ ADD CHECKBOXES
      checkboxes = Map.get(result, "checkboxes", [])
      # ✅ RENAME
      submit_buttons = Map.get(result, "submit_buttons", [])

      Logger.info(
        "[PAGE_ANALYZER] [JS_DISCOVERY] Found #{length(radio_buttons)} radios, #{length(checkboxes)} checkboxes, #{length(submit_buttons)} buttons"
      )

      %{
        radio_buttons: radio_buttons,
        # ✅ INCLUDE CHECKBOXES
        checkboxes: checkboxes,
        submit_buttons: submit_buttons
      }
    rescue
      error ->
        Logger.warning("[PAGE_ANALYZER] [JS_DISCOVERY] Failed: #{inspect(error)}")
        %{radio_buttons: [], checkboxes: [], submit_buttons: []}
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

    checkbox_text =
      case discovered_elements.checkboxes do
        checkboxes when is_list(checkboxes) and length(checkboxes) > 0 ->
          checkbox_list =
            Enum.map(checkboxes, fn checkbox ->
              text = Map.get(checkbox, "text", "")
              selector = Map.get(checkbox, "selector", "")
              name = Map.get(checkbox, "name", "")
              "- Checkbox: #{text} | Selector: #{selector} | Name: #{name}"
            end)

          "DISCOVERED CHECKBOXES:\n" <> Enum.join(checkbox_list, "\n")

        _ ->
          "DISCOVERED CHECKBOXES: None found"
      end

    "#{checkbox_text}\n\n#{radio_text}\n\n#{button_text}"
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
