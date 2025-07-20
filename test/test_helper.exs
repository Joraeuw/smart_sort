ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(SmartSort.Repo, :manual)

# Configure Mox for mocking
Mox.defmock(SmartSort.GmailAccountHandler, for: SmartSort.GmailAccountHandlerBehaviour)
