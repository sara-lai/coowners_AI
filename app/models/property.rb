class Property < ApplicationRecord
  belongs_to :user

  has_many :chats, dependent: :destroy

  has_many_attached :documents
end
