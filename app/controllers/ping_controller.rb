# app/controllers/ping_controller.rb
class PingController < ActionController::Base
  def index
    render plain: "pong"
  end
end
