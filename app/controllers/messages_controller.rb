class MessagesController < ApplicationController
  SYSTEM_PROMPT = "You are an expert paralegal on property co-ownership"

  # maybe: the property can have its own speific system prompt potentially....

  def create
    @chat = current_user.chats.find(params[:chat_id])
    @property = @chat.property

    @message = Message.new(message_params)
    @message.chat = @chat
    @message.role = "user"

    if @message.save
      # todo - ruby-openai gem instead -> stateless Assistants API instead of this
      @ruby_llm_chat = RubyLLM.chat
      build_conversation_history
      response = @ruby_llm_chat.with_instructions(instructions).ask(@message.content)
      @chat.messages.create(role: "assistant", content: response.content)

      @chat.generate_title_from_first_message

      respond_to do |format|
        format.turbo_stream # renders `app/views/messages/create.turbo_stream.erb`
        format.html { redirect_to chat_path(@chat) }
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

  def build_conversation_history
    @chat.messages.each do |message|
      @ruby_llm_chat.add_message(message)
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
    params.require(:message).permit(:content)
  end
end
