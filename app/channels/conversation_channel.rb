class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation =
      if params[:conversation_id].present?
        Conversation.find_by(id: params[:conversation_id])
      elsif params[:session_id].present?
        Conversation.find_by(session_id: params[:session_id])
      end

    if conversation
      stream_from "conversation_#{conversation.id}"
    else
      reject
    end
  end

  def unsubscribed
    stop_all_streams
  end
end
