class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :set_properties

  protected

  def set_properties
    # umm..... need to only get properties for current_user though?
    @properties = Property.all
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
