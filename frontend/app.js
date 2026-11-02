const $ = id => document.getElementById(id);
const ICONS = { Shoes: 'icon-shoe', Clothing: 'icon-tee', Accessories: 'icon-bag' };

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error('Request failed');
  return res.json();
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

// 1. Modal เลือก Sell / Buy
async function showActionModal(product) {
  let modalOverlay = $('action-modal-overlay');
  if (!modalOverlay) {
    modalOverlay = document.createElement('div');
    modalOverlay.id = 'action-modal-overlay';
    modalOverlay.className = 'modal-overlay';
    modalOverlay.innerHTML = `
      <div class="modal-card" style="max-width: 400px; text-align: left; padding: 24px; background: #fff; border-radius: 16px; position: relative;">
        <button class="modal-close" id="modal-close-btn" style="position: absolute; top: 12px; right: 16px; background: none; border: none; font-size: 24px; cursor: pointer; color: #a47c60;">&times;</button>
        <h3 id="modal-product-title" style="margin: 0 0 4px; font-size: 20px;"></h3>
        <p id="modal-product-brand" style="margin: 0 0 16px; font-size: 12px; color: #a47c60; text-transform: uppercase;"></p>
        
        <div id="modal-market-details" style="margin-bottom: 20px;">
          <p style="font-size: 13px; color: #a47c60;">Loading details...</p>
        </div>

        <div style="display: flex; gap: 12px;">
          <button id="modal-btn-sell" style="flex: 1; padding: 12px; background: #5a3826; color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">Sell</button>
          <button id="modal-btn-buy" style="flex: 1; padding: 12px; background: #eddfd0; color: #5a3826; border: 1px solid #eadfce; border-radius: 8px; font-weight: 600; cursor: pointer;">Buy</button>
        </div>
      </div>
    `;
    document.body.append(modalOverlay);

    modalOverlay.addEventListener('click', (e) => {
      if (e.target === modalOverlay || e.target.id === 'modal-close-btn') {
        modalOverlay.classList.remove('is-open');
      }
    });
  }

  $('modal-product-title').textContent = product.name;
  $('modal-product-brand').textContent = product.brand_name;
  
  const marketBox = $('modal-market-details');
  marketBox.innerHTML = `<p style="font-size: 13px; color: #a47c60;">Loading details...</p>`;

  try {
    const data = await getJson(`/api/products/${product.product_id}/market`);
    const listings = data.listings || [];
    
    if (listings.length > 0) {
      marketBox.innerHTML = listings.map(item => `
        <div style="background: #eddfd0; padding: 12px; border-radius: 8px; margin-bottom: 8px; font-size: 13px;">
          <div style="display: flex; justify-content: space-between; font-weight: 600;">
            <span>${item.condition === 'new' ? 'First hand' : 'Second hand'} (${item.size})</span>
            <span style="color: #5a3826;">${item.display_price} THB</span>
          </div>
          ${item.defects ? `<div style="font-size: 11px; color: #a47c60; margin-top: 4px;">Defects: ${item.defects}</div>` : ''}
        </div>
      `).join('');
    } else {
      marketBox.innerHTML = `<div style="background: #eddfd0; padding: 12px; border-radius: 8px; font-size: 13px; color: #a47c60;">No active market listings yet. Be the first to sell!</div>`;
    }
  } catch (e) {
    marketBox.innerHTML = `<p style="font-size: 13px; color: #9a2b1f;">Could not load market details.</p>`;
  }

  // กำหนดให้กดปุ่ม Sell แล้วซ่อน Modal ทันที และเรียกฟอร์ม Sell
  const sellBtn = $('modal-btn-sell');
  sellBtn.onclick = null; //เคลียร์ Event เดิม
  sellBtn.onclick = () => {
    modalOverlay.classList.remove('is-open');
    showSellForm(product);
  };

  $('modal-btn-buy').onclick = () => {
    alert('Buy feature is coming soon!');
  };

  modalOverlay.classList.add('is-open');
}

// 2. หน้าฟอร์มลงขาย (First hand / Second hand)
async function showSellForm(product) {
  // ซ่อนหน้า Home ชั่วคราว หรือสร้าง Container ทับหน้าเว็บหลัก
  let appContainer = document.querySelector('.page') || document.body;
  
  let variants = [];
  try {
    const data = await getJson(`/api/products/${product.product_id}/variants`);
    variants = data.variants || [];
  } catch (e) {
    console.error('Could not load variants', e);
  }

  // สร้างหน้าฟอร์มขึ้นมาแสดงผลแทนที่เนื้อหาเดิม
  appContainer.innerHTML = `
    <div style="max-width: 480px; margin: 40px auto; padding: 0 16px; font-family: ui-sans-serif, sans-serif;">
      
      <header style="margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between;">
        <span style="font-weight: 700; font-size: 20px; background: #263238; color: #fff; padding: 6px 16px; border-radius: 6px;">Owl Pai Lei</span>
        <button id="back-to-home" style="background: none; border: none; font-size: 14px; cursor: pointer; color: #a47c60;">Cancel</button>
      </header>

      <div style="background: #eddfd0; border-radius: 16px; padding: 24px; border: 1px solid #eadfce;">
        
        <div style="display: flex; gap: 8px; background: #e0d0c0; padding: 4px; border-radius: 10px; margin-bottom: 20px;">
          <button type="button" id="tab-new" style="flex: 1; padding: 10px; background: #263238; color: #fff; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">First hand</button>
          <button type="button" id="tab-used" style="flex: 1; padding: 10px; background: transparent; color: #5a3826; border: none; border-radius: 8px; font-weight: 600; cursor: pointer;">Second hand</button>
        </div>

        <form id="offer-form">
          <div style="background: #e9dec9; border: 2px dashed #caa280; border-radius: 12px; height: 140px; display: flex; flex-direction: column; align-items: center; justify-content: center; margin-bottom: 20px; color: #a47c60;">
            <span style="font-size: 12px;">Picture of product</span>
          </div>

          <div style="margin-bottom: 14px;">
            <label style="display: block; font-size: 11px; font-weight: 700; color: #a47c60; margin-bottom: 4px; text-transform: uppercase;">Name of the product</label>
            <input type="text" value="${product.brand_name} - ${product.name}" disabled style="width: 100%; padding: 12px; border: 1px solid #eadfce; border-radius: 8px; background: #fff; font-size: 13px;">
          </div>

          <div style="margin-bottom: 14px;">
            <label style="display: block; font-size: 11px; font-weight: 700; color: #a47c60; margin-bottom: 4px; text-transform: uppercase;">Variant / Size</label>
            <select id="form-variant" required style="width: 100%; padding: 12px; border: 1px solid #eadfce; border-radius: 8px; background: #fff; font-size: 13px;">
              ${variants.map(v => `<option value="${v.variant_id}">${v.size} / ${v.color}</option>`).join('')}
            </select>
          </div>

          <div style="margin-bottom: 14px;">
            <label style="display: block; font-size: 11px; font-weight: 700; color: #a47c60; margin-bottom: 4px; text-transform: uppercase;">Asking Price (THB)</label>
            <input type="number" id="form-price" placeholder="Price" min="1" required style="width: 100%; padding: 12px; border: 1px solid #eadfce; border-radius: 8px; background: #fff; font-size: 13px;">
          </div>

          <div id="used-fields" style="display: none; margin-bottom: 14px;">
            <label style="display: block; font-size: 11px; font-weight: 700; color: #a47c60; margin-bottom: 4px; text-transform: uppercase;">Status / Defects</label>
            <textarea id="form-defects" placeholder="Minor wear, scuffed, with receipt..." style="width: 100%; padding: 12px; border: 1px solid #eadfce; border-radius: 8px; background: #fff; font-size: 13px; min-height: 80px;"></textarea>
          </div>

          <button type="submit" style="width: 100%; padding: 14px; background: #5a3826; color: #fff; border: none; border-radius: 8px; font-size: 14px; font-weight: 600; cursor: pointer; margin-top: 10px;">Confirm</button>
        </form>

      </div>
    </div>
  `;

  $('back-to-home').onclick = () => window.location.reload();

  let selectedCondition = 'new';
  const tabNew = $('tab-new');
  const tabUsed = $('tab-used');

  tabNew.onclick = () => {
    selectedCondition = 'new';
    tabNew.style.background = '#263238';
    tabNew.style.color = '#fff';
    tabUsed.style.background = 'transparent';
    tabUsed.style.color = '#5a3826';
    $('used-fields').style.display = 'none';
  };

  tabUsed.onclick = () => {
    selectedCondition = 'used';
    tabUsed.style.background = '#263238';
    tabUsed.style.color = '#fff';
    tabNew.style.background = 'transparent';
    tabNew.style.color = '#5a3826';
    $('used-fields').style.display = 'block';
  };

  $('offer-form').onsubmit = async (e) => {
    e.preventDefault();
    const payload = {
      variantId: $('form-variant').value,
      condition: selectedCondition,
      price: parseFloat($('form-price').value),
      quantity: 1,
      defects: selectedCondition === 'used' ? ($('form-defects').value || 'Used item') : '',
      notes: '',
      photos: []
    };

    try {
      const res = await fetch('/api/seller/offers', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (res.ok) {
        showPendingResult();
      } else {
        const err = await res.json();
        alert('Error: ' + (err.error || 'Failed to submit offer'));
      }
    } catch (err) {
      alert('Network error.');
    }
  };
}

// 3. หน้า Result (Pending)
function showPendingResult() {
  let appContainer = document.querySelector('.page') || document.body;
  appContainer.innerHTML = `
    <div style="max-width: 480px; margin: 40px auto; padding: 0 16px; font-family: ui-sans-serif, sans-serif;">
      <header style="margin-bottom: 20px;">
        <span style="font-weight: 700; font-size: 20px; background: #263238; color: #fff; padding: 6px 16px; border-radius: 6px;">Owl Pai Lei</span>
      </header>

      <div style="background: #eddfd0; border-radius: 16px; padding: 48px 24px; border: 1px solid #eadfce; text-align: center;">
        <h2 style="font-size: 26px; margin: 0 0 12px; color: #5a3826;">Pending</h2>
        <span style="display: inline-block; padding: 4px 16px; background: #263238; color: #fff; border-radius: 20px; font-size: 11px; font-weight: 600; margin-bottom: 16px;">Approval</span>
        <p style="font-size: 13px; color: #a47c60; margin: 0 0 32px;">Our team is reviewing your listing.</p>
        <button id="done-btn" style="padding: 12px 32px; background: #5a3826; color: #fff; border: none; border-radius: 8px; font-size: 14px; font-weight: 600; cursor: pointer;">Back to Home</button>
      </div>
    </div>
  `;

  $('done-btn').onclick = () => window.location.reload();
}

function makeCard(product) {
  const li = document.createElement('li');
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'card';
  
  card.onclick = () => showActionModal(product);

  const media = document.createElement('div');
  media.className = 'card-media tint-' + (product.product_id % 5);
  const label = document.createElement('span');
  label.className = 'card-label';
  label.textContent = `${product.category} / ${String(product.product_id).padStart(3, '0')}`;
  media.append(label);
  fillMedia(media, product);

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

loadHome();