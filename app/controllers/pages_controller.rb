class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]
  skip_before_action :set_properties      # Skip to avoid nil error
  skip_before_action :set_recent_chats

  layout "landing"

  def home
  end
end
