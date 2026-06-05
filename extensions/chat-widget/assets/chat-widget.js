(function () {
    console.log("AI CHAT LOADED");

    const root =
        document.getElementById("ai-support-widget");


    root.innerHTML = `


<!-- FLOAT BUTTON -->

<button class="ai-floating-btn">
  💬

  <span class="badge">
  1
  </span>

</button>




<!-- HOME SCREEN -->


<div class="ai-widget">


<div class="orange-section">


<button class="close-btn">
×
</button>


<h1>
Hi there, 👋
</h1>


<p>
Welcome to divy test,<br>
feel free to ask us anything
</p>



<div class="reply-box">

<div class="avatar">
DA
</div>

<span>
We usually reply in 🕘 a few minutes
</span>

<span class="online-dot">
</span>

</div>


</div>





<div class="help-section">


<h2>
Get Instant Help
</h2>



<div class="card">

<b>
Contact us via
</b>

<span class="whatsapp">
☎
</span>

</div>




<div class="card flex">

<div>

<b>
Track your orders
</b>

<p>
Instantly find your order
</p>

</div>

<span>
→
</span>

</div>





<div class="faq-card">

<h3>
Browse FAQ
</h3>


<input
placeholder="🔍 Find quick answer"
/>


<ul>

<li>
Payment →
</li>

<li>
How do I return my items? →
</li>

<li>
Exchange process →
</li>


</ul>


<a>
Browse all articles
</a>

</div>





<button class="chat-start">

💬 Chat with us

</button>


</div>


</div>





<!-- CHAT SCREEN -->



<div class="chat-window">


<header>


<div class="avatar">
DA
</div>


<div>

<h3>
Divy Assistant
</h3>

<p>
● Online
</p>

</div>


</header>



<div class="messages">


<div class="bot">

Hi there! 👋 <br>
How can I help you today?

</div>


<div class="user">

I want to track my order

</div>


<div class="bot">

Sure, I can help you with that.
Please provide your order number.

</div>


</div>



<div class="input-area">


<input
id="chatInput"
placeholder="Type your message..."
/>


<button>
➤
</button>


</div>


<div class="powered">

⚡ Powered by AI Assistant

</div>


</div>

`;



    const btn =
        document.querySelector(".ai-floating-btn");


    const widget =
        document.querySelector(".ai-widget");


    const chat =
        document.querySelector(".chat-window");



    btn.onclick = () => {

        widget.classList.add("show");

        btn.style.display = "none";

    }



    document
        .querySelector(".close-btn")
        .onclick = () => {

            widget.classList.remove("show");

            btn.style.display = "block";

        }



    document
        .querySelector(".chat-start")
        .onclick = () => {

            widget.style.display = "none";

            chat.classList.add("show");

        }



})();