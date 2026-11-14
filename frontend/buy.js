// buy.js — Buy workflow, queue-based listing selection, order placement (Pay or Cancel), and "My order" page.
// All HTML templates live in index.html, all styles live in styles.css.

(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const ICONS = { Shoes: 'icon-shoe', Clothing: 'icon-tee', Accessories: 'icon-bag' };
  const ORDERS_STORAGE_KEY = 'owl_buyer_orders';

  // ── Template Renderer ────────────────────────────────────────────────────────
  function renderTemplate(templateId) {
    const page = document.querySelector('.page') || document.body;
    const tpl = document.getElementById(templateId);
    if (!tpl) throw new Error(`Template #${templateId} not found`);
    page.innerHTML = '';
    page.appendChild(tpl.content.cloneNode(true));
    return page;
  }

  // ── Storage Helpers for Buyer Orders ─────────────────────────────────────────
  function getLocalOrders() {
    try {
      const data = localStorage.getItem(ORDERS_STORAGE_KEY);
      return data ? JSON.parse(data) : [];
    } catch (_) {
      return [];
    }
  }

  function saveLocalOrders(orders) {
    try {
      localStorage.setItem(ORDERS_STORAGE_KEY, JSON.stringify(orders));
    } catch (_) {}
  }

  function addLocalOrder(order) {
    const orders = getLocalOrders();
    orders.unshift(order);
    saveLocalOrders(orders);
    return order;
  }

  function updateLocalOrderStatus(orderId, newStatus) {
    const orders = getLocalOrders();
    const target = orders.find(o => String(o.order_id) === String(orderId));
    if (target) {
      target.status = newStatus;
      if (newStatus === 'paid') target.paid_at = new Date().toISOString();
      if (newStatus === 'cancelled') target.cancelled_at = new Date().toISOString();
      saveLocalOrders(orders);
    }
    return target;
  }

  // ── Visual Helpers ───────────────────────────────────────────────────────────
  function renderThumb(container, product) {
    if (!container) return;
    container.innerHTML = '';
    if (typeof product.image === 'string' && /^(data:image\/|https?:\/\/|\/)/.test(product.image)) {
      const img = document.createElement('img');
      img.src = product.image;
      img.alt = product.name || '';
      img.className = 'item-photo';
      container.append(img);
    } else {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 'card-icon');
      const iconId = ICONS[product.category] || 'icon-bag';
      svg.setAttribute('viewBox', iconId === 'icon-shoe' ? '0 0 120 70' : '0 0 100 90');
      svg.setAttribute('aria-hidden', 'true');
      const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
      use.setAttribute('href', '#' + iconId);
      svg.append(use);
      container.append(svg);
    }
  }

  // ── Intercept Modal "Buy" Button ─────────────────────────────────────────────
  function setupModalBuyInterception() {
    document.addEventListener('click', (e) => {
      const buyBtn = e.target.closest('#modal-btn-buy');
      if (buyBtn) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();

        const overlay = $('action-modal-overlay');
        if (overlay) overlay.classList.remove('is-open');

        const product = window.currentModalProduct;
        if (product) {
          showBuyPage(product);
        } else {
          const title = $('modal-product-title')?.textContent;
          const brand = $('modal-product-brand')?.textContent;
          showBuyPage({
            product_id: 1,
            name: title || 'Product',
            brand_name: brand || 'Brand',
            category: 'Shoes',
          });
        }
      }
    }, true);

    document.addEventListener('click', (e) => {
      const card = e.target.closest('.card');
      if (card && card.dataset.productId) {
        const id = Number(card.dataset.productId);
        const name = card.querySelector('.card-name')?.textContent;
        const brand = card.querySelector('.card-brand')?.textContent;
        const img = card.querySelector('.card-photo')?.src;
        window.currentModalProduct = {
          product_id: id,
          name: name || '',
          brand_name: brand || '',
          image: img || null,
        };
      }
    }, true);

    const origModal = window.showActionModal;
    if (typeof origModal === 'function') {
      window.showActionModal = async function (product) {
        window.currentModalProduct = product;
        await origModal.apply(this, arguments);
        const buyBtn = $('modal-btn-buy');
        if (buyBtn) {
          buyBtn.onclick = (e) => {
            e.preventDefault();
            const overlay = $('action-modal-overlay');
            if (overlay) overlay.classList.remove('is-open');
            showBuyPage(product);
          };
        }
      };
    }
  }

  // ── 1. Buy Page (Queue of Seller Listings) ───────────────────────────────────
  async function showBuyPage(product) {
    const page = renderTemplate('tpl-buy');

    page.querySelector('#bp-product-name').textContent = product.name;
    page.querySelector('#bp-product-brand').textContent = product.brand_name || '';
    renderThumb(page.querySelector('#bp-chip-thumb'), product);

    page.querySelector('#bp-cancel')?.addEventListener('click', () => window.location.reload());

    let selectedCondition = 'new';
    const tabNew = page.querySelector('#tab-buy-new');
    const tabUsed = page.querySelector('#tab-buy-used');
    const container = page.querySelector('#bp-listings-container');
    const emptyBox = page.querySelector('#bp-listings-empty');
    const emptyTitle = page.querySelector('#bp-empty-title');

    let allListings = [];
    try {
      const res = await fetch(`/api/products/${product.product_id}/market`, { credentials: 'same-origin' });
      if (res.ok) {
        const data = await res.json();
        allListings = Array.isArray(data.listings) ? data.listings : [];
      }
    } catch (_) {}

    // Sample fallback listings if none seeded for this product
    if (allListings.length === 0) {
      allListings = [
        {
          offer_id: 101,
          variant_id: 1,
          size: '9',
          color: 'Standard',
          condition: 'new',
          display_price: 1070.00,
          condition_notes: 'Brand new in original box',
        },
        {
          offer_id: 102,
          variant_id: 1,
          size: '9',
          color: 'Standard',
          condition: 'new',
          display_price: 1150.00,
          condition_notes: 'Brand new, sealed tags',
        },
        {
          offer_id: 103,
          variant_id: 1,
          size: '9',
          color: 'Standard',
          condition: 'new',
          display_price: 1200.00,
          condition_notes: 'First hand from authorized store',
        },
        {
          offer_id: 201,
          variant_id: 1,
          size: '9',
          color: 'Standard',
          condition: 'used',
          display_price: 749.00,
          defects: 'Light crease on toe box, worn twice with receipt',
        },
        {
          offer_id: 202,
          variant_id: 1,
          size: '9',
          color: 'Standard',
          condition: 'used',
          display_price: 680.00,
          defects: 'Small scuff mark on rear heel',
        }
      ];
    }

    function renderListings() {
      container.innerHTML = '';

      const filtered = allListings.filter(item => {
        const c = (item.condition || '').toLowerCase();
        return selectedCondition === 'new'
          ? (c === 'new' || c === 'one hand' || c === 'first hand')
          : (c === 'used' || c === 'second hand');
      });

      // Sort: earliest listed on TOP, subsequent items UNDER
      filtered.sort((a, b) => Number(a.offer_id || 0) - Number(b.offer_id || 0));

      if (filtered.length === 0) {
        if (emptyBox) {
          emptyBox.hidden = false;
          if (emptyTitle) emptyTitle.textContent = `No ${selectedCondition === 'new' ? 'One hand' : 'Second hand'} listings yet`;
        }
        return;
      }

      if (emptyBox) emptyBox.hidden = true;

      filtered.forEach((item, index) => {
        const isTop = (index === 0);
        const card = document.createElement('div');
        card.className = `bp-listing-item ${isTop ? 'bp-listing-top' : 'bp-listing-queued'}`;

        const priceDisplay = Number(item.display_price || item.price || 0).toFixed(2);

        card.innerHTML = `
          <div class="bp-item-header">
            <span class="bp-badge ${isTop ? 'bp-badge-top' : 'bp-badge-queued'}">
              ${isTop ? '⭐ #1 First in line · Available to Buy' : `🔒 #${index + 1} In Queue`}
            </span>
            <span class="${isTop ? 'bp-item-price' : 'bp-item-price-muted'}">${priceDisplay} THB</span>
          </div>

          <div class="bp-item-details">
            <span><strong>Size:</strong> ${item.size || 'Standard'}</span>
            ${item.color ? `<span><strong>Color:</strong> ${item.color}</span>` : ''}
            ${item.defects ? `<span class="bp-defect">⚠ ${item.defects}</span>` : ''}
            ${item.condition_notes ? `<span>${item.condition_notes}</span>` : ''}
          </div>

          ${isTop ? `
            <button type="button" class="bp-btn-buy" id="btn-buy-top-item">
              Buy Now · ${priceDisplay} THB →
            </button>
          ` : `
            <div class="bp-queue-lock-notice">
              🔒 In queue — only the top listing can be purchased
            </div>
          `}
        `;

        if (isTop) {
          card.querySelector('#btn-buy-top-item')?.addEventListener('click', () => {
            handlePlaceOrder(product, item);
          });
        }

        container.appendChild(card);
      });
    }

    tabNew?.addEventListener('click', () => {
      selectedCondition = 'new';
      tabNew.classList.add('sf-tab-active');
      tabUsed?.classList.remove('sf-tab-active');
      renderListings();
    });

    tabUsed?.addEventListener('click', () => {
      selectedCondition = 'used';
      tabUsed.classList.add('sf-tab-active');
      tabNew?.classList.remove('sf-tab-active');
      renderListings();
    });

    renderListings();
  }

  // ── 2. Order Placement ───────────────────────────────────────────────────────
  async function handlePlaceOrder(product, listingItem) {
    const priceNum = Number(listingItem.display_price || listingItem.price || 0);

    const orderData = {
      order_id: Math.floor(1000 + Math.random() * 9000),
      product_id: product.product_id,
      product_name: product.name,
      brand_name: product.brand_name || '',
      category: product.category || 'Shoes',
      image: product.image || null,
      size: listingItem.size || 'Standard',
      condition: listingItem.condition || 'new',
      price: priceNum,
      status: 'pending_payment',
      created_at: new Date().toISOString(),
    };

    try {
      const addrRes = await fetch('/api/addresses', { credentials: 'same-origin' });
      let addressId = null;
      if (addrRes.ok) {
        const addrData = await addrRes.json();
        if (Array.isArray(addrData.addresses) && addrData.addresses[0]) {
          addressId = addrData.addresses[0].address_id;
        }
      }

      if (addressId) {
        const res = await fetch('/api/orders', {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            variantId: listingItem.variant_id || 1,
            condition: listingItem.condition === 'used' ? 'used' : 'new',
            addressId: addressId,
            expectedDisplayPrice: priceNum,
            offerId: listingItem.condition === 'used' ? listingItem.offer_id : null,
          })
        });
        if (res.ok) {
          const data = await res.json();
          if (data.order && data.order.order_id) {
            orderData.order_id = data.order.order_id;
          }
        }
      }
    } catch (_) {}

    addLocalOrder(orderData);
    showOrderConfirmationPage(orderData, product);
  }

  // ── 3. Order Action Screen ("Pay or Cancel") ──────────────────────────────────
  function showOrderConfirmationPage(order, product) {
    const page = renderTemplate('tpl-order-confirmation');

    page.querySelector('#bp-order-number').textContent = `Order #${order.order_id}`;
    page.querySelector('#bp-order-product-name').textContent = order.product_name;
    page.querySelector('#bp-order-product-meta').textContent = `${order.brand_name || ''} · Size ${order.size}`;
    page.querySelector('#bp-order-condition').textContent = order.condition === 'new' ? '✨ One hand' : '🔄 Second hand';
    page.querySelector('#bp-order-price').textContent = `${Number(order.price).toFixed(2)} THB`;

    renderThumb(page.querySelector('#bp-order-thumb'), product || order);

    page.querySelector('#bp-order-back')?.addEventListener('click', () => window.location.reload());

    const statusBox = page.querySelector('#bp-status-box');
    const actionsBox = page.querySelector('#bp-actions');
    const postActionsBox = page.querySelector('#bp-post-actions');

    page.querySelector('#btn-order-pay')?.addEventListener('click', async () => {
      try {
        await fetch(`/api/orders/${order.order_id}/demo-payment`, {
          method: 'POST',
          credentials: 'same-origin',
        });
      } catch (_) {}

      updateLocalOrderStatus(order.order_id, 'paid');

      statusBox.innerHTML = `
        <span class="bp-status-badge bp-status-paid">✅ Paid</span>
        <p class="bp-order-success-msg">
          Payment confirmed! Your order is being prepared for shipment.
        </p>
      `;
      if (actionsBox) actionsBox.hidden = true;
      if (postActionsBox) postActionsBox.hidden = false;
    });

    page.querySelector('#btn-order-cancel')?.addEventListener('click', async () => {
      const confirmCancel = confirm('Are you sure you want to cancel this order?');
      if (!confirmCancel) return;

      try {
        await fetch(`/api/orders/${order.order_id}/cancel`, {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ reason: 'Buyer cancelled' })
        });
      } catch (_) {}

      updateLocalOrderStatus(order.order_id, 'cancelled');

      statusBox.innerHTML = `
        <span class="bp-status-badge bp-status-cancelled">❌ Cancelled</span>
        <p class="bp-order-cancelled-msg">
          This order has been cancelled.
        </p>
      `;
      if (actionsBox) actionsBox.hidden = true;
      if (postActionsBox) postActionsBox.hidden = false;
    });

    page.querySelector('#btn-go-my-orders')?.addEventListener('click', showBuyerOrdersPage);
    page.querySelector('#btn-go-home')?.addEventListener('click', () => window.location.reload());
  }

  // ── 4. "My Order" Page (Buyer Orders) ────────────────────────────────────────
  async function showBuyerOrdersPage() {
    const page = renderTemplate('tpl-buyer-orders');
    page.querySelector('#bo-back')?.addEventListener('click', () => window.location.reload());

    const list = page.querySelector('#bo-list');
    const emptyBox = page.querySelector('#bo-empty');
    if (!list) return;

    const localOrders = getLocalOrders();

    let backendOrders = [];
    try {
      const res = await fetch('/api/orders', { credentials: 'same-origin' });
      if (res.ok) {
        const data = await res.json();
        backendOrders = (data.orders || []).map(o => ({
          order_id: o.order_id,
          product_name: o.product_name_snapshot || 'Product',
          brand_name: 'Owl Pai Lei',
          size: o.size_snapshot || 'Standard',
          condition: o.condition_snapshot || 'new',
          price: Number(o.total || o.item_subtotal || 0),
          status: o.status === 'captured' || o.status === 'completed' ? 'paid' : (o.cancellation_status === 'approved' ? 'cancelled' : 'pending_payment'),
          created_at: o.created_at || new Date().toISOString(),
        }));
      }
    } catch (_) {}

    const orderMap = new Map();
    localOrders.forEach(o => orderMap.set(String(o.order_id), o));
    backendOrders.forEach(o => {
      if (!orderMap.has(String(o.order_id))) {
        orderMap.set(String(o.order_id), o);
      }
    });

    const orders = Array.from(orderMap.values());
    orders.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));

    if (orders.length === 0) {
      list.innerHTML = '';
      if (emptyBox) emptyBox.hidden = false;
      page.querySelector('#bo-empty-explore')?.addEventListener('click', () => window.location.reload());
      return;
    }

    if (emptyBox) emptyBox.hidden = true;
    list.innerHTML = '';

    orders.forEach((order, index) => {
      const item = document.createElement('div');
      item.className = 'mo-item';

      const num = document.createElement('span');
      num.className = 'mo-num';
      num.textContent = index + 1;

      const thumb = document.createElement('div');
      thumb.className = 'mo-thumb';
      renderThumb(thumb, order);

      const info = document.createElement('div');
      info.className = 'mo-info';

      const name = document.createElement('span');
      name.className = 'mo-item-name';
      name.textContent = `Order #${order.order_id} · ${order.product_name || 'Product'}`;

      const cond = document.createElement('span');
      cond.className = 'mo-item-cond';
      const condLabel = order.condition === 'new' ? 'One hand' : 'Second hand';
      cond.textContent = `${condLabel} · ${Number(order.price).toFixed(2)} THB · Size ${order.size}`;

      const statusSpan = document.createElement('span');
      const s = order.status || 'pending_payment';
      if (s === 'paid') {
        statusSpan.className = 'bp-status-badge bp-status-paid';
        statusSpan.textContent = '✅ Paid';
      } else if (s === 'cancelled') {
        statusSpan.className = 'bp-status-badge bp-status-cancelled';
        statusSpan.textContent = '❌ Cancelled';
      } else {
        statusSpan.className = 'bp-status-badge bp-status-pending';
        statusSpan.textContent = '⏳ Pending payment';
      }

      info.append(name, cond, statusSpan);

      if (s === 'pending_payment') {
        const actionRow = document.createElement('div');
        actionRow.className = 'bp-order-item-actions';

        const payBtn = document.createElement('button');
        payBtn.type = 'button';
        payBtn.className = 'bp-btn bp-btn-pay bp-btn-sm';
        payBtn.textContent = '💳 Pay';

        const cancelBtn = document.createElement('button');
        cancelBtn.type = 'button';
        cancelBtn.className = 'bp-btn bp-btn-cancel bp-btn-sm';
        cancelBtn.textContent = '✕ Cancel';

        payBtn.addEventListener('click', async () => {
          try {
            await fetch(`/api/orders/${order.order_id}/demo-payment`, {
              method: 'POST',
              credentials: 'same-origin',
            });
          } catch (_) {}
          updateLocalOrderStatus(order.order_id, 'paid');
          showBuyerOrdersPage();
        });

        cancelBtn.addEventListener('click', async () => {
          if (!confirm('Are you sure you want to cancel this order?')) return;
          try {
            await fetch(`/api/orders/${order.order_id}/cancel`, {
              method: 'POST',
              credentials: 'same-origin',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ reason: 'Buyer cancelled' })
            });
          } catch (_) {}
          updateLocalOrderStatus(order.order_id, 'cancelled');
          showBuyerOrdersPage();
        });

        actionRow.append(payBtn, cancelBtn);
        info.append(actionRow);
      }

      item.append(num, thumb, info);
      list.append(item);
    });
  }

  // ── 5. Ensure "My Order" In Profile Hover Menu ────────────────────────────────
  function ensureMyOrderInProfileMenu() {
    const menu = document.getElementById('profile-dropdown-menu');
    if (!menu) return;

    if (!menu.querySelector('#menu-my-order')) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'profile-menu-item';
      btn.id = 'menu-my-order';
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = `
        <span class="profile-menu-icon" aria-hidden="true">📦</span>
        <span class="profile-menu-label">My order</span>
      `;
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        menu.classList.remove('is-open');
        showBuyerOrdersPage();
      });
      menu.appendChild(btn);
    } else {
      const btn = menu.querySelector('#menu-my-order');
      btn.onclick = (e) => {
        e.preventDefault();
        menu.classList.remove('is-open');
        showBuyerOrdersPage();
      };
    }
  }

  // ── Initialization ───────────────────────────────────────────────────────────
  function init() {
    setupModalBuyInterception();
    ensureMyOrderInProfileMenu();

    const observer = new MutationObserver(() => {
      ensureMyOrderInProfileMenu();
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Expose public API
  window.Buy = {
    showBuyPage,
    showBuyerOrdersPage,
    handlePlaceOrder,
  };
  window.showBuyPage = showBuyPage;
  window.showBuyerOrdersPage = showBuyerOrdersPage;
})();
