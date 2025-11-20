require "openai"

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY")
  config.log_errors = true
end

# or a controller .... this should put everywhere in app
def openai_client
  #@openai_client ||= OpenAI::Client.new(access_token: ENV["OPENAI_ACCESS_TOKEN"])
  @openai_client ||= OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"), log_errors: true)
end


SYSTEM_PROMPT = "You are an expert paralegal on property co-ownership"
# assistants initializer?
# supposed to only run this ONCE not every rails s (run in console?)
# assistant = openai_client.assistants.create(
#   parameters: {
#     model: "gpt-4o",  # Or "gpt-4-turbo" for better reasoning
#     name: "Property Paralegal",
#     instructions: SYSTEM_PROMPT,
#     tools: [{ type: "file_search" }]
#   }
# )

# can hardcode result of above
ASSISTANT_ID = "asst_H47hBIrsQt6nJ2DI3csvWfW5"#assistant["id"]
