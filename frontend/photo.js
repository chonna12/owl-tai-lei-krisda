// photo.js — Photo reading and preview rendering utilities.

/**
 * Render photo preview thumbnails inside `container`.
 * Calls `onRemove(index)` when the user clicks the remove button on a preview.
 */
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

/**
 * Read a single image File as a base-64 data-URL.
 * Validates type (JPG/PNG/WebP) and size (≤ 2 MB) before resolving.
 */
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
