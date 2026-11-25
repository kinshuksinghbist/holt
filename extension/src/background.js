const api = typeof browser !== "undefined" ? browser : chrome;
const HOST_NAME = "io.github.kinshuksinghbist.holt";
const isFirefox = typeof browser !== "undefined" && typeof browser.runtime?.getBrowserInfo === "function";
const BROWSER_NAME = isFirefox ? "Firefox" : "Chrome";

let port = null;
const youtubeCache = new Map();

function ensurePort() {
  if (port) return port;
  try {
    port = api.runtime.connectNative(HOST_NAME);
    port.onDisconnect.addListener(() => {
      port = null;
    });
  } catch {
    port = null;
  }
  return port;
}

function sendEvent(payload) {
  if (payload.incognito) return;
  const p = ensurePort();
  if (!p) return;
  try {
    p.postMessage(payload);
  } catch {
    port = null;
  }
}

function extractDomain(url) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host.startsWith("www.") ? host.slice(4) : host;
  } catch {
    return null;
  }
}

async function reportActiveTab(tabId) {
  try {
    const tab = tabId
      ? await api.tabs.get(tabId)
      : (await api.tabs.query({ active: true, lastFocusedWindow: true }))[0];
    if (!tab || tab.incognito || !tab.url) return;
    if (!tab.url.startsWith("http://") && !tab.url.startsWith("https://")) return;

    const yt = youtubeCache.get(tab.id) || {};
    sendEvent({
      browser: BROWSER_NAME,
      url: tab.url,
      domain: extractDomain(tab.url),
      title: tab.title || yt.title || null,
      incognito: false,
      ytVideoId: yt.videoId || null,
      ytChannel: yt.channel || null,
      ytCategory: yt.category || null,
      ts: Math.floor(Date.now() / 1000)
    });
  } catch {
    // Ignore transient tab-query failures
  }
}

api.tabs.onActivated.addListener((info) => {
  reportActiveTab(info.tabId);
});

api.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (tab.active && (changeInfo.url || changeInfo.title || changeInfo.status === "complete")) {
    reportActiveTab(tabId);
  }
});

api.windows.onFocusChanged.addListener((windowId) => {
  if (windowId !== api.windows.WINDOW_ID_NONE) {
    reportActiveTab(null);
  }
});

api.runtime.onMessage.addListener((msg, sender) => {
  if (msg && msg.type === "holt-youtube-meta" && sender.tab && !sender.tab.incognito) {
    youtubeCache.set(sender.tab.id, {
      videoId: msg.videoId || null,
      channel: msg.channel || null,
      category: msg.category || null,
      title: msg.title || null
    });
    if (sender.tab.active) {
      reportActiveTab(sender.tab.id);
    }
  }
});
