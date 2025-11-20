class MessagesController < ApplicationController
  SYSTEM_PROMPT = "You are an expert paralegal on property co-ownership"

  #assistants API.....
  # using ruby-openai, not openai-ruby lol
  #https://github.com/alexrudall/ruby-openai?tab=readme-ov-file#assistants
  #https://github.com/openai/openai-ruby

  def create
    @chat = current_user.chats.find(params[:chat_id])
    @property = @chat.property

    @message = Message.new(message_params)
    @message.chat = @chat
    @message.role = "user"

    if @message.save

      # the heavy lifter, see method below for documentation....
      process_with_openai_gem

      @chat.generate_title_from_first_message

      # not using thsi with assistants api:
      # if @message.file.attached?
      #   process_file(@message.file) # send question w/ file to the appropriate model
      # else
      #   send_question # send question to the model
      # end
      # @chat.messages.create(role: "assistant", content: @response.content)
      # @chat.generate_title_from_first_message

      respond_to do |format|
        if @chat.messages.count == 2 # hacky lol, means chat just started, because of "launch" page, need to redirect
          format.html { redirect_to chat_path(@chat) }
          format.turbo_stream { redirect_to chat_path(@chat) } # full redirect
        else
          format.turbo_stream
          format.html { redirect_to chat_path(@chat) }
        end
      end

    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_message", partial: "messages/form", locals: { chat: @chat, message: @message }) }
        format.html { render "chats/show", status: :unprocessable_entity }
      end
    end
  end

  private

  def process_file(file)
    # basically not using anymore.... keeping as reference
    if file.content_type == "application/pdf"
      # testing the openAI assistants API.....
      send_question(model: "gemini-2.0-flash", with: { pdf: @message.file.url })
    elsif file.image?
      send_question(model: "gpt-4o", with: { image: @message.file.url })
    elsif file.audio?
      temp_file = Tempfile.new(["audio", File.extname(@message.file.filename.to_s)])

      URI.open(@message.file.url) do |remote_file|
        IO.copy_stream(remote_file, temp_file)
      end

      send_question(model: "gpt-4o-audio-preview", with: { audio: temp_file.path })
      temp_file.unlink
    end
  end

  def send_question(model: "gpt-4.1-nano", with: {})
    @ruby_llm_chat = RubyLLM.chat(model: model)
    build_conversation_history
    @ruby_llm_chat.with_instructions(instructions)
    @response = @ruby_llm_chat.ask(@message.content, with: with)
  end

  def build_conversation_history
    @chat.messages.each do |message|
      puts "\n\n\n hello!!! why isnt this working \n\n"
      puts message
      # GPT says -> The error "undefined method fetch' for an instance of Message" occurs because @ruby_llm_chat.add_message(message)is passing a fullMessageobject (an ActiveRecord model) toadd_message, but the method likely expects a hash or structured data
      @ruby_llm_chat.add_message({ role: message.role, content: message.content })
    end
  end

  def property_context
    # todo swap out with documents .....
    "Here is the context of the property: #{@property.name}."
  end

  def instructions
    [SYSTEM_PROMPT, property_context].compact.join("\n\n")
  end

  def message_params
    params.require(:message).permit(:content, :file)
  end


  # using the assistants API
  # main difference w/ rubyllm is it is stateful / uses a thread_id, you dont copy everything every time
  # main things:
  # openai_client.files.upload
  # openai_client.messages.create
  # openai_client.runs.create
  # openai_client.runs.retrieve (it recommends "polling" to retreive response)

  def process_with_openai_gem

    thread_id = @chat.thread_id

    # handling attachments
    file_id = nil
    if @message.file.attached?
      if @message.file.content_type == "application/pdf"

        # GPT says create temp_file before uploading the pdf
        temp_file = Tempfile.new(["document", ".pdf"])
        temp_file.binmode
        temp_file.write(@message.file.download)
        temp_file.rewind

        response = openai_client.files.upload(parameters: { file: temp_file.path, purpose: "assistants" })
        file_id = response["id"]
        temp_file.unlink
      elsif @message.file.image?
        # todo
      end
    end

    # building the client.messages.create (with attachment, if any)
    message_params = { role: "user", content: @message.content }
    if file_id
      message_params[:attachments] = [{ file_id: file_id, tools: [{ type: "file_search" }] }]
    end
    openai_client.messages.create(thread_id: thread_id, parameters: message_params)


    # running the assistant & "polling" to get result
    run = openai_client.runs.create(
      thread_id: thread_id,
      parameters: {
        assistant_id: ASSISTANT_ID, # from initializer
        additional_instructions: property_context # necessary? only sending property name lol
      }
    )
    run_id = run["id"]

    status = nil
    until %w[completed failed].include?(status)
      # todo - no idea how long requests might take [if scanning many documents]..... maybe source of errors, Heroku?
      sleep 1
      run_status = openai_client.runs.retrieve(thread_id: thread_id, id: run_id)
      status = run_status["status"]
    end

    if status == "completed"
      # get latest message.... odd syntax
      # dig -> "safely digs into the nested structure without errors if keys are missing"
      messages = openai_client.messages.list(thread_id: thread_id, parameters: { order: "desc", limit: 1 })
      assistant_content = messages["data"].first.dig("content", 0, "text", "value")

      @chat.messages.create!(role: "assistant", content: assistant_content)
    else
      raise "Run failed: #{run_status['error']}"
    end

  end
end
