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
    # updating for openai assistants api:
    # this needs to setup a thread, and send over all property documents

    @property = Property.find(params[:property_id])

    #@chat = Chat.new(title: "Untitled")
    @chat = Chat.new(title: Chat::DEFAULT_TITLE)
    @chat.property = @property
    @chat.user = current_user

    # testing openai gem assisants API
    thread = openai_client.threads.create
    @chat.thread_id = thread["id"]

    # maybe should save it before all the document craziness

    if @chat.save
      setup_documents_for_thread

      redirect_to launch_path(@chat)
    else
      render "properties/launch"
    end
  end

  def destroy
    @chat = current_user.chats.find(params[:id])
    @chat.destroy
    redirect_to property_path(@chat.property) #hopefully stays on show page
  end

  private

  def setup_documents_for_thread
    # basically getting all pdfs [word support later?]
    file_ids = []
      @property.documents.each do |doc|
        next unless doc.content_type == "application/pdf"

        # GPT wants to put each file in a templfile to send to openAI?
        temp_file = Tempfile.new([doc.filename.to_s, ".pdf"])
        temp_file.binmode
        temp_file.write(doc.download)
        temp_file.rewind
        upload = openai_client.files.upload(parameters: { file: temp_file.path, purpose: "assistants" })

        file_ids << upload["id"]
        temp_file.unlink
      end

      unless file_ids.empty?
        attachments = file_ids.map { |id| { file_id: id, tools: [{ type: "file_search" }] } }
        openai_client.messages.create(
          thread_id: @chat.thread_id,
          parameters: {
            role: "assistant", # hides the message?
            content: "Initial property documents attached.",
            attachments: attachments
          }
        )
      end
  end

end
