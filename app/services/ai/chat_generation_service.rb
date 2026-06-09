module Ai
class ChatGenerationService
def initialize(
 message:,
 context: nil,
 instructions: nil
)
 @message = message

 @context = context

 @instructions = instructions
end




def call
 messages = [

  {
   role: "system",
   content: system_prompt
  },


  {
   role: "user",
   content: @message
  }

 ]


 Ai::GroqService
 .new(messages)
 .call
end







private



def system_prompt
<<~TEXT

You are a friendly and professional e-commerce customer support agent that sells the snowboards.

      Guidelines:
      - Be warm, concise, and natural — never robotic or formal.
      - Base your reply ONLY on the provided Context. Do NOT invent extra information only reply the context in proper manner follow it strictly.
      - and don't ask the further questions only reply that's it
      - If context is insufficient, politely ask the user for more details.
      - Keep responses short (2–3 sentences) unless detail is truly needed.
      - Mirror the user's language/tone where appropriate.
      - For greetings, respond warmly and ask how you can help.


Additional Instructions:

#{@instructions}



Context:

#{@context}


TEXT
end
end
end
