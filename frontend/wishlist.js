// wishlist.js — Wishlist functionality for product cards.
// Displays an empty heart icon on each product card.
// Clicking toggles the heart and fills it with vibrant pink.
// State persists across page reloads via localStorage.

(function () {
  'use strict';

  const STORAGE_KEY = 'owl_wishlist';

  // ── Wishlist State Management ───────────────────────────────────────────────

  function getStoredWishlist() {
    try {
      const data = localStorage.getItem(STORAGE_KEY);
      return data ? new Set(JSON.parse(data).map(Number)) : new Set();
    } catch (_) {
      return new Set();
    }
  }

  function saveWishlist(set) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(set)));
    } catch (_) {}
  }

  const wishlist = getStoredWishlist();

  function isWishlisted(productId) {
    return wishlist.has(Number(productId));
  }

  function toggleWishlist(productId) {
    const id = Number(productId);
    const added = !wishlist.has(id);
    if (added) {
      wishlist.add(id);
    } else {
      wishlist.delete(id);
    }
    saveWishlist(wishlist);

    // Update all matching buttons in the DOM for this product ID
    document.querySelectorAll(`.wishlist-btn[data-product-id="${id}"]`).forEach(btn => {
      syncButtonState(btn, added);
    });

    window.dispatchEvent(new CustomEvent('wishlist-updated', {
      detail: { productId: id, isWishlisted: added, totalCount: wishlist.size }
    }));

    return added;
  }

  // ── Button DOM & Visuals ───────────────────────────────────────────────────

  function syncButtonState(btn, active) {
    if (active) {
      btn.classList.add('is-active');
      btn.setAttribute('aria-pressed', 'true');
      btn.setAttribute('aria-label', 'Remove from wishlist');
      btn.title = 'Remove from wishlist';
    } else {
      btn.classList.remove('is-active');
      btn.setAttribute('aria-pressed', 'false');
      btn.setAttribute('aria-label', 'Add to wishlist');
      btn.title = 'Add to wishlist';
    }
  }

  function createButton(productId) {
    const id = Number(productId);
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'wishlist-btn';
    btn.dataset.productId = String(id);

    // SVG Heart Icon (Outline by default; fills with pink when .is-active)
    btn.innerHTML = `
      <svg class="wishlist-icon" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
      </svg>
    `;

    syncButtonState(btn, isWishlisted(id));

    // Handle clicks: prevent modal from opening on product card click
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      toggleWishlist(id);
    });

    btn.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        e.stopPropagation();
        toggleWishlist(id);
      }
    });

    return btn;
  }

  // ── Auto-attach to Product Cards ───────────────────────────────────────────

  function attachToCard(card, productId) {
    if (!card || card.querySelector('.wishlist-btn')) return;
    const media = card.querySelector('.card-media') || card;
    const id = productId || card.dataset.productId || media.dataset.productId;
    if (!id) return;
    const btn = createButton(id);
    media.append(btn);
  }

  function scanAndAttach() {
    const grid = document.getElementById('product-grid');
    if (!grid) return;

    grid.querySelectorAll('.card').forEach(card => {
      if (card.querySelector('.wishlist-btn')) return;
      const media = card.querySelector('.card-media');
      const label = card.querySelector('.card-label');
      let id = card.dataset.productId || (media && media.dataset.productId);
      if (!id && label) {
        // e.g., "Shoes / 001" -> 1
        const parts = label.textContent.split('/');
        if (parts[1]) id = parseInt(parts[1].trim(), 10);
      }
      if (id) attachToCard(card, id);
    });
  }

  function initObserver() {
    const grid = document.getElementById('product-grid');
    if (!grid) return;

    scanAndAttach();

    // Observe changes to #product-grid so newly loaded products get buttons automatically
    const observer = new MutationObserver(() => scanAndAttach());
    observer.observe(grid, { childList: true, subtree: true });
  }

  // ── Bootstrap ───────────────────────────────────────────────────────────────

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initObserver);
  } else {
    initObserver();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  window.Wishlist = {
    isWishlisted,
    toggle: toggleWishlist,
    createButton,
    attachToCard,
    scan: scanAndAttach,
    getAll: () => Array.from(wishlist)
  };
})();

