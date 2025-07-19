defmodule SmartSort.Helpers.PersistEnv do
  def project_id do
    get(:smart_sort, [:smart_sort, :google_api])[:project_id]
  end

  def google_client_id do
    ueberauth()[:client_id]
  end

  def google_client_secret do
    ueberauth()[:client_secret]
  end

  defp ueberauth do
    Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)
  end

  defp get(name, level) do
    :persistent_term.get(name, :not_found)
    |> case do
      :not_found -> persist_env(name, level)
      val -> val
    end
  end

  defp persist_env(name, level) do
    val = Kernel.apply(Application, :get_env, level)
    :persistent_term.put(name, val)
    val
  end
end
