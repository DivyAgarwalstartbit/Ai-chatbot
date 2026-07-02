module Ai
  module LangfuseContext
    def self.set(session_id:, user_id: nil, shop: nil)
      Thread.current[:lf_session_id] = session_id
      Thread.current[:lf_user_id]    = user_id
      Thread.current[:lf_shop]       = shop
    end

    def self.session_id = Thread.current[:lf_session_id]
    def self.user_id    = Thread.current[:lf_user_id]
    def self.shop       = Thread.current[:lf_shop]

    def self.clear
      Thread.current[:lf_session_id] = nil
      Thread.current[:lf_user_id]    = nil
      Thread.current[:lf_shop]       = nil
    end
  end
end
