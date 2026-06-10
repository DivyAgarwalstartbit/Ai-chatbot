(function () {
  console.log("AI CHAT LOADED", window.AI_WIDGET);

  const root = document.getElementById("ai-support-widget");

  root.innerHTML = `

<!-- FLOAT BUTTON -->
<button class="ai-floating-btn" aria-label="Open chat">
  💬
  <span class="badge">1</span>
</button>

<!-- HOME SCREEN -->
<div class="ai-widget">

  <div class="orange-section">
    <button class="close-btn" aria-label="Close">✕</button>
    <h1>Hi there 👋</h1>
    <p>Ask us anything — we're here to help.</p>
    <div class="reply-box">
      <div class="avatar">DA</div>
      <span>We usually reply in a few minutes</span>
      <span class="online-dot"></span>
    </div>
  </div>

  <div class="help-section">
    <h2>Quick actions</h2>

    <div class="card flex">
      <div>
        <b>Track your order</b>
        <p>Get real-time order updates</p>
      </div>
      <span>→</span>
    </div>

    <div class="card flex">
      <div>
        <b>Contact us</b>
        <p>Talk to our support team</p>
      </div>
      <span class="whatsapp">☎</span>
    </div>

    <div class="faq-card">
      <h3>Browse FAQs</h3>
      <input placeholder="🔍 Search for an answer…" />
      <ul>
        <li>Payment methods →</li>
        <li>How do I return an item? →</li>
        <li>Exchange process →</li>
      </ul>
      <a>View all articles</a>
    </div>

    <button class="chat-start">💬 Chat with us</button>
  </div>

</div>

<!-- CHAT SCREEN -->
<div class="chat-window">

  <header>
    <button class="back-btn" aria-label="Back">←</button>
    <div class="avatar">DA</div>
    <div class="header-info">
      <h3>Divy Assistant</h3>
      <p>Online now</p>
    </div>
  </header>

  <div class="messages"></div>

  <div class="input-area">
    <input id="chatInput" placeholder="Type a message…" autocomplete="off" />
    <button class="send-btn" id="chatSend" aria-label="Send">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"
           stroke-linecap="round" stroke-linejoin="round">
        <line x1="22" y1="2" x2="11" y2="13"></line>
        <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
      </svg>
    </button>
  </div>

  <div class="powered">⚡ Powered by AI Assistant</div>

</div>

`;

  // ── state ────────────────────────────────────────────────────
  const visitorId = getOrCreateVisitorId();
  let sessionId   = sessionStorage.getItem("ai_session_id") || null;

  // ── element refs ─────────────────────────────────────────────
  const floatBtn  = root.querySelector(".ai-floating-btn");
  const widget    = root.querySelector(".ai-widget");
  const chat      = root.querySelector(".chat-window");
  const messages  = root.querySelector(".messages");
  const input     = root.querySelector("#chatInput");
  const sendBtn   = root.querySelector("#chatSend");

  // ── initial greeting ─────────────────────────────────────────
  appendBotMessage("Hi there! 👋 How can I help you today?");

  // ── UI behaviour ─────────────────────────────────────────────
  floatBtn.onclick = () => {
    widget.classList.add("show");
    floatBtn.style.display = "none";
  };

  root.querySelector(".close-btn").onclick = () => {
    widget.classList.remove("show");
    floatBtn.style.display = "flex";
  };

  root.querySelector(".chat-start").onclick = () => {
    widget.classList.remove("show");
    chat.classList.add("show");
  };

  root.querySelector(".back-btn").onclick = () => {
    chat.classList.remove("show");
    widget.classList.add("show");
  };

  sendBtn.onclick = sendMessage;
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) sendMessage();
  });

  // ── send message ─────────────────────────────────────────────
  async function sendMessage() {
    const text = input.value.trim();
    if (!text) return;

    input.value = "";
    appendUserMessage(text);
    showTyping();

    const cfg        = window.AI_WIDGET || {};
    const customerId = cfg.customer && cfg.customer.id;
    const appUrl     = (cfg.app_url || "").replace(/\/$/, "");

    const body = {
      shop:       cfg.shop,
      message:    text,
      visitor_id: visitorId,
      session_id: sessionId || undefined,
    };

    if (customerId) {
      body.customer_id = customerId;
      body.email       = cfg.customer.email;
      body.first_name  = cfg.customer.first_name;
    }

    const endpoint = appUrl + "/api/chat";
    console.log("[AI Chat] POST →", endpoint, body);

    try {
      const r = await fetch(endpoint, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify(body),
      });

      if (!r.ok) {
        const t = await r.text();
        throw new Error(r.status + ": " + t.slice(0, 120));
      }

      const data = await r.json();
      removeTyping();

      if (data.session_id) {
        sessionId = data.session_id;
        sessionStorage.setItem("ai_session_id", sessionId);
      }

      appendBotMessage(data.response || "Sorry, something went wrong.");
    } catch (err) {
      console.error("[AI Chat] error:", err);
      removeTyping();
      appendBotMessage("Sorry, I couldn't connect. Please try again.");
    }
  }

  // ── message rendering ─────────────────────────────────────────
  function appendBotMessage(text) {
    const row = document.createElement("div");
    row.className = "bot-row";
    row.innerHTML = `
      <div class="bubble-avatar">DA</div>
      <div class="bot">${escapeHtml(text)}</div>
    `;
    messages.appendChild(row);
    scrollToBottom();
  }

  function appendUserMessage(text) {
    const div = document.createElement("div");
    div.className = "user";
    div.textContent = text;
    messages.appendChild(div);
    scrollToBottom();
  }

  function showTyping() {
    const row = document.createElement("div");
    row.className = "bot-row";
    row.id = "ai-typing";
    row.innerHTML = `
      <div class="bubble-avatar">DA</div>
      <div class="bot typing-indicator">
        <span></span><span></span><span></span>
      </div>
    `;
    messages.appendChild(row);
    scrollToBottom();
  }

  function removeTyping() {
    const t = document.getElementById("ai-typing");
    if (t) t.remove();
  }

  function scrollToBottom() {
    messages.scrollTop = messages.scrollHeight;
  }

  // ── helpers ───────────────────────────────────────────────────
  function escapeHtml(str) {
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function getOrCreateVisitorId() {
    let id = localStorage.getItem("ai_visitor_id");
    if (!id) {
      id = "v_" + Math.random().toString(36).slice(2) + "_" + Date.now();
      localStorage.setItem("ai_visitor_id", id);
    }
    return id;
  }
})();
