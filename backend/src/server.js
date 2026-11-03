import express from 'express';
import pg from 'pg';
import {verifyPassword,newToken,tokenHash,readToken} from './security.js';
import {validatePhotos,savePhotos} from './photos.js';
import {fileURLToPath} from 'node:url';

// [เชื่อม DB] ใช้ค่าจาก backend/.env ติดต่อ PostgreSQL ใน schema owl
const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  options: '-c search_path=owl,public',
  connectionTimeoutMillis: 5000,
});
const app = express();
app.disable('x-powered-by');
// [รับ JSON] แปลงข้อมูลจาก frontend/approve.js มาไว้ใน req.body
app.use(express.json({limit:'9mb'}));
app.use((req,res,next)=>{
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('Content-Security-Policy',"default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; frame-ancestors 'none'");
  if(!['GET','HEAD','OPTIONS'].includes(req.method)&&req.headers.origin&&req.headers.origin!==`http://${req.headers.host}`)return res.status(403).json({error:'Cross-origin request rejected'});
  if(req.path.startsWith('/api/'))res.setHeader('Cache-Control','no-store');
  next();
});
app.use(express.static(fileURLToPath(new URL('../../frontend', import.meta.url))));
const attempts=new Map();
// [Login] รับบัญชีจาก UI → ตรวจ users → สร้าง sessions → ส่ง Cookie
app.post('/api/login',async(req,res)=>{
  const key=req.ip,now=Date.now();let attempt=attempts.get(key);
  if(!attempt||attempt.until<now){attempt={count:0,until:now+300000};attempts.set(key,attempt);}
  if(attempt.count>=15)return res.status(429).json({error:'Too many attempts. Try again in five minutes.'});
  attempt.count++;
  if(typeof req.body.email!=='string'||typeof req.body.password!=='string'||req.body.password.length>200)return res.status(400).json({error:'Enter your email and password'});
  const {rows}=await pool.query(`SELECT u.* FROM users u WHERE email=$1 AND status='active'
    AND EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name IN ('seller','buyer'))`,[req.body.email.trim().toLowerCase()]);
  const user=rows[0];
  if(!user||!verifyPassword(req.body.password,user.password_hash))return res.status(401).json({error:'Email or password is incorrect, or this account is not active.'});
  const token=newToken();await pool.query("INSERT INTO sessions(user_id,token_hash,expires_at) VALUES($1,$2,now()+interval '8 hours')",[user.user_id,tokenHash(token)]);
  res.cookie('owl_session',token,{httpOnly:true,sameSite:'strict',maxAge:8*3600000,path:'/'});
  attempts.delete(key);res.json({user:{name:user.full_name,email:user.email,canSell:user.seller_status==='active'}});
});
// [สิทธิ์] ตรวจ sessions + users + roles ก่อนให้ Seller ทำรายการ
async function seller(req,res,next){
  const {rows}=await pool.query(`SELECT u.user_id,u.full_name,u.email FROM sessions s JOIN users u USING(user_id)
    WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now() AND u.status='active' AND u.seller_status='active'
    AND EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name='seller')`,[tokenHash(readToken(req))]);
  if(!rows.length)return res.status(401).json({error:'Please sign in with a seller account'});
  // [เจ้าของ] ใช้ user_id จาก Session ไม่เชื่อรหัส Seller ที่กรอกจากหน้าเว็บ
  req.seller=rows[0];next();
}
async function account(req,res,next){
 const {rows}=await pool.query(`SELECT u.user_id,u.full_name,u.email,u.seller_status FROM sessions s JOIN users u USING(user_id)
 WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now() AND u.status='active'`,[tokenHash(readToken(req))]);
 if(!rows.length)return res.status(401).json({error:'Please log in to continue'});
 req.seller=rows[0];next();
}
app.get('/api/me',account,(req,res)=>res.json({user:{name:req.seller.full_name,email:req.seller.email,canSell:req.seller.seller_status==='active'}}));
app.post('/api/logout',account,async(req,res)=>{await pool.query('UPDATE sessions SET revoked_at=now() WHERE token_hash=$1',[tokenHash(readToken(req))]);res.clearCookie('owl_session',{path:'/'});res.json({ok:true});});
// [อ่านรายการ] UI → API → JOIN ข้อเสนอ สินค้า รูป คิว → ตอบกลับ UI
app.get('/api/seller/offers',seller,async(req,res)=>{
  const {rows}=await pool.query(`SELECT f.*,p.name,p.brand_name,c.name AS category,v.size,v.color,
    e.position AS queue_position,(g.active_offer_id=f.offer_id) AS is_active,
    coalesce((SELECT json_agg(a.file_reference ORDER BY a.sort_order,a.asset_id) FROM assets a WHERE a.offer_id=f.offer_id),'[]'::json) AS photos
    FROM seller_offers f JOIN product_variants v USING(variant_id) JOIN products p USING(product_id)
    JOIN categories c USING(category_id) LEFT JOIN queue_entries e USING(offer_id)
    LEFT JOIN queue_groups g ON g.group_id=e.group_id WHERE f.seller_id=$1 ORDER BY f.created_at DESC,f.offer_id DESC`,[req.seller.user_id]);
  res.json({offers:rows});
});
// [ตรวจข้อมูล] ตรวจราคา จำนวน และส่งรูปให้ photos.js ตรวจ
function offerInput(req,res,next){
  const b=req.body;
  try{validatePhotos(b.photos);}catch(e){return res.status(400).json({error:e.message});}
  if(!Number.isSafeInteger(b.quantity)||b.quantity<1||b.quantity>100000||!Number.isFinite(b.price)||b.price<=0||b.price>9999999999||Math.abs(b.price*100-Math.round(b.price*100))>0.0001||typeof b.defects!=='string'||b.defects.length>2000||typeof b.notes!=='string'||b.notes.length>2000)return res.status(400).json({error:'Enter a valid price, quantity and item details'});
  next();
}
// [API ลงขาย] รับ POST จาก frontend/approve.js → ตรวจสิทธิ์ → ตรวจข้อมูล
app.post('/api/seller/offers',seller,offerInput,async(req,res)=>{
  const b=req.body;if(!/^[1-9][0-9]{0,17}$/.test(String(b.variantId))||!['new','used'].includes(b.condition))return res.status(400).json({error:'Select a product variant and condition'});
  // [Repository ในไฟล์นี้] ขอ Connection ไป DB เพื่อใช้ Transaction เดียวกัน
  const client=await pool.connect();
  // [บันทึก] BEGIN → create_offer ใน DB → photos.js → COMMIT → ส่ง offer_id
  // [ผิดพลาด] ROLLBACK ย้อนทั้งข้อเสนอและรูป; release คืน Connection
  // [$1 ถึง $7] ส่งค่าแยกจาก SQL ช่วยป้องกัน SQL Injection
  try{await client.query('BEGIN');const {rows}=await client.query('SELECT create_offer($1,$2,$3,$4,$5,$6,$7) AS offer_id',[req.seller.user_id,b.variantId,b.condition,b.price,b.quantity,b.defects,b.notes]);await savePhotos(client,rows[0].offer_id,b.photos);await client.query('COMMIT');res.status(201).json(rows[0]);}catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
});
// [แก้ไข] เรียก edit_pending_offer ใน DB; แก้ได้เฉพาะ Pending ของตน
app.patch('/api/seller/offers/:id',seller,offerInput,async(req,res)=>{
  if(!/^[1-9][0-9]{0,17}$/.test(req.params.id))return res.status(400).json({error:'Invalid offer ID'});
  const b=req.body,client=await pool.connect();
  try{await client.query('BEGIN');await client.query('SELECT edit_pending_offer($1,$2,$3,$4,$5,$6)',[req.seller.user_id,req.params.id,b.price,b.quantity,b.defects,b.notes]);await savePhotos(client,req.params.id,b.photos);await client.query('COMMIT');res.json({ok:true});}catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
});
// [ถอนขาย] เปลี่ยนสถานะใน DB และนำออกจากคิว เก็บประวัติเดิม
app.post('/api/seller/offers/:id/withdraw',seller,async(req,res)=>{
  if(!/^[1-9][0-9]{0,17}$/.test(req.params.id))return res.status(400).json({error:'Invalid offer ID'});
  await pool.query('SELECT withdraw_offer($1,$2)',[req.seller.user_id,req.params.id]);res.json({ok:true});
});
// [ติดตามขาย] อ่าน View ยอดขาย ผล QC และ payouts → ตอบ JSON ให้ UI
app.get('/api/seller/sales',seller,async(req,res)=>{
  const sales=await pool.query('SELECT * FROM seller_sales WHERE seller_id=$1 ORDER BY order_id DESC',[req.seller.user_id]);
  const scores=await pool.query('SELECT * FROM seller_qc_scores WHERE seller_id=$1',[req.seller.user_id]);
  const payouts=await pool.query('SELECT payout_id,amount,status,created_at FROM payouts WHERE seller_id=$1 ORDER BY payout_id DESC',[req.seller.user_id]);
  res.json({sales:sales.rows,score:scores.rows[0]||null,payouts:payouts.rows});
});
app.get('/api/settings',async(req,res)=>{const {rows}=await pool.query('SELECT platform_fee_percent FROM platform_settings');res.json(rows[0]);});
app.get('/api/products/:id/market',async(req,res)=>{
  if(!/^[1-9][0-9]{0,17}$/.test(req.params.id))return res.status(400).json({error:'Invalid product ID'});
  const {rows}=await pool.query('SELECT * FROM public_market WHERE product_id=$1 ORDER BY variant_id,condition',[req.params.id]);
  res.json({listings:rows});
});
app.get('/api/addresses',account,async(req,res)=>{
  const {rows}=await pool.query('SELECT address_id,recipient_name,address_line,district,province,postal_code FROM addresses WHERE user_id=$1 AND NOT archived ORDER BY is_default DESC,address_id',[req.seller.user_id]);res.json({addresses:rows});
});
app.post('/api/orders',account,async(req,res)=>{
  const b=req.body;
  if(!/^[1-9][0-9]{0,17}$/.test(String(b.variantId))||!/^[1-9][0-9]{0,17}$/.test(String(b.addressId))||!['new','used'].includes(b.condition))return res.status(400).json({error:'Select a size, condition and shipping address'});
  const client=await pool.connect();
  try{
    await client.query('BEGIN');
    const {rows}=await client.query('SELECT checkout($1,$2,$3,$4,NULL) AS order_id',[req.seller.user_id,b.variantId,b.condition,b.addressId]);
    const order=(await client.query('SELECT order_id,total,status FROM orders WHERE order_id=$1',[rows[0].order_id])).rows[0];
    await client.query('COMMIT');res.status(201).json({order});
  }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
});

// Only public catalog fields are returned. Seller identities remain private.
app.get('/api/products', async (req, res) => {
  const {rows} = await pool.query(`
    SELECT p.product_id, p.name, p.brand_name, p.description,
           c.name AS category,
           (SELECT a.file_reference FROM assets a
            WHERE a.product_id=p.product_id ORDER BY a.sort_order,a.asset_id LIMIT 1) AS image
    FROM products p JOIN categories c USING(category_id)
    WHERE p.active ORDER BY p.product_id
  `);
  res.json({count:rows.length, products:rows});
});

app.get('/api/products/:id/variants', async (req, res) => {
  if (!/^[1-9][0-9]{0,17}$/.test(req.params.id)) {
    return res.status(400).json({error:'Invalid product ID'});
  }
  const product = await pool.query('SELECT product_id FROM products WHERE product_id=$1 AND active',[req.params.id]);
  if (!product.rowCount) return res.status(404).json({error:'Product not found'});
  const {rows} = await pool.query(`
    SELECT variant_id,product_id,size,color,sku FROM product_variants
    WHERE product_id=$1 AND active ORDER BY variant_id
  `,[req.params.id]);
  res.json({count:rows.length,variants:rows});
});

app.get('/api/health', async (req, res) => {
  await pool.query('SELECT 1');
  res.json({status:'ok',database:'connected'});
});

app.get('/',(req,res)=>res.json({service:'Owl Pai Lei Backend',health:'/api/health',catalog:'/api/products',frontendIncluded:false}));

app.use((req,res)=>res.status(404).json({error:'Route not found'}));
app.use((err,req,res,next)=>{
  console.error('Request failed:',err.code||err.name);
  if(err.type==='entity.too.large')return res.status(413).json({error:'Photos are too large. Use up to 3 images, no larger than 2 MB each.'});
  if(err.type==='entity.parse.failed')return res.status(400).json({error:'Invalid JSON'});
  if(['P0001','23514','23503','22P02','22003'].includes(err.code))return res.status(400).json({error:err.code==='P0001'?err.message:'Please check the selected item, quantity and condition details.'});
  res.status(500).json({error:'Unable to complete request'});
});

await pool.query('SELECT product_id FROM products LIMIT 1');
const server=app.listen(Number(process.env.PORT||3188),'127.0.0.1',()=>{
  console.log('Owl Seller Backend ready: http://127.0.0.1:'+Number(process.env.PORT||3188));
});
function stop(){server.close(async()=>{await pool.end();process.exit(0);});}
process.on('SIGINT',stop);
process.on('SIGTERM',stop);
