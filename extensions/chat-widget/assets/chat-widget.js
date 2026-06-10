(function () {
  const root = document.getElementById("ai-support-widget");
  if (!root || root._aiInit) return;
  root._aiInit = true;

  const cfg = window.AI_WIDGET || {};
  const shop = cfg.shop || "";
  const appUrl = (cfg.app_url || "/apps/ai-chat").replace(/\/$/, "");

  const visitorId = getOrCreateVisitorId();
  let sessionId = sessionStorage.getItem("ai_session_id") || null;
  let promptsHidden = false;
  console.log(
    "🔥 CONFIG URL:",
    `${appUrl}/configuration?shop=${encodeURIComponent(shop)}`
  );
  // Fetch bot settings then render
  fetch(`${appUrl}/configuration?shop=${encodeURIComponent(shop)}`, {
    cache: "no-store",
    headers: {
      "ngrok-skip-browser-warning": "true"
    }
  })
    .then(r => r.json())
    .then(s => boot(s))
    .catch(err => {
      console.error("[AI Config]", err);
      boot({});
    });

  // ─────────────────────────────────────────────────────────
  function boot(s) {
    console.log("🔥 CONFIG RESPONSE", s);


    render(s);       // pehle HTML banao
    applyVars(s);    // phir style lagao
    wire(s);
  }
  // ── Apply CSS variables from settings ────────────────────
  function applyVars(s) {
    const rs = document.documentElement.style;
    if (s.primary_color) rs.setProperty("--ai-primary", s.primary_color);
    if (s.background_color) rs.setProperty("--ai-bg", s.background_color);
    if (s.text_color) rs.setProperty("--ai-text", s.text_color);
    if (s.font_family) rs.setProperty("--ai-font", s.font_family);

    const side = (s.desktop_side_spacing || 16) + "px";
    const bottom = (s.desktop_vertical_offset || 80) + "px";
    const mobileSide = (s.mobile_side_spacing || 8) + "px";
    rs.setProperty("--ai-side", side);
    rs.setProperty("--ai-bottom", bottom);
    rs.setProperty("--ai-side-mobile", mobileSide);

    if (s.desktop_alignment === "left") {
      rs.setProperty("--ai-side", "auto");
      root.querySelectorAll(".ai-launcher,.ai-chat-widget").forEach(el => {
        el.style.right = "auto";
        el.style.left = side;
      });
    }

    if (s.mobile_alignment === "left") {
      root.classList.add("ai-mobile-left");
    }
  }

  // ── Build widget HTML matching bot_settings preview ───────
  function render(s) {
    const name = esc(s.assistant_name || "AI Assistant");
    const greeting = s.greeting || "Hi there! 👋 How can I help you today?";
    const prompts = Array.isArray(s.starter_prompts) ? s.starter_prompts : [];
    const logoUrl = s.business_logo_url || "";
    const avatarUrl = s.assistant_avatar_url || "";

    // Logo in header
    const logoHtml = logoUrl
      ? `<div class="ai-chat-logo"><img src="${esc(logoUrl)}" alt="logo"></div>`
      : `<div class="ai-chat-logo-placeholder">
           <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.8">
             <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
           </svg>
         </div>`;

    // Starter prompt pills
    const promptsHtml = prompts.length
      ? `<div class="ai-chat-prompts" id="ai-prompts">
           ${prompts.map(p => `<button class="ai-prompt-btn" type="button">${esc(p)}</button>`).join("")}
         </div>`
      : "";

    root.innerHTML = `

<!-- Launcher -->
<button class="ai-launcher" aria-label="Chat with us">
  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
  </svg>
</button>

<!-- Chat widget (matches bs-chat-mock layout) -->
<div class="ai-chat-widget" role="dialog" aria-label="Chat">

  <!-- Header — mirrors bs-chat-header -->
  <div class="ai-chat-header">
    ${logoHtml}
    <div class="ai-header-text">
      <div class="ai-chat-name">${name}</div>
      <div class="ai-chat-status">Online · Typically replies instantly</div>
    </div>
    <button class="ai-close-btn" aria-label="Close">✕</button>
  </div>

  <!-- Messages — mirrors bs-chat-body -->
  <div class="ai-chat-body" id="ai-messages"></div>

  <!-- Starter prompts — mirrors bs-chat-prompts -->
  ${promptsHtml}

  <!-- Footer — mirrors bs-chat-footer -->
  <div class="ai-chat-footer">
    <input class="ai-chat-input" id="ai-input" placeholder="Type a message…" autocomplete="off" />
    <button class="ai-chat-send" id="ai-send" aria-label="Send">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/>
      </svg>
    </button>
  </div>

  <div class="ai-powered">⚡ Powered by AI Assistant</div>
</div>

`;

    // Show greeting bubble (mirrors bs-chat-bubble bot)
    addBotMessage(greeting, avatarUrl);

    // Prompt pills → send message on click
    root.querySelectorAll(".ai-prompt-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        sendText(btn.textContent.trim(), avatarUrl);
      });
    });
  }

  // ── Wire events ───────────────────────────────────────────
  function wire(s) {
    const launcher = root.querySelector(".ai-launcher");
    const widget = root.querySelector(".ai-chat-widget");
    const input = root.querySelector("#ai-input");
    const sendBtn = root.querySelector("#ai-send");
    const avatarUrl = s.assistant_avatar_url || "";

    launcher.onclick = () => {
      widget.classList.add("show");
      launcher.style.display = "none";
    };

    root.querySelector(".ai-close-btn").onclick = () => {
      widget.classList.remove("show");
      launcher.style.display = "flex";
    };

    sendBtn.onclick = () => {
      const text = input.value.trim();
      if (text) { input.value = ""; sendText(text, avatarUrl); }
    };

    input.addEventListener("keydown", e => {
      if (e.key === "Enter" && !e.shiftKey) {
        const text = input.value.trim();
        if (text) { input.value = ""; sendText(text, avatarUrl); }
      }
    });
  }

  // ── Send a message ────────────────────────────────────────
  async function sendText(text, avatarUrl) {
    // Hide prompts once conversation starts
    if (!promptsHidden) {
      const p = document.getElementById("ai-prompts");
      if (p) { p.style.display = "none"; promptsHidden = true; }
    }

    addUserMessage(text);
    addTyping(avatarUrl);

    const customer = cfg.customer || {};
    const body = { shop, message: text, visitor_id: visitorId, session_id: sessionId || undefined };
    if (customer.id) { body.customer_id = customer.id; body.email = customer.email; body.first_name = customer.first_name; }

    console.log("[AI Chat] POST →", appUrl + "/chat", body);

    try {
      const r = await fetch(appUrl + "/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json", "ngrok-skip-browser-warning": "true" },
        body: JSON.stringify(body),
      });
      if (!r.ok) { const t = await r.text(); throw new Error(r.status + ": " + t.slice(0, 120)); }
      const data = await r.json();
      removeTyping();
      if (data.session_id) { sessionId = data.session_id; sessionStorage.setItem("ai_session_id", sessionId); }
      addBotMessage(data.response || "Sorry, something went wrong.", avatarUrl);
    } catch (err) {
      console.error("[AI Chat]", err);
      removeTyping();
      addBotMessage("Sorry, I couldn't connect. Please try again.", avatarUrl);
    }
  }

  // ── Message renderers (match bs-chat-message-row / bs-chat-bubble) ──
  function msgContainer() { return document.getElementById("ai-messages"); }
  function scrollBottom() { const m = msgContainer(); if (m) m.scrollTop = m.scrollHeight; }

  function addBotMessage(text, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-bubble bot">${esc(text)}</div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  function addUserMessage(text) {
    const row = document.createElement("div");
    row.className = "ai-user-row";
    row.innerHTML = `<div class="ai-bubble user">${esc(text)}</div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  function addTyping(avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.id = "ai-typing";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl ? `<img src="${esc(avatarUrl)}" alt="">` : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-bubble bot ai-typing"><span></span><span></span><span></span></div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  function removeTyping() { const t = document.getElementById("ai-typing"); if (t) t.remove(); }

  // ── Utilities ─────────────────────────────────────────────
  function esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function getOrCreateVisitorId() {
    let id = localStorage.getItem("ai_visitor_id");
    if (!id) { id = "v_" + Math.random().toString(36).slice(2) + "_" + Date.now(); localStorage.setItem("ai_visitor_id", id); }
    return id;
  }
})();
