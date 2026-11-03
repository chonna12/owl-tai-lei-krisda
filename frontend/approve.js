// approve.js — Sell-flow screens: Action Modal, Sell Form, Pending Result, My Orders.
// Depends on: app.js (shared utils), photo.js (photo helpers)

// ─── Demo session ─────────────────────────────────────────────────────────────
// Public fictional seed credentials only. The backend still validates the
// password, session, and Seller role.

let demoSession = null;

async function ensureDemoSession() {
  if (!demoSession) {
    demoSession = (async () => {
      try {
        const { user } = await getJson('/api/me');
        if (user.email === 'seller1@owl.test' && user.canSell) return user;
      } catch (error) {
        if (error.status !== 401) throw error;
      }
      const { user } = await requestJson('/api/login', {
        method: 'POST',
        body: JSON.stringify({ email: 'seller1@owl.test', password: 'OwlDemo123!' })
      });
      return user;
    })().catch(error => { demoSession = null; throw error; });
  }
  return demoSession;
}

async function sellerRequest(url, options = {}) {
  await ensureDemoSession();
  try { return await requestJson(url, options); }
  catch (error) {
    if (error.status !== 401) throw error;
    demoSession = null;
    await ensureDemoSession();
    return requestJson(url, options);
  }
}

// ─── 1. ACTION MODAL ─────────────────────────────────────────────────────────
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

  // Button handlers (re-assigned each call so `product` is current)
  $('modal-btn-sell').onclick = () => {
    overlay.classList.remove('is-open');
    showSellForm(product);
  };
  $('modal-btn-buy').onclick = () => alert('Buy feature coming soon!');

  overlay.classList.add('is-open');
}

// ─── 2. SELL FORM ─────────────────────────────────────────────────────────────
async function showSellForm(product) {
  try { await ensureDemoSession(); } catch(error) { alert('Demo account could not sign in: ' + error.message); return; }
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

  // Photo upload (uses photo.js helpers)
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

  // Form submit → POST to API → create_offer + savePhotos → PostgreSQL
  // Shows success only after HTTP 201.
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
          photos  // sent to backend and saved in the assets table
        })
      });
      // Also cache photos in localStorage so My Orders can show them even
      // before the backend's CDN/image pipeline makes them available.
      if (photos.length > 0) {
        try {
          localStorage.setItem('offer_photos_' + result.offer_id, JSON.stringify(photos));
        } catch { /* ignore QuotaExceededError */ }
      }
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
  const page = renderTemplate('tpl-my-orders');
  page.querySelector('#mo-back').addEventListener('click', () => window.location.reload());

  const list = page.querySelector('#mo-list');

  let offers;
  try {
    const data = await sellerRequest('/api/seller/offers');
    offers = data.offers.map(offer => {
      // Prefer DB photo; fall back to photo saved in localStorage at submit time
      const dbPhoto = (offer.photos || []).find(p => /^data:image\/(png|jpeg|webp);base64,/.test(p)) || null;
      let localPhoto = null;
      if (!dbPhoto) {
        try {
          const stored = JSON.parse(localStorage.getItem('offer_photos_' + offer.offer_id) || '[]');
          localPhoto = stored[0] || null;
        } catch { /* ignore parse errors */ }
      }
      return {
        ...offer,
        product_name: offer.name,
        price: Number(offer.asking_price),
        image: dbPhoto || localPhoto
      };
    });
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
    case 'approved':  return '✅ Approved';
    case 'rejected':  return '❌ Rejected';
    case 'withdrawn': return 'Withdrawn';
    default:          return 'Pending approval';
  }
}
