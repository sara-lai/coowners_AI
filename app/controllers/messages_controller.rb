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
      ruby_llm_chat = RubyLLM.chat
      response = ruby_llm_chat.with_instructions(instructions).ask(@message.content)
      Message.create(role: "assistant", content: response.content, chat: @chat)

      @chat.generate_title_from_first_message

      redirect_to chat_messages_path(@chat)
    else
      render "chats/show", status: :unprocessable_entity
    end
  end

  private

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
