// Small classroom prototype: images live in the existing assets table.

/**
 * Validate the photos array sent by the browser.
 *
 * Key fixes vs the original:
 *  1. Regex now accepts any amount of trailing '=' padding (=*) because browsers
 *     sometimes omit trailing padding when the byte length is a multiple of 3.
 *  2. Removed the round-trip equality check `data.toString('base64') !== m[2]`
 *     which always failed when the browser omitted padding: Node always re-adds it,
 *     making the strings unequal even for a perfectly valid image.
 *  3. Normalise the data-URL to canonical base64 before the duplicate check so that
 *     the same image sent with or without padding is treated identically.
 */
export function validatePhotos(photos) {
  if (photos === undefined) return;
  if (!Array.isArray(photos) || photos.length > 3) throw Error('Attach up to 3 photos.');
  const unique = new Set();
  for (const photo of photos) {
    // Accept standard base64 with 0, 1, or 2 trailing '=' characters
    const m = typeof photo === 'string' &&
      photo.match(/^data:image\/(png|jpeg|webp);base64,([A-Za-z0-9+/]+=*)$/);
    if (!m) throw Error('Choose JPG, PNG or WebP images.');

    // Decode to Buffer — size check uses byte length, not string length
    const data = Buffer.from(m[2], 'base64');
    if (!data.length || data.length > 2 * 1024 * 1024)
      throw Error('Each photo must be no larger than 2 MB.');

    // Magic-byte check: verify the file actually matches the declared MIME type
    const valid =
      m[1] === 'png'  ? data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) :
      m[1] === 'jpeg' ? data[0] === 255 && data[1] === 216 && data[2] === 255 :
      /* webp */        data.toString('ascii', 0, 4) === 'RIFF' && data.toString('ascii', 8, 12) === 'WEBP';
    if (!valid) throw Error('The image format does not match its file type.');

    // Normalise to canonical padded base64 before the duplicate check
    const canonical = 'data:image/' + m[1] + ';base64,' + data.toString('base64');
    if (unique.has(canonical)) throw Error('The same photo was attached twice.');
    unique.add(canonical);
  }
}

/**
 * Persist photos into the assets table inside an open transaction.
 * Normalises every data-URL to canonical base64 (padded) before INSERT so that
 * the stored value is always well-formed regardless of browser padding behaviour.
 */
export async function savePhotos(client, offerId, photos) {
  if (photos === undefined) return;
  await client.query('DELETE FROM assets WHERE offer_id=$1', [offerId]);
  for (const [index, photo] of photos.entries()) {
    const m = photo.match(/^data:image\/(png|jpeg|webp);base64,([A-Za-z0-9+/]+=*)$/);
    // Normalise to canonical base64; fall back to the raw string if somehow unmatched
    const canonical = m
      ? 'data:image/' + m[1] + ';base64,' + Buffer.from(m[2], 'base64').toString('base64')
      : photo;
    await client.query(
      'INSERT INTO assets(offer_id,file_reference,sort_order) VALUES($1,$2,$3)',
      [offerId, canonical, index]
    );
  }
}
