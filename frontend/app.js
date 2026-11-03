// app.js — Shared utilities, product card builder, home loader, and button bootstrapping.
// approve.js and photo.js are loaded before this file (see index.html <script> tags).

// ─── Shared utilities ─────────────────────────────────────────────────────────

const $ = id => document.getElementById(id);
const ICONS = { Shoes: 'icon-shoe', Clothing: 'icon-tee', Accessories: 'icon-bag' };

/** Fetch JSON with credentials; throws a typed error on non-2xx responses. */
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

const getJson = url => requestJson(url);

/** Clone a <template> into .page and return the page element for querying. */
function renderTemplate(templateId) {
  const page = document.querySelector('.page') || document.body;
  const tpl  = document.getElementById(templateId);
  page.innerHTML = '';
  page.appendChild(tpl.content.cloneNode(true));
  const notice = document.createElement('p');
  notice.className = 'demo-mode';
  notice.textContent = 'Demo mode · Seller One · Offers are saved to PostgreSQL';
  page.prepend(notice);
  return page;
}

// ─── SVG / media helpers ──────────────────────────────────────────────────────

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

// ─── Product card ─────────────────────────────────────────────────────────────

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

// ─── Button / event bootstrapping ────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', () => {
  // Start the named demo session automatically. Backend role checks remain enabled.
  ensureDemoSession().catch(error => {
    const status = $('demo-status');
    if (status) status.textContent = 'Demo sign-in failed: ' + error.message;
  });

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
