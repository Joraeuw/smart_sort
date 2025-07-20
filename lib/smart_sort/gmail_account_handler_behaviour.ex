defmodule SmartSort.GmailAccountHandlerBehaviour do
  @moduledoc """
  Behaviour for GmailAccountHandler to enable mocking in tests.
  """

  @callback fetch_email_changes(SmartSort.Accounts.ConnectedAccount.t(), String.t()) ::
              {:ok, any()} | {:error, any()}

  @callback start_gmail_notifications(SmartSort.Accounts.ConnectedAccount.t()) ::
              {:ok, map()} | {:error, any()}

  @callback stop_gmail_notifications(SmartSort.Accounts.ConnectedAccount.t()) ::
              :ok | {:error, any()}

  @callback start_all_gmail_notifications() ::
              {:ok, list()} | {:error, any()}

  @callback refresh_access_token(SmartSort.Accounts.ConnectedAccount.t()) ::
              {:ok, SmartSort.Accounts.ConnectedAccount.t(), String.t()} | {:error, any()}
end
