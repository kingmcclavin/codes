// Relays observer messages to the native handler (SafariWebExtensionHandler),
// which runs the same Swift policy engine as the app. Content scripts can't
// call sendNativeMessage directly.
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  browser.runtime
    .sendNativeMessage('application.id', message)
    .then(sendResponse)
    .catch(() => sendResponse({ decision: 'allow' })); // fail open: never break Instagram
  return true; // async response
});
