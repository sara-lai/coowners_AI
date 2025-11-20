class AddThreadIdToChats < ActiveRecord::Migration[7.1]
  def change
    add_column :chats, :thread_id, :string
  end
end
