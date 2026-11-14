// Catalog search, category filtering, and result states.
(function () {
  'use strict';

  const searchInput = document.getElementById('catalog-search');
  const categorySelect = document.getElementById('catalog-category');
  const clearButton = document.getElementById('clear-filters');
  const status = document.getElementById('home-status');
  const count = document.getElementById('count');

  let debounceTimer;
  let activeController;
  let requestId = 0;

  function hasActiveFilters() {
    return Boolean(searchInput.value.trim() || categorySelect.value);
  }

  async function loadProducts() {
    const search = searchInput.value.trim();
    const category = categorySelect.value;
    const filtered = Boolean(search || category);
    const params = new URLSearchParams();
    if (search) params.set('q', search);
    if (category) params.set('category', category);

    const currentRequestId = ++requestId;
    activeController?.abort();
    const controller = new AbortController();
    activeController = controller;

    status.classList.remove('is-error');
    status.textContent = 'Loading products…';
    clearButton.hidden = !filtered;

    try {
      const query = params.toString();
      const response = await fetch(`/api/products${query ? `?${query}` : ''}`, {
        signal: controller.signal,
        credentials: 'same-origin'
      });
      if (!response.ok) throw new Error('Catalog request failed');
      const data = await response.json();
      if (currentRequestId !== requestId) return;

      const products = Array.isArray(data.products) ? data.products : [];
      if (typeof window.renderCatalogProducts !== 'function') {
        throw new Error('Catalog renderer is unavailable');
      }
      window.renderCatalogProducts(products);
      count.textContent = `${products.length} curated items`;
      status.textContent = products.length
        ? ''
        : filtered ? 'No products match your search.' : 'No products yet.';
    } catch (error) {
      if (controller.signal.aborted || currentRequestId !== requestId) return;
      status.textContent = 'Could not load products. Check that the backend is running.';
      status.classList.add('is-error');
    } finally {
      if (activeController === controller) activeController = null;
    }
  }

  function scheduleSearch() {
    clearTimeout(debounceTimer);
    requestId += 1;
    activeController?.abort();
    activeController = null;
    status.classList.remove('is-error');
    status.textContent = 'Searching…';
    clearButton.hidden = !hasActiveFilters();
    debounceTimer = setTimeout(loadProducts, 300);
  }

  function init() {
    if (!searchInput || !categorySelect || !clearButton || !status || !count) return;

    searchInput.addEventListener('input', scheduleSearch);
    categorySelect.addEventListener('change', () => {
      clearTimeout(debounceTimer);
      loadProducts();
    });
    clearButton.addEventListener('click', () => {
      clearTimeout(debounceTimer);
      searchInput.value = '';
      categorySelect.value = '';
      loadProducts();
    });

    loadProducts();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
