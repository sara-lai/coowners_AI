class MessagesController < ApplicationController
  SYSTEM_PROMPT = "You are an expert paralegal on property co-ownership"

  # maybe: the property can have its own speific system prompt potentially....
  # todo - ruby-openai gem instead -> stateless Assistants API instead of this

  def create
    @chat = current_user.chats.find(params[:chat_id])
    @property = @chat.property

    @message = Message.new(message_params)
    @message.chat = @chat
    @message.role = "user"

    if @message.save
      # changing to use more models/ more media types
      # @ruby_llm_chat = RubyLLM.chat
      # build_conversation_history
      # response = @ruby_llm_chat.with_instructions(instructions).ask(@message.content)

      if @message.file.attached?
        process_file(@message.file) # send question w/ file to the appropriate model
      else
        send_question # send question to the model
      end

      @chat.messages.create(role: "assistant", content: @response.content)
      @chat.generate_title_from_first_message


      respond_to do |format|
        # working on bug because i introduced a "launch chat" page, needs to move to show....
        if @chat.messages.count == 2 # hacky lol, means chat just started....
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
        # ^ so
        format.html { render "chats/show", status: :unprocessable_entity }
      end
    end
  end

  private

  def process_file(file)
    if file.content_type == "application/pdf"
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
end
