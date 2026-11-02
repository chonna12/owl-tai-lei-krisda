// approve.js — Pure JS logic. HTML lives in index.html, styles in styles.css.

// ─── Local order store — persisted in localStorage (no auth required yet) ─────
const ORDERS_KEY = 'owl_local_orders';

function loadLocalOrders() {
  try { return JSON.parse(localStorage.getItem(ORDERS_KEY)) || []; }
  catch { return []; }
}

function saveLocalOrder(order) {
  const orders = loadLocalOrders();
  orders.push(order);
  localStorage.setItem(ORDERS_KEY, JSON.stringify(orders));
}

// ─── Utilities ────────────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const ICONS = { Shoes: 'icon-shoe', Clothing: 'icon-tee', Accessories: 'icon-bag' };

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error('Request failed');
  return res.json();
}

/** Clone a <template> into .page and return the page element for querying. */
function renderTemplate(templateId) {
  const page = document.querySelector('.page') || document.body;
  const tpl  = document.getElementById(templateId);
  page.innerHTML = '';
  page.appendChild(tpl.content.cloneNode(true));
  return page;
}

function svgIcon(id) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('class', 'card-icon');
  svg.setAttribute('viewBox', id === 'icon-shoe' ? '0 0 120 70' : '0 0 100 90');
  svg.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
  use.setAttribute('href', '#' + id);
  svg.append(use);
  return svg;
}

function fillMedia(media, product) {
  if (typeof product.image === 'string' && /^(data:image\/|https?:\/\/|\/)/.test(product.image)) {
    const img = document.createElement('img');
    img.className = 'card-photo';
    img.src = product.image;
    img.alt = product.name;
    media.append(img);
  } else {
    media.append(svgIcon(ICONS[product.category] || 'icon-bag'));
  }
}

// ─── 1. ACTION MODAL ──────────────────────────────────────────────────────────
// The modal markup is already in index.html — JS just populates & shows it.

async function showActionModal(product) {
  const overlay = $('action-modal-overlay');

  // Populate header
  $('modal-product-title').textContent = product.name;
  $('modal-product-brand').textContent = product.brand_name;

  // Thumb image
  const thumb = $('apm-thumb');
  thumb.innerHTML = '';
  thumb.removeAttribute('style');
  if (typeof product.image === 'string' && /^(data:image\/|https?:\/\/|\/)/.test(product.image)) {
    const img = document.createElement('img');
    img.src = product.image;
    img.alt = product.name;
    img.style.cssText = 'width:100%;height:100%;object-fit:cover;border-radius:10px;';
    thumb.append(img);
  } else {
    thumb.style.cssText = 'display:grid;place-items:center;font-size:30px;';
    thumb.textContent = '👟';
  }

  // Market listings
  const marketBox = $('modal-market-details');
  marketBox.innerHTML = '<div class="apm-loading">Loading listings…</div>';

  try {
    const data     = await getJson(`/api/products/${product.product_id}/market`);
    const listings = data.listings || [];

    if (listings.length > 0) {
      marketBox.innerHTML = '<p class="apm-section-label">Available listings</p>';
      listings.forEach(item => {
        const row = document.createElement('div');
        row.className = 'apm-listing-row';

        const info = document.createElement('div');
        const cond = document.createElement('span');
        cond.className   = 'apm-listing-condition';
        cond.textContent = item.condition === 'new' ? 'First hand' : 'Second hand';
        const size = document.createElement('span');
        size.className   = 'apm-listing-size';
        size.textContent = `Size ${item.size}`;
        info.append(cond, size);

        const price = document.createElement('span');
        price.className   = 'apm-listing-price';
        price.textContent = `${item.display_price} THB`;

        row.append(info, price);
        marketBox.append(row);

        if (item.defects) {
          const defect = document.createElement('p');
          defect.className   = 'apm-listing-defect';
          defect.textContent = `⚠ ${item.defects}`;
          marketBox.append(defect);
        }
      });
    } else {
      const empty = document.createElement('div');
      empty.className   = 'apm-empty';
      empty.innerHTML   = '<span style="font-size:28px;">📭</span><p>No listings yet — be the first to sell!</p>';
      marketBox.innerHTML = '';
      marketBox.append(empty);
    }
  } catch {
    marketBox.innerHTML = '<p class="apm-error">Could not load market details.</p>';
  }

  // Button handlers (re-assign each call so product is current)
  const sellBtn = $('modal-btn-sell');
  sellBtn.onclick = () => {
    overlay.classList.remove('is-open');
    showSellForm(product);
  };
  $('modal-btn-buy').onclick = () => alert('Buy feature coming soon!');

  overlay.classList.add('is-open');
}

// ─── 2. SELL FORM ─────────────────────────────────────────────────────────────
async function showSellForm(product) {
  const page = renderTemplate('tpl-sell-form');

  // Fill product chip
  page.querySelector('#sf-product-name').textContent  = product.name;
  page.querySelector('#sf-product-brand').textContent = product.brand_name;

  // Cancel button
  page.querySelector('#sf-cancel').addEventListener('click', () => window.location.reload());

  // Load variants into <select>
  const select = page.querySelector('#form-variant');
  try {
    const data     = await getJson(`/api/products/${product.product_id}/variants`);
    const variants = data.variants || [];
    if (variants.length) {
      variants.forEach(v => {
        const opt = document.createElement('option');
        opt.value       = v.variant_id;
        opt.textContent = `${v.size} / ${v.color}`;
        select.append(opt);
      });
    } else {
      const opt = document.createElement('option');
      opt.value       = '';
      opt.textContent = 'No variants available';
      select.append(opt);
    }
  } catch (e) {
    console.error('Could not load variants', e);
  }

  // Condition tabs
  let selectedCondition = 'new';
  const tabNew    = page.querySelector('#tab-new');
  const tabUsed   = page.querySelector('#tab-used');
  const usedBlock = page.querySelector('#used-fields');

  tabNew.addEventListener('click', () => {
    selectedCondition = 'new';
    tabNew.classList.add('sf-tab-active');
    tabUsed.classList.remove('sf-tab-active');
    usedBlock.style.display = 'none';
  });
  tabUsed.addEventListener('click', () => {
    selectedCondition = 'used';
    tabUsed.classList.add('sf-tab-active');
    tabNew.classList.remove('sf-tab-active');
    usedBlock.style.display = 'block';
  });

  // Form submit — auth not required yet, save locally and go to pending page
  page.querySelector('#offer-form').addEventListener('submit', e => {
    e.preventDefault();
    const btn = page.querySelector('#sf-submit');
    btn.disabled    = true;
    btn.textContent = 'Submitting…';

    // Save listing to localStorage so "My sell orders" persists across reloads
    saveLocalOrder({
      product_name: product.name,
      brand_name:   product.brand_name,
      image:        product.image || null,
      condition:    selectedCondition,
      price:        parseFloat(page.querySelector('#form-price').value) || null,
      status:       'pending'
    });

    showPendingResult();
  });
}

// ─── 3. PENDING APPROVAL PAGE ─────────────────────────────────────────────────
function showPendingResult() {
  const page = renderTemplate('tpl-pending');
  page.querySelector('#pa-home').addEventListener('click', () => window.location.reload());
  page.querySelector('#pa-view-orders').addEventListener('click', showMyOrders);
}

// ─── 4. MY SELL ORDERS PAGE ───────────────────────────────────────────────────
async function showMyOrders() {
  const page = renderTemplate('tpl-my-orders');
  page.querySelector('#mo-back').addEventListener('click', () => window.location.reload());

  const list = page.querySelector('#mo-list');

  // Use locally stored orders (persisted in localStorage, no auth required yet)
  const offers = loadLocalOrders();

  if (offers.length === 0) {
    list.innerHTML = '';
    const empty = document.createElement('div');
    empty.className = 'mo-empty';
    empty.innerHTML = '<span style="font-size:44px;">📦</span><p>You have no sell orders yet.</p>';
    list.append(empty);
    return;
  }

  list.innerHTML = '';
  offers.forEach((offer, i) => {
    const item = document.createElement('div');
    item.className = 'mo-item';

    // Number badge
    const num = document.createElement('span');
    num.className   = 'mo-num';
    num.textContent = i + 1;

    // Thumb
    const thumb = document.createElement('div');
    thumb.className = offer.image ? 'mo-thumb' : 'mo-thumb mo-thumb-empty';
    if (offer.image) {
      const img = document.createElement('img');
      img.src   = offer.image;
      img.alt   = offer.product_name || '';
      img.style.cssText = 'width:100%;height:100%;object-fit:cover;border-radius:10px;';
      thumb.append(img);
    } else {
      thumb.textContent = 'Picture';
    }

    // Info
    const info = document.createElement('div');
    info.className = 'mo-info';

    const name = document.createElement('span');
    name.className   = 'mo-item-name';
    name.textContent = offer.product_name || 'Product';

    const cond = document.createElement('span');
    cond.className   = 'mo-item-cond';
    cond.textContent = (offer.condition === 'new' ? 'First hand' : 'Second hand')
                     + (offer.price ? ` · ${offer.price.toFixed(2)} THB` : '');

    const badge = document.createElement('span');
    const status = offer.status || 'pending';
    badge.className   = `mo-status mo-status-${status}`;
    badge.textContent = statusLabel(status);

    info.append(name, cond, badge);
    item.append(num, thumb, info);
    list.append(item);
  });
}

function statusLabel(status) {
  switch (status) {
    case 'approved': return '✅ Approved';
    case 'rejected': return '❌ Rejected';
    default:         return 'Pending approval';
  }
}

// ─── Product cards (home grid) ────────────────────────────────────────────────
function makeCard(product) {
  const li   = document.createElement('li');
  const card = document.createElement('button');
  card.type      = 'button';
  card.className = 'card';
  card.addEventListener('click', () => showActionModal(product));

  const media = document.createElement('div');
  media.className = 'card-media tint-' + (product.product_id % 5);
  const label = document.createElement('span');
  label.className   = 'card-label';
  label.textContent = `${product.category} / ${String(product.product_id).padStart(3, '0')}`;
  media.append(label);
  fillMedia(media, product);

  const body  = document.createElement('div');
  body.className = 'card-body';
  const brand = document.createElement('span');
  brand.className   = 'card-brand';
  brand.textContent = product.brand_name;
  const name  = document.createElement('span');
  name.className   = 'card-name';
  name.textContent = product.name;
  body.append(brand, name);

  card.append(media, body);
  li.append(card);
  return li;
}

// ─── Home loader ──────────────────────────────────────────────────────────────
async function loadHome() {
  const status = $('home-status');
  if (!status) return;
  status.textContent = 'Loading products…';
  try {
    const { products } = await getJson('/api/products');
    $('product-grid').replaceChildren(...products.map(makeCard));
    $('count').textContent = `${products.length} curated items`;
    status.textContent = products.length ? '' : 'No products yet.';
  } catch {
    status.textContent = 'Could not load products. Check that the backend is running.';
    status.classList.add('is-error');
  }
}

// ─── Bootstrap ────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  // Modal close handlers (modal is always in the DOM)
  const overlay = $('action-modal-overlay');
  overlay.addEventListener('click', e => {
    if (e.target === overlay || e.target.id === 'modal-close-btn')
      overlay.classList.remove('is-open');
  });

  // Avatar / username → My Orders
  [document.querySelector('.avatar'), document.querySelector('.user-name')]
    .forEach(el => {
      if (!el) return;
      el.title = 'View my sell orders';
      el.addEventListener('click', showMyOrders);
    });
});

loadHome();
