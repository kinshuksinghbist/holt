(() => {
  try {
    const micro = window.ytInitialPlayerResponse?.microformat?.playerMicroformatRenderer;
    const details = window.ytInitialPlayerResponse?.videoDetails;
    const params = new URLSearchParams(window.location.search);
    window.postMessage(
      {
        source: "holt-yt-page",
        videoId: details?.videoId || params.get("v") || null,
        channel: micro?.ownerChannelName || details?.author || null,
        category: micro?.category || null,
        title: micro?.title?.simpleText || details?.title || document.title || null
      },
      "*"
    );
  } catch {
    // Fallback handled by content script
  }
})();
