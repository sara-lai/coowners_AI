class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_properties
  before_action :set_recent_chats

  # devise erroring out
  skip_before_action :authenticate_user!, if: :devise_controller?
  skip_before_action :set_properties, if: :devise_controller?
  skip_before_action :set_recent_chats, if: :devise_controller?

  protected

  def set_properties
    if current_user
      @all_properties = current_user.properties
    end
  end

  def set_recent_chats
    if current_user
      @recent_chats = Chat.where(property: current_user.properties).order(updated_at: :desc).limit(10)
    end
  end

  def after_sign_in_path_for(resource)
    puts "this is working - custom redirect after sign in"
    dashboard_path
  end


  def after_sign_up_path_for(resource)
     puts "this is working - custom redirect after sign up"
    dashboard_path
  end
end
