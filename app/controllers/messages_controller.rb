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
        if @chat.messages.where(role: "user").count == 1 # bc launch page handle first message differently
          process_with_openai_gem
          format.html { redirect_to chat_path(@chat) }
          format.turbo_stream { redirect_to chat_path(@chat) } # full redirect
        else
          # immediately creaet so can stream chunks
          @assistant_message = @chat.messages.create!(role: "assistant", content: "")
          process_with_openai_gem
          format.turbo_stream {}
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

    if @chat.messages.where(role: "user").count == 1  # handle chat launch differently (nc differetn page)
      run = openai_client.runs.create(
        thread_id: thread_id,
        parameters: {
          assistant_id: ASSISTANT_ID, # from initializer
          additional_instructions: property_context
        }
      )
      run_id = run["id"]

      status = nil
      until %w[completed failed].include?(status)
        sleep 1
        run_status = openai_client.runs.retrieve(thread_id: thread_id, id: run_id)
        status = run_status["status"]
      end

      if status == "completed"
        messages = openai_client.messages.list(thread_id: thread_id, parameters: { order: "desc", limit: 1 })
        assistant_content = messages["data"].first.dig("content", 0, "text", "value")
        @chat.messages.create!(role: "assistant", content: assistant_content)  # Appends via broadcast (but redirect happens anyway)
      else
        raise "Run failed: #{run_status['error']}"
      end
    else
      # per lecture
      full_content = ""
      stream_assistant_response(thread_id) do |chunk|
        next if chunk.blank?

        full_content += chunk
        broadcast_replace(@assistant_message.tap { |m| m.content = full_content })  # In-memory update for broadcast; no save yet
      end

      # Final save (like lecture's update)
      @assistant_message.update!(content: full_content)
    end
  end

   # streaming: bit different from lectures .... gem wants this approach with the proc
  def stream_assistant_response(thread_id, &block)
    openai_client.runs.create(
      thread_id: thread_id,
      parameters: {
        assistant_id: ASSISTANT_ID,
        additional_instructions: property_context,
        stream: proc do |chunk, _bytesize|
          if chunk["object"] == "thread.message.delta"
            delta = chunk.dig("delta", "content", 0, "text", "value")
            block.call(delta) if delta
          elsif chunk["object"] == "thread.run.failed"
            raise "Run failed: #{chunk.dig('last_error')}"
          end
        end
      }
    )
  end

  def broadcast_replace(message)
    Turbo::StreamsChannel.broadcast_replace_to @chat, target: helpers.dom_id(message), partial: "messages/message", locals: { message: message }
  end

end
