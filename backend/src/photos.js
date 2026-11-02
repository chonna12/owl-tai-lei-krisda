// Small classroom prototype: images live in the existing assets table.
export function validatePhotos(photos){
  if(photos===undefined)return;
  if(!Array.isArray(photos)||photos.length>3)throw Error('Attach up to 3 photos.');
  const unique=new Set();
  for(const photo of photos){
    const m=typeof photo==='string'&&photo.match(/^data:image\/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$/);
    if(!m)throw Error('Choose JPG, PNG or WebP images.');
    const data=Buffer.from(m[2],'base64');
    if(!data.length||data.length>2*1024*1024||data.toString('base64')!==m[2])throw Error('Each photo must be no larger than 2 MB.');
    const valid=m[1]==='png'?data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])):m[1]==='jpeg'?data[0]===255&&data[1]===216&&data[2]===255:data.toString('ascii',0,4)==='RIFF'&&data.toString('ascii',8,12)==='WEBP';
    if(!valid)throw Error('The image format does not match its file type.');
    if(unique.has(photo))throw Error('The same photo was attached twice.');unique.add(photo);
  }
}
export async function savePhotos(client,offerId,photos){
  if(photos===undefined)return;
  await client.query('DELETE FROM assets WHERE offer_id=$1',[offerId]);
  for(const [index,photo] of photos.entries())await client.query('INSERT INTO assets(offer_id,file_reference,sort_order) VALUES($1,$2,$3)',[offerId,photo,index]);
}
