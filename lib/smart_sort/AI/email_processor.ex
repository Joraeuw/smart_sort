defmodule SmartSort.AI.EmailProcessor do
  require Logger

  alias SmartSort.Accounts.Email

  defmodule EmailResponse do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    ## Field Descriptions:
    - summary: A clear, concise summary of the email (10-500 characters)
    - confidence_score: Your confidence in this analysis (0.0 to 1.0, where 1.0 is completely confident)
    - category_id: The ID of the most appropriate category for this email (must be from the provided list)
    """

    @primary_key false
    embedded_schema do
      field :summary, :string
      field :category_id, :integer
      field :confidence_score, :float
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> Ecto.Changeset.validate_number(:confidence_score,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
    end
  end

  def process_email(email, categories) do
    with {:ok,
          %EmailResponse{
            summary: summary,
            category_id: category_id,
            confidence_score: confidence_score
          }} <- do_perform(email, categories),
         {:ok, _updated_email} <-
           Email.assign_to_category(email, category_id, summary, confidence_score) do
      {:ok, %{category_id: category_id, summary: summary}}
    else
      {:error, reason} = error ->
        Logger.error("[EMAIL_PROCESSOR] Failed to process email: #{inspect(reason)}")
        error
    end
  end

  def do_perform(email, categories) do
    Instructor.chat_completion(
      model: "gpt-4o-mini",
      response_model: EmailResponse,
      max_retries: 3,
      messages: [
        %{
          role: "user",
          content: """
          Your purpose is to summarize emails and sort them into one of the provided categories and their description.

          Available categories - choose the most appropriate category ID:
          Category format:
          ID. Category - Description

          <categories>
            #{Enum.map_join(categories, "\n", &"#{&1.id}. #{&1.name} - #{&1.description}")}
          </categories>

          Summarize the following email:

          <email>
            #{email.body}
          </email>
          """
        }
      ]
    )
  end
end
