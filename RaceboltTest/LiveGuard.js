/* Injected at document start in every frame of the live WKWebView.
 * Defence in depth alongside native navigation and WKContentRuleList blocking.
 * This is not a server-side sandbox; new checkout integrations need rechecking.
 */
(() => {
  'use strict';
  const riskyAction = /checkout|place[-_]?order|process[-_]?payment|create[-_]?order|approve[-_]?order|capture[-_]?order|payment[-_]?intent|ppc[-_]|ppcp|stripe|wcpay/i;
  const riskyPath = /\/(checkout|order-pay|order-received|pay-for-order|add-payment-method)(\/|$)/i;
  const paymentHost = /(^|\.)(paypal\.com|paypalobjects\.com|stripe\.com|stripe\.network|klarna\.com|squareup\.com|apple-pay-gateway\.apple\.com)$/i;
  const checkoutControls = 'form.checkout, form.woocommerce-checkout, #place_order, [name="woocommerce_checkout_place_order"], .checkout-button, .wc-block-cart__submit-button, .wc-block-components-checkout-place-order-button, .ppc-button-wrapper, [id^="ppc-button"], [id^="paypal-button"], .payment_request_button, .wcpay-payment-request-wrapper';
  function decoded(value) {
    let s = String(value || '');
    for (let i = 0; i < 3; i++) { try { const next = decodeURIComponent(s); if (next === s) break; s = next; } catch (_) { break; } }
    return s;
  }
  function blockedURL(value) {
    try {
      const u = new URL(typeof value === 'string' ? value : (value instanceof URL ? value.href : value.url), location.href);
      if (paymentHost.test(u.hostname) || riskyPath.test(decoded(u.pathname))) return true;
      const params = new URLSearchParams(decoded(u.search));
      for (const [key, val] of params) {
        if (['wc-ajax', 'wc_ajax', 'action', 'rest_route'].includes(key.toLowerCase()) && riskyAction.test(val)) return true;
        if (key.toLowerCase() === 'rest_route' && riskyPath.test(val)) return true;
      }
      return false;
    } catch (_) { return true; }
  }
  function blockedBody(body) {
    if (!body) return false;
    if (typeof body === 'string') {
      const text = decoded(body);
      if (/woocommerce_checkout_place_order|woocommerce-process-checkout-nonce/i.test(text)) return true;
      try {
        const obj = JSON.parse(text);
        return Object.entries(obj).some(([k, v]) => ['action', 'wc-ajax', 'wc_ajax'].includes(k) && riskyAction.test(String(v)));
      } catch (_) { body = new URLSearchParams(text); }
    }
    if (body instanceof FormData || body instanceof URLSearchParams) {
      for (const [key, val] of body) {
        if (/woocommerce_checkout_place_order|woocommerce-process-checkout-nonce/i.test(key)) return true;
        if (['action', 'wc-ajax', 'wc_ajax'].includes(key) && riskyAction.test(String(val))) return true;
      }
    }
    return false;
  }
  let lastNotice = 0;
  function notice() {
    if (Date.now() - lastNotice < 1200) return;
    lastNotice = Date.now();
    try { window.webkit.messageHandlers.raceboltBlocked.postMessage('Checkout is disabled in Racebolt Test.'); } catch (_) { /* Browser tests have no native handler. */ }
  }
  function reject() { notice(); return new DOMException('Checkout disabled in Racebolt Test', 'SecurityError'); }
  document.addEventListener('click', (event) => {
    const target = event.target instanceof Element ? event.target : event.target.parentElement;
    if (!target) return;
    const link = target.closest('a[href]');
    if (target.closest(checkoutControls) || (link && blockedURL(link.href))) {
      event.preventDefault(); event.stopImmediatePropagation(); notice();
    }
  }, true);
  function blockedForm(form) {
    return form.matches(checkoutControls) || blockedURL(form.action || location.href) || blockedBody(new FormData(form));
  }
  document.addEventListener('submit', (event) => {
    if (event.target instanceof HTMLFormElement && blockedForm(event.target)) {
      event.preventDefault(); event.stopImmediatePropagation(); notice();
    }
  }, true);
  for (const method of ['submit', 'requestSubmit']) {
    const original = HTMLFormElement.prototype[method];
    if (original) HTMLFormElement.prototype[method] = function (...args) {
      if (blockedForm(this)) throw reject();
      return original.apply(this, args);
    };
  }
  const originalFetch = window.fetch;
  if (originalFetch) window.fetch = function (input, init) {
    if (blockedURL(input) || blockedBody(init && init.body)) return Promise.reject(reject());
    // Read Request bodies before passing them through, so a hidden admin-ajax action cannot bypass inspection.
    if (input instanceof Request && !['GET', 'HEAD'].includes(input.method.toUpperCase())) {
      return input.clone().text().then((text) => { if (blockedBody(text)) throw reject(); return originalFetch.call(this, input, init); });
    }
    return originalFetch.call(this, input, init);
  };
  const open = XMLHttpRequest.prototype.open;
  const send = XMLHttpRequest.prototype.send;
  const requests = new WeakMap();
  XMLHttpRequest.prototype.open = function (method, url, ...args) {
    if (blockedURL(url)) throw reject();
    requests.set(this, String(url));
    return open.call(this, method, url, ...args);
  };
  XMLHttpRequest.prototype.send = function (body) {
    if (blockedURL(requests.get(this) || location.href) || blockedBody(body)) throw reject();
    return send.call(this, body);
  };
  const beacon = navigator.sendBeacon;
  if (beacon) navigator.sendBeacon = function (url, data) {
    if (blockedURL(url) || blockedBody(data)) { notice(); return false; }
    return beacon.call(this, url, data);
  };
  function hideExpressPayment() {
    document.querySelectorAll('.ppc-button-wrapper, [id^="ppc-button"], [id^="paypal-button"], .payment_request_button, .wcpay-payment-request-wrapper').forEach((el) => {
      el.hidden = true;
      el.style.setProperty('display', 'none', 'important');
    });
  }
  function ready() {
    hideExpressPayment();
    let queued = false;
    new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; hideExpressPayment(); });
    }).observe(document.documentElement, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true }); else ready();
})();