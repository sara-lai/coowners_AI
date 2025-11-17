class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  protected

  def after_sign_in_path_for(resource)
    puts "this is working - custom redirect after sign in"
    dashboard_path
  end


  def after_sign_up_path_for(resource)
     puts "this is working - custom redirect after sign up"
    dashboard_path
  end
end
