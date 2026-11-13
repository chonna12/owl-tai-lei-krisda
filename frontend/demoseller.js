// demoseller.js — Fake / demo authentication for Seller One.
// Load this script INSTEAD OF login.js when you want to skip the login screen
// and auto-authenticate as the seeded demo seller.
//
// Usage in index.html:
//   <script src="demoseller.js"></script>   ← replaces login.js
//   <script src="approve.js"></script>
//
// The demo seller credentials are public test-only seed data.
// The backend still validates the password, session, and Seller role.

(function () {
  'use strict';

  // ── Demo credentials (public seed data only) ──────────────────────────────
  const DEMO_EMAIL    = 'seller1@owl.test';
  const DEMO_PASSWORD = 'OwlDemo123!';

  // ── Shared session promise (re-used across all calls) ─────────────────────
  let _session = null;

  // ── Plain JSON fetch ──────────────────────────────────────────────────────
  async function requestJson(url, options = {}) {
    const res  = await fetch(url, {
      ...options,
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', ...options.headers },
    });
    const data = await res.json();
    if (!res.ok) throw Object.assign(new Error(data.error || 'Request failed'), { status: res.status });
    return data;
  }

  // ── Core: ensure a valid demo session exists ──────────────────────────────
  // Returns the user object. Safe to call concurrently — only one login happens.
  function ensureDemoSession() {
    if (!_session) {
      _session = (async () => {
        // 1. Try the existing cookie first (avoids an extra round-trip)
        try {
          const { user } = await requestJson('/api/me');
          if (user.email === DEMO_EMAIL && user.canSell) return user;
        } catch (e) {
          if (e.status !== 401) throw e;
        }
        // 2. Log in with demo credentials
        const { user } = await requestJson('/api/login', {
          method: 'POST',
          body: JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
        });
        return user;
      })().catch(err => { _session = null; throw err; });
    }
    return _session;
  }

  // ── Authenticated fetch helper ─────────────────────────────────────────────
  // Auto-retries once if the session cookie expires mid-session.
  async function sellerRequest(url, options = {}) {
    await ensureDemoSession();
    try {
      return await requestJson(url, options);
    } catch (err) {
      if (err.status !== 401) throw err;
      _session = null;
      await ensureDemoSession();
      return requestJson(url, options);
    }
  }

  // ── Update the header user chip ───────────────────────────────────────────
  function updateHeader(user) {
    const nameEl   = document.getElementById('demo-status');
    const avatarEl = document.querySelector('.avatar');
    if (nameEl)   nameEl.textContent   = (user?.name ?? 'Demo Seller One') + ' · Demo mode';
    if (avatarEl) avatarEl.textContent = 'DS';
  }

  // ── Hide the login overlay ────────────────────────────────────────────────
  function hideLoginOverlay() {
    const overlay = document.getElementById('login-overlay');
    if (!overlay) return;
    overlay.style.transition = 'opacity .2s';
    overlay.style.opacity    = '0';
    setTimeout(() => overlay.remove(), 220);
    const filters = document.querySelector('.filters');
    if (filters) filters.removeAttribute('inert');
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────
  async function init() {
    try {
      const user = await ensureDemoSession();
      updateHeader(user);
      hideLoginOverlay();
    } catch (err) {
      const statusEl = document.getElementById('demo-status');
      if (statusEl) statusEl.textContent = 'Demo sign-in failed: ' + err.message;
      console.error('[demoseller] auto-login failed:', err);
    }
  }

  // ── Expose on window so approve.js can call sellerRequest ─────────────────
  window.DemoSeller = { ensureDemoSession, sellerRequest, requestJson };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

