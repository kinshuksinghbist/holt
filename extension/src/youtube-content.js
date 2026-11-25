(() => {
  const api = typeof browser !== "undefined" ? browser : chrome;

  function injectPageReader() {
    const existing = document.getElementById("holt-yt-page-script");
    if (existing) existing.remove();
    const s = document.createElement("script");
    s.id = "holt-yt-page-script";
    s.src = api.runtime.getURL("src/youtube-page.js");
    s.onload = () => s.remove();
    (document.head || document.documentElement).appendChild(s);
  }

  function readMetaFallback() {
    const genre = document.querySelector('meta[itemprop="genre"]')?.getAttribute("content") || null;
    const channel = document.querySelector('#owner #channel-name a, link[itemprop="name"]')?.textContent?.trim()
      || document.querySelector('span[itemprop="author"] link[itemprop="name"]')?.getAttribute("content")
      || null;
    const params = new URLSearchParams(window.location.search);
    const videoId = params.get("v");
    return { videoId, channel, category: genre, title: document.title };
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || !event.data || event.data.source !== "holt-yt-page") return;
    const fallback = readMetaFallback();
    api.runtime.sendMessage({
      type: "holt-youtube-meta",
      videoId: event.data.videoId || fallback.videoId,
      channel: event.data.channel || fallback.channel,
      category: event.data.category || fallback.category,
      title: event.data.title || fallback.title
    });
  });

  function refresh() {
    if (!window.location.pathname.startsWith("/watch") && !window.location.pathname.startsWith("/shorts")) return;
    setTimeout(() => {
      injectPageReader();
      setTimeout(() => {
        const fb = readMetaFallback();
        if (fb.videoId || fb.category) {
          api.runtime.sendMessage({ type: "holt-youtube-meta", ...fb });
        }
      }, 300);
    }, 250);
  }

  window.addEventListener("yt-navigate-finish", refresh);
  refresh();
})();
