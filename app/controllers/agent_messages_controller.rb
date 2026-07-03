class AgentMessagesController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_cors_headers

  def index
    conversation = Conversation.find_by(session_id: params[:session_id])
    return render json: { messages: [] } unless conversation

    # ID-based pagination avoids timestamp-precision re-delivery loops.
    after_id = params[:after_id].to_i

    messages = conversation.messages
                 .where(role: "agent")
                 .where("id > ?", after_id)
                 .order(:id)

    render json: {
      messages: messages.map { |m|
        { id: m.id, content: m.content }
      }
    }
  end

  def options
    head :ok
  end

  private

  def set_cors_headers
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] =
    "Content-Type, Authorization, Accept, Origin, X-Requested-With, ngrok-skip-browser-warning"

  response.headers["Access-Control-Max-Age"] = "86400"
end
end
