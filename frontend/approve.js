// approve.js — Pure JS logic. HTML lives in index.html, styles in styles.css.

// Uses real user sessions (login.js handles authentication before this runs).
const $ = id => document.getElementById(id);
const ICONS = { Shoes: 'icon-shoe', Clothing: 'icon-tee', Accessories: 'icon-bag' };

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', ...options.headers }
  });
  const data = await response.json();
  if (!response.ok) {
    const error = new Error(data.error || 'Request failed. Please try again.');
    error.status = response.status;
    throw error;
  }
  return data;
}

const getJson = (url, options = {}) => requestJson(url, options);

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
    const data = await getJson('/api/me');
    window.currentUser = data.user || null;
  } catch (_) {
    window.currentUser = null;
  }
  return window.currentUser;
}

// All seller API calls go through here. If the session expired, reload so
// login.js can re-authenticate the user.
async function sellerRequest(url, options = {}) {
  if (window.DemoSeller) {
    return window.DemoSeller.sellerRequest(url, options);
  }
  const user = await getCurrentUser();
  if (!user || !user.canSell) {
    throw new Error('Only sellers can list items for sale. You are signed in as a Buyer.');
  }
  try {
    return await requestJson(url, options);
  } catch (error) {
    if (error.status === 401) {
      // Session expired — reload triggers login.js to show login screen again
      window.location.reload();
    }
    throw error;
  }
}

function renderPhotoPreviews(container, photos, onRemove) {
  container.replaceChildren();
  photos.forEach((src, index) => {
    const box = document.createElement('div');
    box.className = 'sf-photo-preview';
    const img = document.createElement('img');
    img.src = src; img.alt = `Item photo ${index + 1}`;
    const remove = document.createElement('button');
    remove.type = 'button'; remove.textContent = '×';
    remove.setAttribute('aria-label', `Remove photo ${index + 1}`);
    remove.addEventListener('click', () => onRemove(index));
    box.append(img, remove); container.append(box);
  });
}

async function readItemPhoto(file) {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type))
    throw new Error('Choose JPG, PNG or WebP images.');
  if (!file.size || file.size > 2 * 1024 * 1024)
    throw new Error('Each photo must be no larger than 2 MB.');
  const data = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error('Could not read this photo.'));
    reader.readAsDataURL(file);
  });
  await new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = resolve;
    image.onerror = () => reject(new Error('This file could not be opened as an image.'));
    image.src = data;
  });
  return data;
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
    img.className = 'item-photo';
    thumb.append(img);
  } else {
    thumb.classList.add('apm-thumb-placeholder');
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
  const user = await getCurrentUser();
  const isSeller = Boolean(user && user.canSell);

  if (!isSeller) {
    sellBtn.title = 'Only sellers can list items for sale';
    sellBtn.classList.add('apm-btn-disabled');
    sellBtn.onclick = () => {
      alert('Only sellers can list items for sale. Your account is currently a Buyer.');
    };
  } else {
    sellBtn.title = '';
    sellBtn.classList.remove('apm-btn-disabled');
    sellBtn.onclick = () => {
      overlay.classList.remove('is-open');
      showSellForm(product);
    };
  }
  $('modal-btn-buy').onclick = () => alert('Buy feature coming soon!');

  overlay.classList.add('is-open');
}

// ─── 2. SELL FORM ─────────────────────────────────────────────────────────────
async function showSellForm(product) {
  const user = await getCurrentUser();
  if (!user || !user.canSell) {
    alert('Only sellers can list items for sale. Your account is currently a Buyer.');
    return;
  }
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
    usedBlock.hidden = true;
    page.querySelector('#form-defects').required = false;
    page.querySelector('#form-quantity').readOnly = false;
    page.querySelector('#form-quantity').max = '100000';
  });
  tabUsed.addEventListener('click', () => {
    selectedCondition = 'used';
    tabUsed.classList.add('sf-tab-active');
    tabNew.classList.remove('sf-tab-active');
    usedBlock.hidden = false;
    page.querySelector('#form-defects').required = true;
    page.querySelector('#form-quantity').value = '1';
    page.querySelector('#form-quantity').max = '1';
    page.querySelector('#form-quantity').readOnly = true;
  });

  const photos = [];
  const photoInput = page.querySelector('#form-photos');
  const previews = page.querySelector('#photo-previews');
  const message = page.querySelector('#sf-error');
  const btn = page.querySelector('#sf-submit');
  let readingPhotos = false;
  const repaint = () => renderPhotoPreviews(previews, photos, index => {
    photos.splice(index, 1); repaint();
  });
  photoInput.addEventListener('change', async () => {
    const files = Array.from(photoInput.files || []);
    message.textContent = '';
    if (photos.length + files.length > 3) {
      message.textContent = 'Attach up to 3 photos. Remove a photo before adding another.';
      photoInput.value = ''; return;
    }
    readingPhotos = true; btn.disabled = true;
    try {
      const loaded = [];
      for (const file of files) {
        const src = await readItemPhoto(file);
        if (photos.includes(src) || loaded.includes(src)) throw new Error('This photo is already attached.');
        loaded.push(src);
      }
      photos.push(...loaded); repaint();
    } catch (error) { message.textContent = error.message; }
    finally { readingPhotos = false; btn.disabled = false; photoInput.value = ''; }
  });

  // UI -> POST API -> create_offer/savePhotos -> PostgreSQL. Show success only after HTTP 201.
  page.querySelector('#offer-form').addEventListener('submit', async e => {
    e.preventDefault();
    if (readingPhotos) return;
    btn.disabled = true; btn.textContent = 'Submitting…'; message.textContent = '';
    try {
      const result = await sellerRequest('/api/seller/offers', {
        method: 'POST',
        body: JSON.stringify({
          variantId: select.value,
          condition: selectedCondition,
          price: Number(page.querySelector('#form-price').value),
          quantity: Number(page.querySelector('#form-quantity').value),
          defects: selectedCondition === 'used' ? page.querySelector('#form-defects').value.trim() : '',
          notes: page.querySelector('#form-notes').value.trim(),
          photos
        })
      });
      showPendingResult(result.offer_id);
    } catch (error) { message.textContent = error.message; }
    finally { btn.disabled = false; btn.textContent = 'Confirm listing →'; }
  });
}

// ─── 3. PENDING APPROVAL PAGE ─────────────────────────────────────────────────
function showPendingResult(offerId) {
  const page = renderTemplate('tpl-pending');
  const saved = document.createElement('p'); saved.className = 'saved-offer-id';
  saved.textContent = `Offer #${offerId} saved to the database · Pending Admin approval`;
  page.querySelector('.pa-page').append(saved);
  page.querySelector('#pa-home').addEventListener('click', () => window.location.reload());
  page.querySelector('#pa-view-orders').addEventListener('click', showMyOrders);
}

// ─── 4. MY SELL ORDERS PAGE ───────────────────────────────────────────────────
async function showMyOrders() {
  const user = await getCurrentUser();
  if (!user || !user.canSell) {
    alert('Only sellers have sell orders. Your account is currently a Buyer.');
    return;
  }
  const page = renderTemplate('tpl-my-orders');
  page.querySelector('#mo-back').addEventListener('click', () => window.location.reload());

  const list = page.querySelector('#mo-list');

  // Read only this authenticated Seller's records from PostgreSQL, never from localStorage.
  let offers;
  try {
    const data = await sellerRequest('/api/seller/offers');
    offers = data.offers.map(offer => ({
      ...offer,
      product_name: offer.name,
      price: Number(offer.asking_price),
      image: (offer.photos || []).find(photo => /^data:image\/(png|jpeg|webp);base64,/.test(photo)) || null
    }));
  } catch (error) { list.textContent = error.message; return; }

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
      img.className = 'item-photo';
      thumb.append(img);
    } else {
      thumb.textContent = 'Picture';
    }

    // Info
    const info = document.createElement('div');
    info.className = 'mo-info';

    const name = document.createElement('span');
    name.className   = 'mo-item-name';
    name.textContent = `#${offer.offer_id} · ${offer.product_name || 'Product'}`;

    const cond = document.createElement('span');
    cond.className   = 'mo-item-cond';
    cond.textContent = (offer.condition === 'new' ? 'First hand' : 'Second hand')
                     + (offer.price ? ` · ${offer.price.toFixed(2)} THB` : '') + ` · Size ${offer.size} · Qty ${offer.available_quantity}`;

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
    case 'withdrawn': return 'Withdrawn';
    default:         return 'Pending approval';
  }
}

// ─── Product cards (home grid) ────────────────────────────────────────────────
function makeCard(product) {
  const li   = document.createElement('li');
  const card = document.createElement('button');
  card.type      = 'button';
  card.className = 'card';
  card.dataset.productId = String(product.product_id);
  card.addEventListener('click', () => showActionModal(product));

  const media = document.createElement('div');
  media.className = 'card-media tint-' + (product.product_id % 5);
  media.dataset.productId = String(product.product_id);
  const label = document.createElement('span');
  label.className   = 'card-label';
  label.textContent = `${product.category} / ${String(product.product_id).padStart(3, '0')}`;
  media.append(label);
  fillMedia(media, product);

  // Wishlist heart button (empty heart by default, filled with pink on click)
  if (window.Wishlist && typeof window.Wishlist.createButton === 'function') {
    media.append(window.Wishlist.createButton(product.product_id));
  }

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

// Small connection point for catalog.js; product card behavior stays with this UI.
window.renderCatalogProducts = products => {
  $('product-grid').replaceChildren(...products.map(makeCard));
};

// ─── Logout ───────────────────────────────────────────────────────────────────
async function handleLogout() {
  try {
    await requestJson('/api/logout', { method: 'POST' });
  } catch (_) { /* ignore errors — session is gone either way */ }
  window.location.reload();
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
      el.addEventListener('click', async () => {
        const user = await getCurrentUser();
        if (!user || !user.canSell) {
          alert('Only sellers have sell orders. Your account is currently a Buyer.');
          return;
        }
        showMyOrders();
      });
    });

  // Logout button (injected next to avatar)
  const userDiv = document.querySelector('.user');
  if (userDiv) {
    const logoutBtn = document.createElement('button');
    logoutBtn.id = 'logout-btn';
    logoutBtn.textContent = 'Sign out';
    logoutBtn.style.cssText = [
      'background:none;border:1px solid #eadfce;border-radius:999px',
      'font:inherit;font-size:12px;color:#a47c60;padding:5px 12px',
      'cursor:pointer;transition:background .15s',
    ].join(';');
    logoutBtn.onmouseover = () => logoutBtn.style.background = '#f5ece0';
    logoutBtn.onmouseout  = () => logoutBtn.style.background = 'none';
    logoutBtn.addEventListener('click', handleLogout);
    userDiv.append(logoutBtn);
  }
});
