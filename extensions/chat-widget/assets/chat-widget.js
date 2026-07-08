console.log("Chat widget loaded");
(function () {
  const root = document.getElementById("ai-support-widget");
  if (!root || root._aiInit) return;
  root._aiInit = true;

  const cfg = window.AI_WIDGET || {};
  const shop = cfg.shop || "";
  const appUrl = "https://sb-aic.onrender.com";

  const visitorId = getOrCreateVisitorId();
  let sessionId = sessionStorage.getItem("ai_session_id") || null;
  let promptsHidden = false;
  let handoffActive = false;
  let agentSocket = null;
  let agentSocketAvatarUrl = "";
  let agentReconnectTimer = null;
  let addToCartEnabled = true; // set from server config in boot()
  let relatedQuestionsEnabled = true;
  let relatedQuestionsCount = 3;

  const COLOR_HEX = {
    red: '#e74c3c', blue: '#3498db', green: '#27ae60', black: '#111111', white: '#f9f9f9',
    yellow: '#f1c40f', orange: '#e67e22', purple: '#9b59b6', pink: '#ff69b4',
    brown: '#8b4513', gray: '#95a5a6', grey: '#95a5a6', navy: '#001f5b',
    teal: '#008080', gold: '#d4af37', silver: '#aaaaaa', beige: '#f5f5dc',
    maroon: '#800000', lime: '#32cd32', cyan: '#00bcd4', magenta: '#e91e63',
    indigo: '#3f51b5', violet: '#ee82ee', coral: '#ff6b6b', tan: '#d2b48c',
    khaki: '#f0e68c', lavender: '#e6e6fa', mint: '#98ff98', cream: '#fffdd0',
    charcoal: '#36454f', rose: '#ff007f', peach: '#ffcba4', ivory: '#fffff0'
  };
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

  // ── Load conversation history on reload ───────────────────
  function loadHistory(s, avatarUrl) {
    const params = new URLSearchParams({ shop, session_id: sessionId });
    const customer = cfg.customer || {};
    if (customer.id) params.set("customer_id", customer.id);

    fetch(`${appUrl}/chat/history?${params}`, {
      headers: { "ngrok-skip-browser-warning": "true" }
    })
      .then(r => r.json())
      .then(data => {
        if (!data.messages || data.messages.length === 0) {
          // No history — show greeting as normal
          addBotMessage(s.greeting || "Hi there! 👋 How can I help you today?", avatarUrl);
          return;
        }

        // Restore conversation history
        data.messages.forEach(m => {
          if (m.role === "user") {
            addUserMessage(m.content);
          } else {
            renderHistoryMessage(m, avatarUrl);
          }
        });

        // Hide starter prompts since conversation is already in progress
        promptsHidden = true;
        const p = document.getElementById("ai-prompts");
        if (p) p.style.display = "none";
      })
      .catch(() => {
        // Network error — fall back to greeting
        addBotMessage(s.greeting || "Hi there! 👋 How can I help you today?", avatarUrl);
      });
  }

  // ── Re-render a single history message (text + any card) ─
  function renderHistoryMessage(m, avatarUrl) {
    const meta = m.metadata;

    if (!meta) {
      addBotMessage(m.content, avatarUrl);
      return;
    }

    // Use metadata.message for display — m.content is the LLM-context summary
    const displayText = meta.message || m.content;
    if (displayText) addBotMessage(displayText, avatarUrl);

    const type = meta.type;

    // Product cards
    if (type === "product_cards" && Array.isArray(meta.products)) {
      addProductCards(meta.products, avatarUrl);
    } else {
      if (meta.product) addProductCard(meta.product, avatarUrl);
      if (Array.isArray(meta.products) && type !== "product_cards") {
        addProductCards(meta.products, avatarUrl);
      }
    }

    // Order card
    if (type === "order_details" && meta.order) {
      renderOrderCard(meta.order, avatarUrl);
    }

    // Escalation card
    if (type === "human_escalation") {
      renderEscalationCard(meta, avatarUrl);
    }

    // auth_required / order_lookup_form — text only, no stale interactive card
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
      root.querySelectorAll(".ai-launcher,.ai-chat-widget,.ai-anim-bubble").forEach(el => {
        el.style.right = "auto";
        el.style.left = side;
      });
      const bubble = root.querySelector(".ai-anim-bubble");
      if (bubble) {
        bubble.style.left = `calc(${side} + 60px)`;
        bubble.style.borderRadius = "16px 16px 16px 4px";
      }
    }

    if (s.mobile_alignment === "left") {
      root.classList.add("ai-mobile-left");
    }
  }

  // ── Visibility rules — returns true if widget should be hidden ──
  function shouldHideWidget(s) {
    const ua = navigator.userAgent;
    const isMobile = /Mobi|Android|iPhone|iPad|iPod/i.test(ua) || window.innerWidth < 768;
    const path = window.location.pathname.toLowerCase();

    if (s.hide_on_mobile && isMobile) return true;
    if (s.hide_on_desktop && !isMobile) return true;
    if (s.hide_on_checkout && (path.includes("/checkouts") || path.includes("/checkout"))) return true;
    if (s.hide_on_cart && (path === "/cart" || path.startsWith("/cart/"))) return true;

    return false;
  }

  // ── Boot ─────────────────────────────────────────────────
  function boot(s) {
    console.log("🔥 CONFIG RESPONSE", s);

    // Hide widget entirely if visibility rules exclude this page/device
    if (shouldHideWidget(s)) {
      root.style.display = "none";
      return;
    }

    addToCartEnabled = s.enable_add_to_cart !== false;
    relatedQuestionsEnabled = s.enable_related_questions !== false;
    relatedQuestionsCount = s.related_questions_count || 3;

    render(s);
    applyVars(s);
    wire(s);

    const avatarUrl = s.assistant_avatar_url || "";

    if (sessionId) {
      // Restore previous conversation — greeting is skipped in render() for this path
      loadHistory(s, avatarUrl);
    }

    // Restore handoff WebSocket if this session was already escalated
    if (sessionStorage.getItem("ai_handoff") === "true" && sessionId) {
      _applyHandoffUI();
      connectAgentSocket(avatarUrl);
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

    // Launcher icon inner HTML based on widget_icon_type
    let launcherIconHtml;
    if (s.widget_icon_type === "custom" && s.widget_icon_url) {
      launcherIconHtml = `<img src="${esc(s.widget_icon_url)}" alt="chat icon" style="width:24px;height:24px;border-radius:6px;object-fit:cover;">`;
    } else if (s.widget_icon_type === "text") {
      launcherIconHtml = `<span style="color:#fff;font-size:12px;font-weight:600;">Chat</span>`;
    } else {
      launcherIconHtml = `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>`;
    }

    // Animation bubble (hidden initially; shown by wire())
    const animText = esc(s.animation_text || "Hi there! Need help?");
    const animBubbleHtml = s.enable_animation !== false
      ? `<div class="ai-anim-bubble" id="ai-anim-bubble" aria-hidden="true">${animText}<button class="ai-anim-dismiss" aria-label="Dismiss">✕</button></div>`
      : "";

    root.innerHTML = `

<!-- Animation bubble (shown above launcher) -->
${animBubbleHtml}

<!-- Launcher -->
<button class="ai-launcher" aria-label="Chat with us">
  ${launcherIconHtml}
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
    <button class="ai-new-chat-btn" aria-label="New chat" title="Start new conversation">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.45"/></svg>
    </button>
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

 
</div>

`;

    // Show greeting only for fresh sessions — history loader will handle existing sessions
    if (!sessionId) {
      addBotMessage(greeting, avatarUrl);
    }

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

    // ── Animation bubble ──────────────────────────────────
    const animBubble = root.querySelector("#ai-anim-bubble");
    let animDismissTimer = null;

    function showAnimBubble() {
      if (!animBubble) return;
      animBubble.classList.add("visible");
      // Auto-dismiss after 8 seconds
      animDismissTimer = setTimeout(hideAnimBubble, 8000);
    }

    function hideAnimBubble() {
      if (!animBubble) return;
      clearTimeout(animDismissTimer);
      animBubble.classList.remove("visible");
    }

    // Show bubble after 1.5s on first load
    if (animBubble) {
      setTimeout(showAnimBubble, 1500);

      const dismissBtn = animBubble.querySelector(".ai-anim-dismiss");
      if (dismissBtn) {
        dismissBtn.addEventListener("click", e => {
          e.stopPropagation();
          hideAnimBubble();
        });
      }

      // Clicking the bubble opens the chat
      animBubble.addEventListener("click", () => {
        hideAnimBubble();
        widget.classList.add("show");
        launcher.style.display = "none";
      });
    }

    launcher.onclick = () => {
      hideAnimBubble();
      widget.classList.add("show");
      launcher.style.display = "none";
    };

    root.querySelector(".ai-close-btn").onclick = () => {
      widget.classList.remove("show");
      launcher.style.display = "flex";
      // Re-show bubble after chat closes (if animation is enabled)
      if (animBubble && s.enable_animation !== false) {
        setTimeout(showAnimBubble, 3000);
      }
    };

    root.querySelector(".ai-new-chat-btn").onclick = async () => {
      // Tell the server to close the current conversation + tickets and clear Redis
      if (sessionId) {
        try {
          await fetch(appUrl + "/chat/reset", {
            method: "POST",
            headers: { "Content-Type": "application/json", "ngrok-skip-browser-warning": "true" },
            body: JSON.stringify({ shop, session_id: sessionId, visitor_id: visitorId })
          });
        } catch (_) { /* ignore — still reset locally */ }
      }

      // Reset all client-side state
      sessionId = null;
      sessionStorage.removeItem("ai_session_id");
      sessionStorage.removeItem("ai_handoff");
      promptsHidden = false;
      handoffActive = false;

      // Disconnect any live agent WebSocket
      if (agentSocket) { agentSocket.close(); agentSocket = null; }
      clearTimeout(agentReconnectTimer);

      // Clear chat messages
      const msgs = msgContainer();
      if (msgs) msgs.innerHTML = "";

      // Remove handoff notice and restore input placeholder
      const handoffNotice = root.querySelector(".ai-handoff-notice");
      if (handoffNotice) handoffNotice.remove();
      const input = root.querySelector("#ai-input");
      if (input) input.placeholder = "Type a message…";

      // Restore starter prompts
      const promptsEl = root.querySelector("#ai-prompts");
      if (promptsEl) promptsEl.style.display = "";

      // Show greeting again
      addBotMessage(s.greeting || "Hi there! 👋 How can I help you today?", avatarUrl);
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
    if (!promptsHidden) {
      const p = document.getElementById("ai-prompts");
      if (p) { p.style.display = "none"; promptsHidden = true; }
    }

    addUserMessage(text);

    const customer = cfg.customer || {};
    const body = { shop, message: text, visitor_id: visitorId, session_id: sessionId || undefined };
    if (customer.id) { body.customer_id = customer.id; body.email = customer.email; body.first_name = customer.first_name; }

    // ── Streaming via SSE ────────────────────────────────────
    let streamBubble = null;
    let streamText = "";
    let sseBuffer = "";
    let sseEvent = "message";
    let sseData = "";
    let streamStarted = false;

    function processSseLine(line) {
      if (line === "") {
        // Dispatch buffered event
        if (!sseData) return;
        if (sseEvent === "done") {
          handleDone(sseData, avatarUrl, streamBubble, streamText);
        } else if (sseEvent === "error") {
          removeTyping();
          addBotMessage("Sorry, something went wrong. Please try again.", avatarUrl);
        } else {
          // token event — default "message"
          try {
            const token = JSON.parse(sseData);
            if (typeof token === "string" && token) {
              if (!streamStarted) {
                removeTyping();
                streamBubble = addStreamingBubble(avatarUrl);
                streamStarted = true;
              }
              streamText += token;
              appendToStream(streamBubble, token);
            }
          } catch (_) { /* skip malformed */ }
        }
        sseEvent = "message";
        sseData = "";
      } else if (line.startsWith("event:")) {
        sseEvent = line.slice(6).trim();
      } else if (line.startsWith("data:")) {
        sseData = line.slice(5).trim();
      }
    }

    addTyping(avatarUrl);

    try {
      const r = await fetch(appUrl + "/chat/stream", {
        method: "POST",
        headers: { "Content-Type": "application/json", "ngrok-skip-browser-warning": "true" },
        body: JSON.stringify(body)
      });

      if (!r.ok) throw new Error(r.status);

      const reader = r.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        sseBuffer += decoder.decode(value, { stream: true });

        let newlineIdx;
        while ((newlineIdx = sseBuffer.indexOf("\n")) !== -1) {
          const line = sseBuffer.slice(0, newlineIdx);
          sseBuffer = sseBuffer.slice(newlineIdx + 1);
          processSseLine(line);
        }
      }

    } catch (err) {
      console.error("[AI Stream]", err);
      removeTyping();
      if (streamBubble) finalizeStream(streamBubble, streamText);
      else addBotMessage("Sorry, I couldn't connect. Please try again.", avatarUrl);
    }
  }

  // ── Handle the "done" SSE event — render structured payload ─
  function handleDone(rawData, avatarUrl, streamBubble, streamText) {
    let payload;
    try { payload = JSON.parse(rawData); } catch (_) { payload = {}; }

    // Unwrap nested { session_id, response } if present
    if (payload.session_id) {
      sessionId = payload.session_id;
      sessionStorage.setItem("ai_session_id", sessionId);
    }

    const inner = (payload.response && typeof payload.response === "object")
      ? payload.response : payload;

    // Finalize streaming bubble if we were streaming text
    if (streamBubble) {
      finalizeStream(streamBubble, streamText);
    } else {
      removeTyping();
      // Non-streamed text (e.g. greeting/escalation hardcoded messages)
      const textMsg = typeof inner.message === "string" ? inner.message
        : typeof inner.response === "string" ? inner.response : null;
      if (textMsg) addBotMessage(textMsg, avatarUrl);
    }

    // Product cards
    if (inner.type === "product_cards" && Array.isArray(inner.products)) {
      addProductCards(inner.products, avatarUrl);
    } else {
      if (inner.product) addProductCard(inner.product, avatarUrl);
      if (Array.isArray(inner.products)) addProductCards(inner.products, avatarUrl);
    }

    if (inner.type === "auth_required") { renderAuthCard(inner, avatarUrl); return; }

    if (inner.type === "order_lookup_form") addOrderLookupForm(inner, avatarUrl);
    if (inner.type === "order_details" && inner.order) renderOrderCard(inner.order, avatarUrl);

    if (inner.type === "human_escalation" || inner.type === "human_handoff_active") {
      lockInputForHandoff(avatarUrl);
    }
    if (inner.type === "human_escalation") renderEscalationCard(inner, avatarUrl);

    // Related questions chips — skip for escalation/handoff/auth flows
    const skipChips = ["human_escalation", "human_handoff_active", "auth_required", "order_lookup_form"];
    if (relatedQuestionsEnabled && Array.isArray(inner.related_questions) && inner.related_questions.length &&
      !skipChips.includes(inner.type)) {
      renderRelatedQuestions(inner.related_questions, avatarUrl);
    }
  }

  // ── Streaming bubble helpers ──────────────────────────────
  function addStreamingBubble(avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-bubble bot ai-stream-bubble"></div>`;
    msgContainer().appendChild(row);
    scrollBottom();
    return row.querySelector(".ai-stream-bubble");
  }

  function appendToStream(bubbleEl, token) {
    // Insert text node before the cursor so cursor stays at end
    let cursor = bubbleEl.querySelector(".ai-stream-cursor");
    if (!cursor) {
      cursor = document.createElement("span");
      cursor.className = "ai-stream-cursor";
      bubbleEl.appendChild(cursor);
    }
    bubbleEl.insertBefore(document.createTextNode(token), cursor);
    scrollBottom();
  }

  function finalizeStream(bubbleEl, fullText) {
    if (!bubbleEl) return;
    // Re-render with newline support and remove cursor
    bubbleEl.innerHTML = fullText
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\n/g, "<br>");
    scrollBottom();
  }

  // ── Message renderers (match bs-chat-message-row / bs-chat-bubble) ──
  function msgContainer() { return document.getElementById("ai-messages"); }
  function scrollBottom() { const m = msgContainer(); if (m) m.scrollTop = m.scrollHeight; }

  function addBotMessage(text, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    // Escape HTML then restore newlines as <br> so multi-line AI responses render correctly
    const safeHtml = esc(text).replace(/\n/g, "<br>");
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-bubble bot">${safeHtml}</div>`;
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

  // ── Product card ──────────────────────────────────────────
  function addProductCard(product, avatarUrl) {
    addProductCards([product], avatarUrl);
  }

  function addProductCards(products, avatarUrl) {
    if (!products || !products.length) return;

    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>`;

    if (products.length === 1) {
      const card = buildProductCard(products[0]);
      row.appendChild(card);
      msgContainer().appendChild(row);
      scrollBottom();
      wireProductCard(card, avatarUrl);
    } else {
      const strip = document.createElement("div");
      strip.className = "ai-product-cards-strip";
      products.forEach(p => {
        const card = buildProductCard(p);
        strip.appendChild(card);
        wireProductCard(card, avatarUrl);
      });
      wireDragScroll(strip);
      row.appendChild(strip);
      msgContainer().appendChild(row);
      scrollBottom();
    }
  }

  function wireDragScroll(el) {
    let isDown = false, startX = 0, scrollLeft = 0;
    el.addEventListener("mousedown", e => {
      isDown = true;
      startX = e.pageX - el.offsetLeft;
      scrollLeft = el.scrollLeft;
    });
    el.addEventListener("mouseleave", () => { isDown = false; });
    el.addEventListener("mouseup", () => { isDown = false; });
    el.addEventListener("mousemove", e => {
      if (!isDown) return;
      e.preventDefault();
      el.scrollLeft = scrollLeft - (e.pageX - el.offsetLeft - startX);
    });
  }

  function addOrderLookupForm(payload, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";

    row.innerHTML = `
    <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>

    <div class="ai-bubble bot ai-order-form">

      <div class="ai-order-header">
        <div class="ai-order-title">📦 Track Your Order</div>
        <div class="ai-order-subtitle">
          Enter your details to find your order status
        </div>
      </div>

      <div class="ai-order-fields">

        <div class="ai-field">
          <label>Order ID</label>
          <input id="order-id" placeholder="#12345" required/>
        </div>

        <div class="ai-field">
          <label>Email Address</label>
          <input id="order-email" type="email" placeholder="you@example.com" required/>
        </div>

        <div class="ai-field">
          <label>Phone Number (optional)</label>
          <input id="order-phone" type="text" placeholder="+91 XXXXX XXXXX" />
        </div>

      </div>

      <button id="order-submit" class="ai-order-btn">
        Check Order Status
      </button>

      <div class="ai-order-note">
        🔒 Your data is secure and only used for order lookup
      </div>

    </div>
  `;

    msgContainer().appendChild(row);
    scrollBottom();

    row.querySelector("#order-submit").onclick = async () => {
      const orderId = row.querySelector("#order-id").value.trim();
      const email = row.querySelector("#order-email").value.trim();
      const phone = row.querySelector("#order-phone").value.trim();

      addTyping();

      await fetchOrderDetails({ order_id: orderId, email, phone }, avatarUrl);
    };
  }

  async function fetchOrderDetails(data, avatarUrl) {
    const r = await fetch(appUrl + "/order_lookup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        shop,
        session_id: sessionId,
        visitor_id: visitorId,
        ...data
      })
    });

    const res = await r.json();
    console.log("[AI Chat] Order lookup response:", res);
    removeTyping();

    if (res.message) addBotMessage(res.message, avatarUrl);

    if (res.type === "order_details" && res.order) {
      renderOrderCard(res.order, avatarUrl);
    } else if (res.type === "order_lookup_form") {
      addOrderLookupForm(res, avatarUrl);
    } else if (!res.order) {
      addBotMessage("Sorry, something went wrong. Please try again.");
    }
  }


  function renderOrderCard(order, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";

    const items = Array.isArray(order.items) ? order.items : [];
    const shipping = order.shipping_address || {};

    row.innerHTML = `
     <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>

<div class="invoice-card">

  <div class="invoice-header">
    <h3>📦 Order ${esc(order.name || "")}</h3>
    <span>
      ${order.created_at
        ? new Date(order.created_at).toLocaleDateString()
        : ""
      }
    </span>
  </div>

  <div class="invoice-status">
    <span class="status paid">
      ${esc(order.financial_status || "—")}
    </span>

    <span class="status unfulfilled">
      ${esc(order.fulfillment_status || "—")}
    </span>
  </div>

  ${items.length
        ? `
      <div class="invoice-items">

        ${items.map(item => `
          <div class="invoice-item">

            <img
              src="${esc(item.image || '')}"
              alt="${esc(item.title)}"
              onerror="this.style.display='none'"
            >

            <div class="invoice-item-info">

              <div >
                ${esc(item.title)}
              </div>

              ${item.sku
            ? `
                  <div class="sku">
                    SKU: ${esc(item.sku)}
                  </div>
                `
            : ""
          }

              <div class="price">
                ${esc(order.currency || "")}
                ${esc(item.unit_price || "0")}
                ×
                ${esc(String(item.quantity))}
              </div>

            </div>

            <div class="invoice-line-total">
              ${esc(order.currency || "")}
              ${esc(item.total_price || "0")}
            </div>

          </div>
        `).join("")}

      </div>
    `
        : ""
      }

  <div class="invoice-address">
    <h4>Shipping Address</h4>

    <p>${esc(shipping.name || "")}</p>

    ${shipping.address1
        ? `<p>${esc(shipping.address1)}</p>`
        : ""
      }

    ${shipping.address2
        ? `<p>${esc(shipping.address2)}</p>`
        : ""
      }

    <p>
      ${esc(shipping.city || "")}
      ${shipping.city ? "," : ""}
      ${esc(shipping.province || "")}
    </p>

    <p>
      ${esc(shipping.zip || "")}
    </p>

    <p>
      ${esc(shipping.country || "")}
    </p>
  </div>


  ${order.tracking?.length ? `
  <div class="invoice-address">
    <h4>Tracking Information</h4>

    ${order.tracking.map(track => `
      <div class="tracking-row">

        <div>
          <strong>${esc(track.company || "Carrier")}</strong>
        </div>

        <div>
          Tracking #: ${esc(track.number || "N/A")}
        </div>

        ${track.url
          ? `
            <a
              href="${esc(track.url)}"
              target="_blank"
              rel="noopener noreferrer"
              class="tracking-link"
            >
              Track Package →
            </a>
            `
          : ""
        }

      </div>
    `).join("")}
  </div>
` : ""}

  <div class="invoice-summary">

    <div>
      <span>Subtotal</span>
      <span>
        ${esc(order.currency || "")}
        ${esc(order.subtotal || "0")}
      </span>
    </div>

    <div>
      <span>Shipping</span>
      <span>
        ${esc(order.currency || "")}
        ${esc(order.shipping || "0")}
      </span>
    </div>

    <div>
      <span>Tax</span>
      <span>
        ${esc(order.currency || "")}
        ${esc(order.tax || "0")}
      </span>
    </div>

    <div class="grand-total">
      <span>Total</span>
      <span>
        ${esc(order.currency || "")}
        ${esc(order.total || "0")}
      </span>
    </div>

  </div>

</div>
`;

    msgContainer().appendChild(row);
    scrollBottom();
  }

  function parseVariantOptions(variants) {
    const SIZE_RE = /^(xs|s|m|l|xl|2xl|xxl|3xl|xxxl|small|medium|large|one.?size)$/i;
    const partSets = [];
    (variants || []).forEach(v => {
      if (!v.title || v.title === "Default Title") return;
      v.title.split(" / ").forEach((part, i) => {
        if (!partSets[i]) partSets[i] = new Set();
        partSets[i].add(part.trim());
      });
    });
    let colors = [], sizes = [];
    partSets.forEach(set => {
      const vals = [...set];
      if (vals.some(v => COLOR_HEX[v.toLowerCase()])) {
        colors = vals;
      } else if (vals.some(v => SIZE_RE.test(v))) {
        sizes = vals;
      } else {
        sizes = [...sizes, ...vals];
      }
    });
    return { colors, sizes };
  }

  function buildProductCard(product) {
    const card = document.createElement("div");
    card.className = "ai-product-card";
    card.dataset.variants = JSON.stringify(product.variants || []);

    const imageUrl = product.image || (product.images && product.images[0] && product.images[0].src) || "";
    if (imageUrl) {
      const url = new URL(imageUrl);
      url.searchParams.set("width", "200"); // agar width pehle se hai to update karega
      imageUrl = url.toString();
    }

    const imageHtml = `
  <img 
    src="${esc(imageUrl || window.AI_WIDGET.assets.no_product)}"
    alt="${esc(product.title || 'No image')}"
  >
`;

    const sku = (product.variants && product.variants[0] && product.variants[0].sku) || product.sku || "";
    const codeHtml = sku ? `<div class="ai-product-code">Code #${esc(sku)}</div>` : "";

    // Price — variants carry a float price directly (e.g. 749.95)
    const variants = Array.isArray(product.variants) ? product.variants : [];
    const prices = variants.map(v => parseFloat(v.price)).filter(p => !isNaN(p) && p > 0);
    const minPrice = prices.length ? Math.min(...prices) : parseFloat(product.price || 0);
    const maxPrice = prices.length ? Math.max(...prices) : minPrice;
    const shopCurrency = product.currency || cfg.currency || window.AI_WIDGET?.currency || "USD";
    const fmt = n => new Intl.NumberFormat("en-US", { style: "currency", currency: shopCurrency }).format(n);
    const priceLabel = minPrice ? (minPrice !== maxPrice ? `From ${fmt(minPrice)}` : fmt(minPrice)) : "";
    const priceHtml = `
  <div class="ai-product-price">
    ${priceLabel}
  </div>
`;

    // Options parsed from variant titles like "l / beige"
    const { colors, sizes } = parseVariantOptions(variants);

    const colorsHtml = colors.length
      ? `<div class="ai-product-section">
      <div class="ai-product-label">Available Colors</div>
      <div class="ai-color-swatches">
      ${colors.map(v => {
        const hex = COLOR_HEX[v.toLowerCase()];
        const disabledAttr = addToCartEnabled ? "" : "disabled aria-disabled='true'";
        const displayClass = addToCartEnabled ? "" : " ai-color-swatch--display";
        const dataAttr = addToCartEnabled ? `data-color="${esc(v)}"` : "";
        return hex
          ? `<button class="ai-color-swatch${displayClass}" style="background:${hex}" title="${esc(v)}" ${dataAttr} ${disabledAttr}></button>`
          : `<button class="ai-color-swatch ai-color-swatch--text${displayClass}" ${dataAttr} ${disabledAttr}>${esc(v)}</button>`;
      }).join("")}
      </div>
    </div>`
      : "";

    const sizesHtml = sizes.length
      ? `<div class="ai-product-section">
    <div class="ai-product-label">Available Sizes</div>
    <div class="ai-size-options">
    ${sizes.map(v => {
        const disabledAttr = addToCartEnabled ? "" : "disabled aria-disabled='true'";
        const displayClass = addToCartEnabled ? "" : " ai-size-btn--display";
        const dataAttr = addToCartEnabled ? `data-size="${esc(v)}"` : "";
        return `<button class="ai-size-btn${displayClass}" ${dataAttr} ${disabledAttr}>${esc(v.toUpperCase())}</button>`;
      }).join("")}
    </div>
  </div>`
      : "";


    const productUrl = product.url || (product.handle ? `/products/${product.handle}` : "#");

    card.innerHTML = `
      <a class="ai-product-img-link" href="${esc(productUrl)}" target="_blank" rel="noopener noreferrer">
        <div class="ai-product-img">${imageHtml}</div>
      </a>
      <div class="ai-product-info">
        ${codeHtml}
        <a class="ai-product-title" href="${esc(productUrl)}" target="_blank" rel="noopener noreferrer">${esc(product.title || "Product")}</a>
        ${priceLabel ? `<div class="ai-product-price">${esc(priceLabel)}</div>` : ""}
      </div>
      ${colorsHtml || sizesHtml ? `<div class="ai-product-variants">${colorsHtml}${sizesHtml}</div>` : ""}
      <div class="ai-product-actions-row">
        ${addToCartEnabled
        ? `<button type="button" class="ai-add-to-cart" data-product-url="${esc(productUrl)}">Add to Cart</button>`
        : `<a class="ai-view-product-link" href="${esc(productUrl)}" target="_blank" rel="noopener noreferrer">View Product</a>`
      }
      </div>`;

    return card;
  }

  function wireProductCard(card, avatarUrl) {
    const variants = JSON.parse(card.dataset.variants || "[]");
    let selectedColor = null;
    let selectedSize = null;

    card.querySelectorAll(".ai-color-swatch").forEach(btn => {
      btn.addEventListener("click", () => {
        card.querySelectorAll(".ai-color-swatch").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        selectedColor = btn.dataset.color || null;
      });
    });

    card.querySelectorAll(".ai-size-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        card.querySelectorAll(".ai-size-btn").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");
        selectedSize = btn.dataset.size || null;
      });
    });

    const cartBtn = card.querySelector(".ai-add-to-cart");
    if (!cartBtn) return;

    cartBtn.addEventListener("click", async () => {
      const variant = findMatchingVariant(variants, selectedColor, selectedSize);

      // No Shopify variant ID available — fall back to opening the product page
      if (!variant || !variant.shopify_variant_id) {
        window.open(cartBtn.dataset.productUrl || "#", "_blank");
        return;
      }

      if (variant.stock <= 0) {
        addBotMessage("Sorry, that variant is currently out of stock.", avatarUrl);
        return;
      }

      const productTitle = card.querySelector(".ai-product-title")?.textContent?.trim() || "Product";
      const variantLabel = (!variant.title || variant.title === "Default Title") ? "" : ` — ${variant.title}`;

      cartBtn.textContent = "Adding…";
      cartBtn.disabled = true;

      try {
        const r = await fetch("/cart/add.js", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: variant.shopify_variant_id, quantity: 1 })
        });

        if (!r.ok) {
          const err = await r.json().catch(() => ({}));
          throw new Error(err.description || "Add to cart failed");
        }

        cartBtn.textContent = "✓ Added!";
        cartBtn.style.background = "#27ae60";

        addBotMessage(
          `✅ "${productTitle}${variantLabel}" has been added to your cart! `,
          avatarUrl
        );
      } catch (err) {
        console.error("[AI Cart]", err);
        cartBtn.textContent = "Add to Cart";
        cartBtn.disabled = false;
        addBotMessage(
          "Sorry, I couldn't add that to your cart. Please try again or visit the product page.",
          avatarUrl
        );
      }
    });
  }

  // Find the best matching variant for the selected color + size combination.
  function findMatchingVariant(variants, color, size) {
    if (!variants || variants.length === 0) return null;
    if (variants.length === 1) return variants[0];

    const lc = s => (s || "").toLowerCase();

    // Exact match on both color and size
    if (color && size) {
      const match = variants.find(v =>
        lc(v.title).includes(lc(color)) && lc(v.title).includes(lc(size))
      );
      if (match) return match;
    }

    // Color only
    if (color) {
      const match = variants.find(v => lc(v.title).includes(lc(color)));
      if (match) return match;
    }

    // Size only
    if (size) {
      const match = variants.find(v => lc(v.title).includes(lc(size)));
      if (match) return match;
    }

    // No selection — first in-stock variant, else first variant
    return variants.find(v => v.stock > 0) || variants[0];
  }

  // ── Auth required card ────────────────────────────────────
  function renderAuthCard(payload, avatarUrl) {
    const loginUrl = `${window.location.origin}/account/login`;
    const registerUrl = `${window.location.origin}/account/register`;

    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-auth-card">
        <div class="ai-auth-icon">🔒</div>
        <div class="ai-auth-title">Sign in required</div>
        <div class="ai-auth-body">${esc(payload.message || "Please sign in to access this feature.")}</div>
        <div class="ai-auth-actions">
          <a class="ai-auth-btn ai-auth-btn--primary" href="${esc(loginUrl)}" target="_blank" rel="noopener noreferrer">Sign In</a>
          <a class="ai-auth-btn ai-auth-btn--secondary" href="${esc(registerUrl)}" target="_blank" rel="noopener noreferrer">Create Account</a>
        </div>
      </div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  // ── Related questions chips ───────────────────────────────
  function renderRelatedQuestions(questions, avatarUrl) {
    // Remove any existing chip row first (only latest should show)
    root.querySelectorAll(".ai-related-chips").forEach(el => el.remove());

    const row = document.createElement("div");
    row.className = "ai-related-chips";
    row.innerHTML = questions
      .slice(0, relatedQuestionsCount)
      .map(q => `<button class="ai-chip" type="button">${esc(q)}</button>`)
      .join("");

    msgContainer().appendChild(row);
    scrollBottom();

    row.querySelectorAll(".ai-chip").forEach(btn => {
      btn.addEventListener("click", () => {
        // Remove the chips so they don't persist after being used
        row.remove();
        sendText(btn.textContent.trim(), avatarUrl);
      });
    });
  }

  // ── Human escalation card ─────────────────────────────────
  function renderEscalationCard(payload, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8c9196" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-escalation-card">
        <div class="ai-escalation-icon">🎧</div>
        <div class="ai-escalation-title">Connected to Support Team</div>
        <div class="ai-escalation-body">
          Your request has been escalated. A human agent will review your conversation and respond soon.
        </div>
        ${payload.ticket_number
        ? `<div class="ai-escalation-ticket">Ticket: <strong>${esc(payload.ticket_number)}</strong></div>`
        : ""}
        <div class="ai-escalation-note">Keep an eye on your email for updates.</div>
      </div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  function lockInputForHandoff(avatarUrl) {
    if (handoffActive) return;
    handoffActive = true;
    sessionStorage.setItem("ai_handoff", "true");
    _applyHandoffUI();
    connectAgentSocket(avatarUrl);
  }

  function _applyHandoffUI() {
    const input = root.querySelector("#ai-input");
    if (input) input.placeholder = "Message the support team…";

    if (!root.querySelector(".ai-handoff-notice")) {
      const notice = document.createElement("div");
      notice.className = "ai-handoff-notice";
      notice.textContent = "🧑‍💼 Handoff active — your messages are logged for the support Team";
      const footer = root.querySelector(".ai-chat-footer");
      if (footer) footer.insertAdjacentElement("beforebegin", notice);
    }
  }

  // Native WebSocket — speaks the Action Cable wire protocol directly.
  // No external library needed; avoids ngrok interstitial + CSP issues.
  function connectAgentSocket(avatarUrl) {
    console.log("CONNECTING SOCKET");
    console.log("sessionId =", sessionId);

    if (!sessionId) return;
    if (agentSocket && agentSocket.readyState <= WebSocket.OPEN) return;

    clearTimeout(agentReconnectTimer);
    agentSocketAvatarUrl = avatarUrl;

    const wsUrl = appUrl.replace(/^https/, "wss").replace(/^http/, "ws") + "/cable";
    const identifier = JSON.stringify({ channel: "ConversationChannel", session_id: sessionId });

    agentSocket = new WebSocket(wsUrl);

    agentSocket.onopen = () => {
      agentSocket.send(JSON.stringify({ command: "subscribe", identifier }));
    };

    agentSocket.onmessage = (event) => {
      console.log("WS RAW:", event.data);
      try {
        const frame = JSON.parse(event.data);
        // Ignore protocol frames (welcome, ping, confirm)
        console.log("WS FRAME:", frame);
        if (frame.type || !frame.message) return;
        const data = frame.message;
        console.log("WS DATA:", data);
        if (data && data.role === "agent") {
          addAgentMessage(data.content, agentSocketAvatarUrl);
        }
      } catch (_) { }
    };

    agentSocket.onclose = () => {
      if (handoffActive) {
        console.log("WS CLOSED");
        agentReconnectTimer = setTimeout(() => connectAgentSocket(agentSocketAvatarUrl), 3000);
      }
    };

    agentSocket.onerror = () => agentSocket.close();
  }

  function addAgentMessage(text, avatarUrl) {
    const row = document.createElement("div");
    row.className = "ai-message-row";
    row.innerHTML = `
      <div class="ai-message-avatar">
        ${avatarUrl
        ? `<img src="${esc(avatarUrl)}" alt="avatar">`
        : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#2e7d32" stroke-width="1.8"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>`}
      </div>
      <div class="ai-bubble agent-reply">
        <div class="ai-agent-label">Support Agent</div>
        ${esc(text)}
      </div>`;
    msgContainer().appendChild(row);
    scrollBottom();
  }

  // ── Utilities ─────────────────────────────────────────────
  function esc(str) {
    return String(str).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function stripHtml(html) {
    return String(html).replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  }

  function getOrCreateVisitorId() {
    let id = localStorage.getItem("ai_visitor_id");
    if (!id) { id = "v_" + Math.random().toString(36).slice(2) + "_" + Date.now(); localStorage.setItem("ai_visitor_id", id); }
    return id;
  }
})();
