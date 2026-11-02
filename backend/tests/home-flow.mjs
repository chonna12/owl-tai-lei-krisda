import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import pg from 'pg';
import {fileURLToPath} from 'node:url';
const rootDir=fileURLToPath(new URL('../',import.meta.url));
const name='owl_home_test_'+randomBytes(5).toString('hex'),url=new URL(process.env.DATABASE_URL);url.pathname='/postgres';
const root=new pg.Pool({connectionString:url.toString()});let db,child;
try{
 await root.query(`CREATE DATABASE ${name}`);url.pathname='/'+name;db=new pg.Pool({connectionString:url.toString()});await db.query(await readFile(rootDir+'database/schema.sql','utf8'));
 child=spawn(process.execPath,['src/server.js'],{cwd:rootDir,env:{...process.env,DATABASE_URL:url.toString(),PORT:'3199'},stdio:['ignore','pipe','pipe']});
 await new Promise((resolve,reject)=>{child.stdout.once('data',resolve);child.stderr.once('data',x=>reject(Error(String(x))));child.once('exit',c=>reject(Error('Server exited '+c)));});
 const base='http://127.0.0.1:3199';let cookie='';
 const request=async(path,options={})=>fetch(base+path,{...options,headers:{'Content-Type':'application/json',...(cookie?{cookie}:{}),...options.headers}});
 const info=await (await request('/')).json();assert.equal(info.frontendIncluded,false);
 assert.equal((await request('/api/orders',{method:'POST',body:'{}'})).status,401);
 const login=await request('/api/login',{method:'POST',body:JSON.stringify({email:'buyer@owl.test',password:'OwlDemo123!'})});assert.equal(login.status,200);cookie=login.headers.get('set-cookie').split(';')[0];const buyer=await login.json();assert.equal(buyer.user.canSell,false);
 const addresses=await (await request('/api/addresses')).json();assert.equal(addresses.addresses[0].address_id,'1');
 const market=await (await request('/api/products/1/market')).json();assert.equal(market.listings[0].display_price,'1100.00');assert(!JSON.stringify(market).includes('seller_id'));
 const orderRes=await request('/api/orders',{method:'POST',body:JSON.stringify({variantId:'3',condition:'new',addressId:'1'})});assert.equal(orderRes.status,201);const {order}=await orderRes.json();assert.equal(order.status,'awaiting_payment');assert.equal(order.total,'1150.00');
 assert.equal((await request('/api/seller/offers')).status,401);
 const badAddress=await request('/api/orders',{method:'POST',body:JSON.stringify({variantId:'3',condition:'new',addressId:'2'})});assert.equal(badAddress.status,400);
 const sellerLogin=await request('/api/login',{method:'POST',body:JSON.stringify({email:'seller2@owl.test',password:'OwlDemo123!'})});cookie=sellerLogin.headers.get('set-cookie').split(';')[0];const seller=await sellerLogin.json();
 const photo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDaoAAAAASUVORK5CYII=';
 const invalid=await request('/api/seller/offers',{method:'POST',body:JSON.stringify({variantId:'3',condition:'used',price:600,quantity:1,defects:'Small mark',notes:'',photos:['data:image/svg+xml;base64,AAAA']})});assert.equal(invalid.status,400);
 const offered=await request('/api/seller/offers',{method:'POST',body:JSON.stringify({variantId:'3',condition:'used',price:600,quantity:1,defects:'Small mark',notes:'Home-flow test',photos:[photo]})});assert.equal(offered.status,201);const {offer_id}=await offered.json();const saved=(await (await request('/api/seller/offers')).json()).offers.find(o=>o.offer_id===offer_id);assert.deepEqual(saved.photos,[photo]);
 const edit=await request('/api/seller/offers/'+offer_id,{method:'PATCH',body:JSON.stringify({price:650,quantity:1,defects:'Small mark',notes:'Updated'})});assert.equal(edit.status,200);assert.equal((await db.query('SELECT file_reference FROM owl.assets WHERE offer_id=$1',[offer_id])).rows[0].file_reference,photo);
 const locked=await request('/api/seller/offers/1',{method:'PATCH',body:JSON.stringify({price:1000,quantity:3,defects:'',notes:'',photos:[photo]})});assert.equal(locked.status,400);
 assert.equal((await db.query('SELECT status FROM seller_offers WHERE offer_id=$1',[offer_id])).rows[0].status,'pending');
 console.log('PASS: Backend runs without frontend; catalog, buyer login/checkout, address ownership, seller offer creation/edit, photo persistence/validation and approved-offer protection.');
}finally{
 if(child){child.kill();await new Promise(r=>child.once('exit',r));}await db?.end();if(/^owl_home_test_[a-f0-9]{10}$/.test(name))await root.query(`DROP DATABASE IF EXISTS ${name}`);await root.end();
}

