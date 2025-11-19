class ChatsController < ApplicationController

  def show
    @chat    = current_user.chats.find(params[:id])
    @message = Message.new
  end

  def launch
    @chat    = current_user.chats.find(params[:id])
    @message = Message.new
  end

  def create
    @property = Property.find(params[:property_id])

    #@chat = Chat.new(title: "Untitled")
    @chat = Chat.new(title: Chat::DEFAULT_TITLE)
    @chat.property = @property
    @chat.user = current_user

    if @chat.save
      redirect_to launch_path(@chat)
    else
      render "properties/launch"
    end
  end

end
