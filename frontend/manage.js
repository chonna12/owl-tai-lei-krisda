// manage.js — Profile menu dropdown ("Your product", "Your wishlist", "My order") and Wishlist page.
// All HTML markup lives in index.html, all styles live in styles.css.

(function () {
  'use strict';

  const $ = id => document.getElementById(id);

  // ── Template Renderer ────────────────────────────────────────────────────────
  function renderTemplate(templateId) {
    const page = document.querySelector('.page') || document.body;
    const tpl = document.getElementById(templateId);
    if (!tpl) throw new Error(`Template #${templateId} not found`);
    page.innerHTML = '';
    page.appendChild(tpl.content.cloneNode(true));
    return page;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  async function getCurrentUser() {
    if (window.currentUser && window.currentUser.name) return window.currentUser;
    if (window.DemoSeller) {
      try {
        const user = await window.DemoSeller.ensureDemoSession();
        window.currentUser = user;
        return user;
      } catch (_) {}
    }
    try {
      const res = await fetch('/api/me', { credentials: 'same-origin' });
      if (res.ok) {
        const data = await res.json();
        window.currentUser = data.user || null;
      }
    } catch (_) {
      window.currentUser = null;
    }
    return window.currentUser;
  }

  function getWishlistedIds() {
    const ids = new Set();
    if (window.Wishlist && typeof window.Wishlist.getAll === 'function') {
      window.Wishlist.getAll().forEach(id => ids.add(Number(id)));
    } else {
      try {
        const stored = JSON.parse(localStorage.getItem('owl_wishlist') || '[]');
        stored.forEach(id => ids.add(Number(id)));
      } catch (_) {}
    }
    return ids;
  }

  // ── Profile Dropdown Menu Setup ──────────────────────────────────────────────
  let menuHideTimer = null;

  function setupProfileMenu() {
    const wrapper = $('profile-dropdown-wrapper');
    const menu = $('profile-dropdown-menu');
    const avatar = document.querySelector('.avatar');
    const userName = document.querySelector('.user-name');

    if (!wrapper || !menu || !avatar) return;

    // Prevent multiple initializations on the same wrapper
    if (wrapper.dataset.menuBound === 'true') return;
    wrapper.dataset.menuBound = 'true';

    // Remove legacy title tooltips from approve.js to prevent native browser tooltip
    avatar.removeAttribute('title');
    if (userName) userName.removeAttribute('title');

    // Clone avatar to strip existing direct-click handlers from approve.js
    const cleanAvatar = avatar.cloneNode(true);
    cleanAvatar.removeAttribute('title');
    avatar.parentNode.replaceChild(cleanAvatar, avatar);

    function openMenu() {
      clearTimeout(menuHideTimer);
      menu.classList.add('is-open');
    }

    function closeMenuWithDelay() {
      clearTimeout(menuHideTimer);
      menuHideTimer = setTimeout(() => {
        menu.classList.remove('is-open');
      }, 180);
    }

    function closeMenuImmediately() {
      clearTimeout(menuHideTimer);
      menu.classList.remove('is-open');
    }

    // Hover interactions
    wrapper.addEventListener('mouseenter', openMenu);
    wrapper.addEventListener('mouseleave', closeMenuWithDelay);

    if (userName) {
      userName.addEventListener('mouseenter', openMenu);
      userName.addEventListener('mouseleave', closeMenuWithDelay);
    }

    // Click to toggle on mobile / pointer
    cleanAvatar.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (menu.classList.contains('is-open')) {
        closeMenuImmediately();
      } else {
        openMenu();
      }
    });

    document.addEventListener('click', (e) => {
      if (!wrapper.contains(e.target) && (!userName || !userName.contains(e.target))) {
        closeMenuImmediately();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeMenuImmediately();
    });

    // ── Menu Action Listeners ──────────────────────────────────────────────────
    const productBtn = menu.querySelector('#menu-your-product');
    const wishlistBtn = menu.querySelector('#menu-your-wishlist');
    const myOrderBtn = menu.querySelector('#menu-my-order');

    productBtn?.addEventListener('click', async (e) => {
      e.preventDefault();
      closeMenuImmediately();
      await navigateToYourProduct();
    });

    wishlistBtn?.addEventListener('click', (e) => {
      e.preventDefault();
      closeMenuImmediately();
      showWishlistPage();
    });

    myOrderBtn?.addEventListener('click', (e) => {
      e.preventDefault();
      closeMenuImmediately();
      if (typeof window.showBuyerOrdersPage === 'function') {
        window.showBuyerOrdersPage();
      }
    });
  }

  // ── Navigation 1: "Your product" (My Sell Orders) ───────────────────────────
  async function navigateToYourProduct() {
    const user = await getCurrentUser();
    if (!user || !user.canSell) {
      alert('Only sellers have sell orders. Your account is currently a Buyer.');
      return;
    }

    if (typeof window.showMyOrders === 'function') {
      window.showMyOrders();
    } else {
      const page = renderTemplate('tpl-my-orders');
      page.querySelector('#mo-back')?.addEventListener('click', () => window.location.reload());
    }
  }

  // ── Navigation 2: "Your wishlist" ───────────────────────────────────────────
  async function showWishlistPage() {
    const page = renderTemplate('tpl-wishlist');
    page.querySelector('#wl-back')?.addEventListener('click', () => window.location.reload());
    page.querySelector('#wl-empty-explore')?.addEventListener('click', () => window.location.reload());
    await loadWishlistItems();
  }

  // ── Load & Render Wishlisted Products ───────────────────────────────────────
  async function loadWishlistItems() {
    const loadingEl = $('wl-loading');
    const gridEl = $('wl-grid');
    const emptyEl = $('wl-empty');
    const countBadge = $('wl-count-badge');
    const subEl = $('wl-sub');

    if (!gridEl) return;

    const wishlistedIds = getWishlistedIds();

    try {
      const res = await fetch('/api/wishlist', { credentials: 'same-origin' });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data.items)) {
          data.items.forEach(it => wishlistedIds.add(Number(it.product_id)));
        }
      }
    } catch (_) {}

    let allProducts = [];
    try {
      const res = await fetch('/api/products', { credentials: 'same-origin' });
      if (res.ok) {
        const data = await res.json();
        allProducts = Array.isArray(data.products) ? data.products : [];
      }
    } catch (_) {}

    if (loadingEl) loadingEl.remove();

    function getFilteredProducts() {
      return allProducts.filter(p => wishlistedIds.has(Number(p.product_id)));
    }

    function renderView() {
      const items = getFilteredProducts();
      gridEl.innerHTML = '';

      if (items.length === 0) {
        if (emptyEl) emptyEl.hidden = false;
        gridEl.hidden = true;
        if (countBadge) countBadge.textContent = '0 items';
        if (subEl) subEl.textContent = 'You have no items in your wishlist yet.';
        return;
      }

      if (emptyEl) emptyEl.hidden = true;
      gridEl.hidden = false;
      if (countBadge) countBadge.textContent = `${items.length} item${items.length > 1 ? 's' : ''}`;
      if (subEl) subEl.textContent = `You have ${items.length} saved piece${items.length > 1 ? 's' : ''} in your wishlist.`;

      items.forEach(product => {
        let cardLi;
        if (typeof window.makeCard === 'function') {
          cardLi = window.makeCard(product);
        } else {
          cardLi = createCardElement(product);
        }
        gridEl.appendChild(cardLi);
      });
    }

    renderView();

    const onWishlistUpdate = (e) => {
      const { productId, isWishlisted } = e.detail || {};
      if (!isWishlisted && productId) {
        wishlistedIds.delete(Number(productId));
        const cardLi = gridEl.querySelector(`.card[data-product-id="${productId}"]`)?.closest('li');
        if (cardLi) {
          cardLi.classList.add('card-removing');
          setTimeout(renderView, 230);
        } else {
          renderView();
        }
      }
    };

    window.addEventListener('wishlist-updated', onWishlistUpdate);
  }

  // Fallback card builder if makeCard is unavailable
  function createCardElement(product) {
    const li = document.createElement('li');
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'card';
    card.dataset.productId = String(product.product_id);
    card.addEventListener('click', () => {
      if (typeof window.showActionModal === 'function') {
        window.showActionModal(product);
      }
    });

    const media = document.createElement('div');
    media.className = 'card-media tint-' + (product.product_id % 5);
    media.dataset.productId = String(product.product_id);

    const label = document.createElement('span');
    label.className = 'card-label';
    label.textContent = `${product.category} / ${String(product.product_id).padStart(3, '0')}`;
    media.append(label);

    if (typeof product.image === 'string' && /^(data:image\/|https?:\/\/|\/)/.test(product.image)) {
      const img = document.createElement('img');
      img.className = 'card-photo';
      img.src = product.image;
      img.alt = product.name;
      media.append(img);
    } else {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 'card-icon');
      const iconId = product.category === 'Shoes' ? 'icon-shoe' : (product.category === 'Clothing' ? 'icon-tee' : 'icon-bag');
      svg.setAttribute('viewBox', iconId === 'icon-shoe' ? '0 0 120 70' : '0 0 100 90');
      svg.setAttribute('aria-hidden', 'true');
      const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
      use.setAttribute('href', '#' + iconId);
      svg.append(use);
      media.append(svg);
    }

    if (window.Wishlist && typeof window.Wishlist.createButton === 'function') {
      media.append(window.Wishlist.createButton(product.product_id));
    }

    const body = document.createElement('div');
    body.className = 'card-body';
    const brand = document.createElement('span');
    brand.className = 'card-brand';
    brand.textContent = product.brand_name;
    const name = document.createElement('span');
    name.className = 'card-name';
    name.textContent = product.name;
    body.append(brand, name);

    card.append(media, body);
    li.append(card);
    return li;
  }

  // ── Initialization ───────────────────────────────────────────────────────────
  function init() {
    setupProfileMenu();

    const observer = new MutationObserver(() => {
      const wrapper = $('profile-dropdown-wrapper');
      if (wrapper && wrapper.dataset.menuBound !== 'true') {
        setupProfileMenu();
      }
    });

    const userDiv = document.querySelector('.user');
    if (userDiv) {
      observer.observe(userDiv, { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Expose public API
  window.Manage = {
    setupProfileMenu,
    showWishlistPage,
    navigateToYourProduct,
  };
  window.showWishlistPage = showWishlistPage;
  window.showYourProducts = navigateToYourProduct;
})();
