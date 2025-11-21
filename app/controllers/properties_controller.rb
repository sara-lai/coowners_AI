class PropertiesController < ApplicationController
  before_action :authenticate_user!

  def index
    # @properties = Property.all
    @properties = current_user.properties.all
  end

  def show
    @property = current_user.properties.find(params[:id])
    @chats = @property.chats.order(created_at: :desc)
  end

  def new
    @property = current_user.properties.new
  end

  def edit
  end

  def create
     @property = current_user.properties.new(property_params)

     if @property.save
      # test this x100
      if params[:property][:documents].present? # lookup references for active storage documents....
        @property.documents.attach(params[:property][:documents])
      end

      redirect_to dashboard_path, notice: "Property created successfully!"
    else
      render :new
    end
  end

  def update
    @property = current_user.properties.find(params[:id])
    if params[:property][:documents].present?
      @property.documents.attach(params[:property][:documents])
      redirect_to property_path(@property), notice: "Successfully added."
    end
  end

  def destroy
  end

  private

  def property_params
    params.require(:property).permit(:name, :address, :jurisdiction, :photo, documents: [])
  end
end
