// Chrome API shim for WKWebView
// Replaces chrome.runtime and chrome.storage with WKWebView message handlers

(function() {
  'use strict';

  // --- Platform flag for iOS WKWebView ---
  // offscreen.js checks this to disable features unsupported in WKWebView (e.g. Workers for proofs)
  window.__CELARI_IOS = true;

  // --- Node.js globals polyfill (needed by esbuild bundle) ---
  if (typeof process === 'undefined') {
    window.process = {
      env: { NODE_ENV: 'production', NODE_DEBUG: '' },
      version: 'v20.0.0',
      versions: { node: '20.0.0' },
      platform: 'darwin',
      pid: 1,
      nextTick: function(fn) { Promise.resolve().then(fn); },
      noDeprecation: true,
      throwDeprecation: false,
      traceDeprecation: false,
      browser: true,
      cwd: function() { return '/'; },
      argv: [],
      stdout: { write: function() {} },
      stderr: { write: function() {} }
    };
  }

  if (typeof global === 'undefined') {
    window.global = window;
  }

  // NOTE: Buffer is provided by a separate buffer-polyfill.js (feross/buffer)
  // injected by PXEBridge.swift as a WKUserScript after this shim.

  // --- fetch() polyfill for file:// URLs (needed by WASM loaders) ---
  // WKWebView's fetch() doesn't work with file:// URLs.
  // Override fetch to use XMLHttpRequest for local files.
  var _origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = (input instanceof Request) ? input.url : String(input);
    if (url.startsWith('file://')) {
      return new Promise(function(resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.responseType = 'arraybuffer';
        xhr.onload = function() {
          if (xhr.status === 0 || (xhr.status >= 200 && xhr.status < 300)) {
            resolve(new Response(xhr.response, {
              status: 200,
              statusText: 'OK',
              headers: { 'Content-Type': 'application/wasm' }
            }));
          } else {
            reject(new Error('XHR failed: ' + xhr.status + ' for ' + url));
          }
        };
        xhr.onerror = function() {
          reject(new Error('XHR error loading ' + url));
        };
        xhr.send();
      });
    }
    return _origFetch.apply(this, arguments);
  };
  console.log('[PXE-Shim] fetch() polyfill for file:// URLs installed');

  // --- Worker polyfill (WKWebView does not support Web Workers) ---
  // Aztec SDK uses workers for zk-proof computation.
  // Since WKWebView doesn't support Workers, we create a no-op shim
  // that logs the attempt. The SDK may have fallback single-threaded paths.
  if (typeof Worker === 'undefined' || true) {
    var _OrigWorker = typeof Worker !== 'undefined' ? Worker : null;
    window.Worker = function(url, options) {
      console.warn('[PXE-Shim] Worker creation intercepted (unsupported in WKWebView): ' + url);
      // Store for potential future use
      this._url = url;
      this._options = options;
      this._listeners = {};
      this.postMessage = function(msg) {
        console.warn('[PXE-Shim] Worker.postMessage called (no-op)');
      };
      this.terminate = function() {};
      this.addEventListener = function(type, fn) {
        if (!this._listeners[type]) this._listeners[type] = [];
        this._listeners[type].push(fn);
      };
      this.removeEventListener = function(type, fn) {
        if (this._listeners[type]) {
          this._listeners[type] = this._listeners[type].filter(function(f) { return f !== fn; });
        }
      };
      // Simulate immediate error so SDK can handle fallback
      var self = this;
      setTimeout(function() {
        var errorEvent = new ErrorEvent('error', {
          message: 'Workers not supported in WKWebView',
          filename: String(url),
          lineno: 0
        });
        if (typeof self.onerror === 'function') self.onerror(errorEvent);
        if (self._listeners['error']) {
          self._listeners['error'].forEach(function(fn) { fn(errorEvent); });
        }
      }, 0);
    };
    console.log('[PXE-Shim] Worker polyfill installed (no-op, WKWebView limitation)');
  }

  // --- chrome.runtime shim ---
  if (!window.chrome) window.chrome = {};
  if (!window.chrome.runtime) window.chrome.runtime = {};
  window.chrome.runtime.id = 'celari-ios';

  const _messageHandlers = [];
  window._messageHandlers = _messageHandlers; // Expose for diagnostics

  window.chrome.runtime.onMessage = {
    addListener: function(fn) {
      _messageHandlers.push(fn);
      console.log('[PXE-Shim] onMessage listener registered (total: ' + _messageHandlers.length + ')');
      // Notify Swift that the JS message handler is ready (ESM modules load after didFinish)
      if (_messageHandlers.length === 1) {
        try {
          window.webkit.messageHandlers.pxeBridge.postMessage(JSON.stringify({ _type: 'JS_HANDLER_READY' }));
        } catch(e) {}
      }
    }
  };

  // chrome.runtime.sendMessage → forward to Swift (for WC events, etc.)
  window.chrome.runtime.sendMessage = function(msg, callback) {
    if (msg && msg.type && msg.type.startsWith('WC_')) {
      // WalletConnect events go to Swift
      window.webkit.messageHandlers.pxeEvent.postMessage(JSON.stringify(msg));
    }
    if (callback) callback({ success: true });
  };

  // --- chrome.storage shim ---
  if (!window.chrome.storage) window.chrome.storage = {};

  window._pendingStorageCallbacks = {};

  function storageGet(area, keys, callback) {
    var id = 'sc_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    window._pendingStorageCallbacks[id] = callback;
    var keysArray = typeof keys === 'string' ? [keys] : (Array.isArray(keys) ? keys : Object.keys(keys));
    window.webkit.messageHandlers.pxeStorage.postMessage(JSON.stringify({
      action: 'get',
      area: area,
      keys: keysArray,
      callbackId: id
    }));
  }

  function storageSet(area, data, callback) {
    var id = 'sc_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    if (callback) window._pendingStorageCallbacks[id] = callback;
    window.webkit.messageHandlers.pxeStorage.postMessage(JSON.stringify({
      action: 'set',
      area: area,
      data: data,
      callbackId: id
    }));
  }

  function storageRemove(area, keys, callback) {
    var id = 'sc_' + Date.now() + '_' + Math.random().toString(36).slice(2);
    if (callback) window._pendingStorageCallbacks[id] = callback;
    var keysArray = typeof keys === 'string' ? [keys] : keys;
    window.webkit.messageHandlers.pxeStorage.postMessage(JSON.stringify({
      action: 'remove',
      area: area,
      keys: keysArray,
      callbackId: id
    }));
  }

  window._deliverStorageCallback = function(callbackId, resultJson) {
    var cb = window._pendingStorageCallbacks[callbackId];
    if (cb) {
      delete window._pendingStorageCallbacks[callbackId];
      try {
        cb(JSON.parse(resultJson));
      } catch(e) {
        cb({});
      }
    }
  };

  window.chrome.storage.local = {
    get: function(keys, cb) { storageGet('local', keys, cb); },
    set: function(data, cb) { storageSet('local', data, cb); },
    remove: function(keys, cb) { storageRemove('local', keys, cb); }
  };

  window.chrome.storage.session = {
    get: function(keys, cb) { storageGet('session', keys, cb); },
    set: function(data, cb) { storageSet('session', data, cb); },
    remove: function(keys, cb) { storageRemove('session', keys, cb); }
  };

  // --- chrome.alarms shim (no-op) ---
  if (!window.chrome.alarms) window.chrome.alarms = {};
  window.chrome.alarms.create = function() {};
  window.chrome.alarms.onAlarm = { addListener: function() {} };

  // --- chrome.windows / chrome.action shim (no-op) ---
  if (!window.chrome.windows) window.chrome.windows = {};
  window.chrome.windows.create = function() {};
  if (!window.chrome.action) window.chrome.action = {};
  window.chrome.action.openPopup = function() {};

  // --- Bridge: Swift → JS message delivery ---

  window._pendingBridgeCallbacks = {};

  // Called by Swift to send a PXE message to the offscreen.js handler
  window._receiveFromSwift = function(msgJson) {
    console.log('[PXE-Shim] _receiveFromSwift called, type=' + (JSON.parse(msgJson).type || '?'));
    var msg;
    try {
      msg = JSON.parse(msgJson);
    } catch (parseErr) {
      console.error('[PXE-Shim] JSON parse error:', parseErr.message);
      return;
    }
    var messageId = msg._messageId;
    delete msg._messageId;

    console.log('[PXE-Shim] Dispatching to ' + _messageHandlers.length + ' handler(s), type=' + msg.type);

    for (var i = 0; i < _messageHandlers.length; i++) {
      var handler = _messageHandlers[i];
      try {
        var result = handler(msg, { id: 'celari-ios' }, function(response) {
          // Send response back to Swift
          console.log('[PXE-Shim] sendResponse called for type=' + msg.type);
          var resp = response || {};
          resp._messageId = messageId;
          window.webkit.messageHandlers.pxeBridge.postMessage(JSON.stringify(resp));
        });
        console.log('[PXE-Shim] handler returned: ' + result + ' for type=' + msg.type);
        if (result === true) return; // async response — will call sendResponse later
      } catch (handlerErr) {
        console.error('[PXE-Shim] handler threw for type=' + msg.type + ':', handlerErr.message || handlerErr);
      }
    }
  };

  console.log('[PXE-Shim] Chrome API shim loaded for iOS WKWebView');
})();
