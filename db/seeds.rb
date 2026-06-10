# frozen_string_literal: true

# Idempotent seed data for development / testing.
# Run with: bin/rails db:seed

shop = Shop.first
abort "No shop found. Install the app first, then run db:seed." unless shop

puts "Seeding conversations for #{shop.shopify_domain}..."

# ── Helpers ──────────────────────────────────────────────────────────────────

def rand_time(days_ago_min:, days_ago_max:)
  rand(days_ago_min..days_ago_max).days.ago - rand(0..23).hours - rand(0..59).minutes
end

GREETINGS = [
  "Hi, I need help with my order.",
  "Hello! I have a question about shipping.",
  "Hey, is this product still available?",
  "Hi there! I was wondering about your return policy.",
  "Can you help me find the right size?"
].freeze

EXCHANGES = [
  [
    { role: "customer",  content: "Hi, I placed an order 3 days ago and haven't received a tracking number yet." },
    { role: "assistant", content: "Hi! I'm sorry to hear that. Let me look into your order. Could you provide your order number?" },
    { role: "customer",  content: "It's #10234." },
    { role: "assistant", content: "Thank you! Order #10234 is currently being prepared for shipment. You should receive a tracking email within 24 hours." },
    { role: "customer",  content: "Great, thanks!" },
    { role: "assistant", content: "You're welcome! Is there anything else I can help you with?" }
  ],
  [
    { role: "customer",  content: "Do you ship internationally?" },
    { role: "assistant", content: "Yes, we ship to over 50 countries! Shipping rates and delivery times vary by destination." },
    { role: "customer",  content: "How long does shipping to Canada take?" },
    { role: "assistant", content: "Standard shipping to Canada typically takes 7–12 business days. Expedited options are available at checkout." }
  ],
  [
    { role: "customer",  content: "I want to return an item I bought last week." },
    { role: "assistant", content: "Of course! We accept returns within 30 days of purchase. Is the item unused and in its original packaging?" },
    { role: "customer",  content: "Yes, I never opened it." },
    { role: "assistant", content: "Perfect. I'll email you a prepaid return label. You should receive it within a few minutes." },
    { role: "customer",  content: "Wonderful, thank you so much." },
    { role: "system",    content: "Return label sent via email." }
  ],
  [
    { role: "customer",  content: "What sizes do you carry for the Classic Tee?" },
    { role: "assistant", content: "The Classic Tee is available in XS, S, M, L, XL, and XXL." },
    { role: "customer",  content: "I'm usually between M and L. Which would you recommend?" },
    { role: "assistant", content: "If you prefer a relaxed fit, go with L. For a more fitted look, M is the better choice." }
  ],
  [
    { role: "customer",  content: "Is the leather wallet available in brown?" },
    { role: "assistant", content: "Yes! The leather wallet comes in black, brown, and tan." },
    { role: "customer",  content: "How long does it take to ship?" },
    { role: "assistant", content: "Standard shipping takes 3–5 business days. Express options are available at checkout." },
    { role: "customer",  content: "I'll go ahead and order. Thanks!" }
  ],
  [
    { role: "customer",  content: "My package arrived damaged. What should I do?" },
    { role: "assistant", content: "I'm really sorry to hear that! Please take a photo of the damaged item and packaging, then reply here or email us at support@store.com." },
    { role: "customer",  content: "I sent the photos." },
    { role: "assistant", content: "Thank you! Our team will review and arrange a replacement or refund within 1 business day." },
    { role: "system",    content: "Damage claim #DC-4421 opened automatically." }
  ],
  [
    { role: "customer",  content: "Do you have a loyalty program?" },
    { role: "assistant", content: "Yes! You earn 1 point per dollar spent. Every 100 points = $5 off your next order." },
    { role: "customer",  content: "How do I sign up?" },
    { role: "assistant", content: "Just create an account on our website — you're automatically enrolled." }
  ],
  [
    { role: "customer",  content: "Can I change the shipping address on my order?" },
    { role: "assistant", content: "If your order hasn't shipped yet, we can update the address. What's your order number?" },
    { role: "customer",  content: "#10891" },
    { role: "assistant", content: "Order #10891 hasn't shipped yet. What's the new address?" },
    { role: "customer",  content: "123 Maple Street, Toronto, ON, M5V 2T6, Canada" },
    { role: "assistant", content: "Done! I've updated the shipping address. You'll receive a confirmation email shortly." }
  ]
].freeze

CUSTOMERS_DATA = [
  { first_name: "Sarah",   last_name: "Mitchell",  email: "sarah.mitchell@example.com",  phone: "+1-555-0101", shopify_customer_id: 1001 },
  { first_name: "James",   last_name: "Okafor",    email: "james.okafor@example.com",    phone: "+1-555-0102", shopify_customer_id: 1002 },
  { first_name: "Priya",   last_name: "Sharma",    email: "priya.sharma@example.com",    phone: nil,           shopify_customer_id: 1003 },
  { first_name: "Carlos",  last_name: "Reyes",     email: "carlos.reyes@example.com",    phone: "+1-555-0104", shopify_customer_id: nil  },
  { first_name: "Emma",    last_name: "Johansson", email: "emma.johansson@example.com",  phone: "+1-555-0105", shopify_customer_id: 1005 },
  { first_name: "Liam",    last_name: "Chen",      email: nil,                           phone: nil,           shopify_customer_id: nil  },
  { first_name: "Amara",   last_name: "Nwosu",     email: "amara.nwosu@example.com",     phone: "+1-555-0107", shopify_customer_id: 1007 },
  { first_name: "Oliver",  last_name: "Müller",    email: "oliver.muller@example.com",   phone: nil,           shopify_customer_id: 1008 }
].freeze

STATUSES  = %w[open open open closed resolved].freeze
PAGE_URLS = [
  "/products/classic-tee",
  "/products/leather-wallet",
  "/collections/accessories",
  "/pages/shipping-policy",
  nil
].freeze

# ── Create customers ──────────────────────────────────────────────────────────

customers = CUSTOMERS_DATA.map do |attrs|
  Customer.find_or_create_by!(shop: shop, email: attrs[:email] || nil, visitor_id: attrs[:email].present? ? nil : SecureRandom.hex(6)) do |c|
    c.first_name          = attrs[:first_name]
    c.last_name           = attrs[:last_name]
    c.phone               = attrs[:phone]
    c.shopify_customer_id = attrs[:shopify_customer_id]
  end
end

puts "  #{customers.size} customers ready."

# ── Create conversations + messages ──────────────────────────────────────────

EXCHANGES.each_with_index do |messages, i|
  customer   = customers[i % customers.size]
  started    = rand_time(days_ago_min: 1, days_ago_max: 30)
  last_at    = started + messages.size.minutes
  status     = STATUSES.sample
  page_url   = PAGE_URLS.sample

  # Deterministic UUIDs so re-running seeds stays idempotent
  session_id = "00000000-seed-0000-0000-#{format('%012d', i + 1)}"

  conv = Conversation.find_or_create_by!(
    shop:       shop,
    customer:   customer,
    session_id: session_id
  ) do |c|
    c.status          = status
    c.started_at      = started
    c.ended_at        = status == "open" ? nil : last_at
    c.last_message_at = last_at
    c.page_url        = page_url
    c.reviewed_at     = status == "open" ? nil : last_at
  end

  next unless conv.messages.empty?

  messages.each_with_index do |msg, j|
    conv.messages.create!(
      role:       msg[:role],
      content:    msg[:content],
      created_at: started + j.minutes,
      updated_at: started + j.minutes,
      metadata:   msg[:role] == "assistant" ? { model: "gpt-4o", tokens: rand(50..400) } : nil
    )
  end

  puts "  Conversation #{i + 1}: #{customer.first_name} #{customer.last_name} — #{status} — #{messages.size} messages"
end

# ── Anonymous conversation ────────────────────────────────────────────────────

anon_conv = Conversation.find_or_create_by!(shop: shop, session_id: "00000000-seed-0000-0000-anon00000000") do |c|
  c.customer        = nil
  c.status          = "open"
  c.started_at      = 2.hours.ago
  c.last_message_at = 1.hour.ago
  c.page_url        = "/products/classic-tee"
end

if anon_conv.messages.empty?
  [
    { role: "customer",  content: "Is the Classic Tee available in XL?", offset: 0 },
    { role: "assistant", content: "Yes, the Classic Tee is available in XL!", offset: 1 }
  ].each do |m|
    anon_conv.messages.create!(
      role: m[:role], content: m[:content],
      created_at: anon_conv.started_at + m[:offset].minutes,
      updated_at: anon_conv.started_at + m[:offset].minutes
    )
  end
  puts "  Anonymous conversation created — 2 messages"
end

# ── Seed tickets ─────────────────────────────────────────────────────────────

puts "\nSeeding tickets..."

# Grab a few seeded conversations to link tickets to
seeded_convs = Conversation.where(shop: shop).order(:created_at).limit(5).to_a

TICKET_SEEDS = [
  {
    subject: "Damaged item received — order #10234",
    issue: "Customer reports the leather wallet arrived with a cracked corner. Photos were shared. Requesting replacement or refund.",
    source: "customer_requested_human",
    status: "open",
    customer_index: 0,
    conversation_index: 5
  },
  {
    subject: "Refund request for Classic Tee (wrong size)",
    issue: "AI could not process the refund directly. Customer ordered M but needs L. Item is unused with tags attached.",
    source: "ai_escalation",
    status: "in_progress",
    customer_index: 1,
    conversation_index: 3
  },
  {
    subject: "Shipping dispute — package marked delivered but not received",
    issue: "Tracking shows delivered 3 days ago to the listed address. Customer says they haven't received it. May need carrier investigation.",
    source: "customer_requested_human",
    status: "open",
    customer_index: 2,
    conversation_index: 0
  },
  {
    subject: "Order #10891 — address update failed",
    issue: "Customer requested address change but order may have already shipped. Needs manual verification with fulfillment.",
    source: "ai_escalation",
    status: "resolved",
    customer_index: 7,
    conversation_index: 7
  },
  {
    subject: "International shipping — customs delay inquiry",
    issue: "Customer's package to Canada has been stuck in customs for 2 weeks. AI could not provide specific customs resolution steps.",
    source: "ai_escalation",
    status: "closed",
    customer_index: 4,
    conversation_index: 1
  },
  {
    subject: "Loyalty points not applied to order",
    issue: "Customer says they had 350 points but they were not applied at checkout. Requires manual review of loyalty account.",
    source: "customer_requested_human",
    status: "open",
    customer_index: 6,
    conversation_index: nil
  }
].freeze

TICKET_SEEDS.each do |attrs|
  customer = customers[attrs[:customer_index]]
  conv     = attrs[:conversation_index] ? seeded_convs[attrs[:conversation_index]] : nil

  Ticket.find_or_create_by!(shop: shop, subject: attrs[:subject]) do |t|
    t.issue           = attrs[:issue]
    t.source          = attrs[:source]
    t.status          = attrs[:status]
    t.customer        = customer
    t.conversation    = conv
    t.created_at      = rand(1..20).days.ago
    t.updated_at      = t.created_at
  end

  puts "  Ticket: #{attrs[:subject].truncate(55)} — #{attrs[:status]}"
end

puts "\nDone. #{Conversation.where(shop: shop).count} conversations, #{Message.joins(:conversation).where(conversations: { shop: shop }).count} messages, #{Ticket.where(shop: shop).count} tickets total."
