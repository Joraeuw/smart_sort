defmodule SmartSort.GmailAccountHandlerMock do
  @moduledoc """
  Mock for GmailAccountHandler for testing
  """
  @behaviour SmartSort.GmailAccountHandler

  def start_gmail_notifications(connected_account) do
    Mox.mock(__MODULE__, :start_gmail_notifications, [connected_account])
  end
end

defmodule SmartSort.Jobs.RefreshGoogleTokensMock do
  @moduledoc """
  Mock for RefreshGoogleTokens job for testing
  """

  def schedule(connected_account) do
    Mox.mock(__MODULE__, :schedule, [connected_account])
  end
end

defmodule SmartSort.Jobs.RenewGmailWatchesMock do
  @moduledoc """
  Mock for RenewGmailWatches job for testing
  """

  def schedule(connected_account) do
    Mox.mock(__MODULE__, :schedule, [connected_account])
  end
end

defmodule SmartSort.Mocks.InstructorMock do
  @moduledoc """
  Mock for Instructor module used in AI tests.
  """

  def chat_completion(params) do
    # Default mock implementation
    {:ok, %{response: "Mock response"}}
  end
end

defmodule SmartSort.Mocks.EmailAnalysisAgentMock do
  @moduledoc """
  Mock for EmailAnalysisAgent module used in AI tests.
  """

  def analyze_email(email) do
    # Default mock implementation
    {:ok,
     %{
       confidence_score: 0.5,
       unsubscribe_url: "https://example.com/unsubscribe",
       user_email: "user@example.com",
       link_search_text: "unsubscribe",
       link_context: "Click here to unsubscribe",
       reasoning: "Mock analysis result"
     }}
  end
end

defmodule SmartSort.Mocks.TextExtractorMock do
  @moduledoc """
  Mock for TextExtractor module used in AI tests.
  """

  def extract_unsubscribe_info(email) do
    # Default mock implementation
    {:ok,
     %{
       confidence_score: 0.5,
       unsubscribe_url: "https://example.com/unsubscribe",
       user_email: "user@example.com",
       link_search_text: "unsubscribe",
       link_context: "Click here to unsubscribe",
       reasoning: "Mock extraction result"
     }}
  end

  def attempt_text_extraction(body_content, user_email) do
    # Default mock implementation
    {:ok,
     %{
       confidence_score: 0.5,
       unsubscribe_url: "https://example.com/unsubscribe",
       user_email: user_email,
       link_search_text: "unsubscribe",
       link_context: "Click here to unsubscribe",
       reasoning: "Mock text extraction result"
     }}
  end

  def valid_unsubscribe_url?(url) do
    # Default mock implementation
    String.contains?(url, "unsubscribe") || String.contains?(url, "opt-out") ||
      String.contains?(url, "remove")
  end

  def clean_url(url) do
    # Default mock implementation
    url |> String.trim() |> ensure_protocol()
  end

  def extract_footer_section(body_content) do
    # Default mock implementation
    String.slice(body_content, -10_000, 10_000)
  end

  def extract_search_text(body_content, url) do
    # Default mock implementation
    "unsubscribe"
  end

  def extract_context(body_content, url) do
    # Default mock implementation
    "Click here to unsubscribe"
  end

  def calculate_confidence(_url_pattern, url) do
    # Default mock implementation
    if url && String.length(url) > 0, do: 0.8, else: 0.0
  end

  def build_reasoning(_url_pattern, url) do
    # Default mock implementation
    if url && String.length(url) > 0 do
      "Found unsubscribe URL: #{url}"
    else
      "No unsubscribe URL found"
    end
  end

  defp ensure_protocol(url) do
    if String.starts_with?(url, "http") do
      url
    else
      "https://#{url}"
    end
  end
end

defmodule SmartSort.Mocks.WallabyBrowserMock do
  @moduledoc """
  Mock for Wallaby.Browser module used in form tools tests.
  """

  def click(session, element) do
    # Default mock implementation
    {:ok, session}
  end

  def fill_in(session, element, with: value) do
    # Default mock implementation
    {:ok, session}
  end

  def execute_script(session, script) do
    # Default mock implementation
    {:ok, session}
  end

  def all(session, query) do
    # Default mock implementation
    [%{text: "Button 1"}, %{text: "Button 2"}]
  end

  def visit(session, url) do
    # Default mock implementation
    session
  end

  def take_screenshot(session, name: name) do
    # Default mock implementation
    session
  end
end

defmodule SmartSort.Mocks.WallabyQueryMock do
  @moduledoc """
  Mock for Wallaby.Query module used in form tools tests.
  """

  def css(selector) do
    # Default mock implementation
    %{selector: selector}
  end

  def text(text) do
    # Default mock implementation
    %{text: text}
  end
end

defmodule SmartSort.Mocks.WallabyMock do
  @moduledoc """
  Mock for Wallaby module used in screenshot tests.
  """

  def start_session do
    # Default mock implementation
    {:ok, %{session: "test_session"}}
  end

  def end_session(session) do
    # Default mock implementation
    :ok
  end
end

defmodule SmartSort.Mocks.FileMock do
  @moduledoc """
  Mock for File module used in screenshot tests.
  """

  def exists?(path) do
    # Default mock implementation
    true
  end

  def mkdir_p(path) do
    # Default mock implementation
    {:ok, path}
  end

  def rm(path) do
    # Default mock implementation
    :ok
  end
end

defmodule SmartSort.Mocks.UnsubscribeReactorMock do
  @moduledoc """
  Mock for UnsubscribeReactor module used in service tests.
  """

  def execute_unsubscribe(email, user_email) do
    # Default mock implementation
    {:ok,
     %{
       success: true,
       method: "form_automation",
       details: "Successfully unsubscribed"
     }}
  end
end

defmodule SmartSort.Mocks.ReactorMock do
  @moduledoc """
  Mock for Reactor module used in reactor tests.
  """

  def run(reactor, inputs) do
    # Default mock implementation
    {:ok,
     %{
       success: true,
       method: "form_automation",
       details: "Successfully unsubscribed"
     }}
  end
end

defmodule SmartSort.Mocks.ExtractUnsubscribeInfoStepMock do
  @moduledoc """
  Mock for ExtractUnsubscribeInfoStep module used in reactor tests.
  """

  def run(arguments, context, options) do
    # Default mock implementation
    {:ok,
     %{
       unsubscribe_url: "https://example.com/unsubscribe",
       user_email: "user@example.com",
       link_search_text: "unsubscribe",
       link_context: "Click here to unsubscribe",
       confidence_score: 0.8,
       reasoning: "Found unsubscribe link",
       extraction_method: "ai_analysis",
       original_email: arguments.email
     }}
  end

  def compensate(reason, arguments, context, options) do
    # Default mock implementation
    :ok
  end
end

defmodule SmartSort.Mocks.AnalyzeUnsubscribePageStepMock do
  @moduledoc """
  Mock for AnalyzeUnsubscribePageStep module used in reactor tests.
  """

  def run(arguments, context, options) do
    # Default mock implementation
    {:ok,
     %{
       form_data: %{
         fields: [
           %{name: "email", type: "text", selector: "input[name='email']"},
           %{name: "submit", type: "submit", selector: "button[type='submit']"}
         ],
         method: "POST",
         action: "https://example.com/unsubscribe"
       }
     }}
  end

  def compensate(reason, arguments, context, options) do
    # Default mock implementation
    :ok
  end
end

defmodule SmartSort.Mocks.ExecuteFormAutomationStepMock do
  @moduledoc """
  Mock for ExecuteFormAutomationStep module used in reactor tests.
  """

  def run(arguments, context, options) do
    # Default mock implementation
    {:ok,
     %{
       success: true,
       method: "form_automation",
       details: "Successfully filled and submitted form"
     }}
  end

  def compensate(reason, arguments, context, options) do
    # Default mock implementation
    :ok
  end
end

defmodule SmartSort.Mocks.VerifyUnsubscribeSuccessStepMock do
  @moduledoc """
  Mock for VerifyUnsubscribeSuccessStep module used in reactor tests.
  """

  def run(arguments, context, options) do
    # Default mock implementation
    {:ok,
     %{
       success: true,
       method: "form_automation",
       details: "Successfully unsubscribed"
     }}
  end

  def compensate(reason, arguments, context, options) do
    # Default mock implementation
    :ok
  end
end
