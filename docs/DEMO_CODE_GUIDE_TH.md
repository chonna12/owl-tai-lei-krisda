# คู่มืออ่านโค้ดเตรียมเดโม — backend+database

เลขบรรทัดนี้อิงฉบับที่เพิ่มคอมเมนต์แล้ว (เลขเดิมที่เคยคุยกันเปลี่ยนไป)

## อ่านจุดไหนก่อน

เริ่มหัวข้อ 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 ก่อน เป็นเส้นทาง Seller เสนอขายและแก้ข้อมูลครบตั้งแต่ API จนถึง DB

เส้นทาง: UI ของเพื่อนส่ง POST → server.js ตรวจ session/ข้อมูล → BEGIN → client.query เรียก create_offer → savePhotos → COMMIT → HTTP 201 กลับ UI หากผิดพลาด ROLLBACK และ release connection

branch นี้ไม่มีไฟล์ UI; Service/Repository ยังอยู่รวมใน server.js และฟังก์ชัน PostgreSQL คอมเมนต์ที่เพิ่มไม่ได้เปลี่ยนสถาปัตยกรรมหรือเพิ่มฟังก์ชันใหม่

## จุดที่ควรซ้อมตอบ (เป็นการคาดการณ์ ไม่ใช่ข้อสอบที่อาจารย์ยืนยัน)

| จุดเน้น | ไฟล์:บรรทัด | คำถามที่อาจเจอ | แนวตอบ |
|---|---|---|---|
| 1. API รับการเสนอขาย | [backend/src/server.js:175](../backend/src/server.js#L175) | ทำไมต้องผ่าน seller กับ offerInput ก่อน? | ตรวจว่าเป็น Seller ที่เข้าใช้งานได้ และข้อมูลพื้นฐานถูกต้องก่อนเริ่มบันทึก |
| 2. ตรวจ Login/สิทธิ์ Seller | [backend/src/server.js:91](../backend/src/server.js#L91) | รู้ได้อย่างไรว่ารายการนี้เป็นของใคร? | อ่าน token ตรวจ session และบทบาท แล้วใช้ req.seller.user_id; ไม่เชื่อ seller_id จากฟอร์ม |
| 3. ตรวจข้อมูลฟอร์ม | [backend/src/server.js:149](../backend/src/server.js#L149) | มือสองต้องใส่จำนวนหนึ่งตรวจตรงไหน? | API ตรวจจำนวน/ราคา/รูปทั่วไป; ข้อจำกัดมือสองจำนวนไม่เกินหนึ่งและมีตำหนิอยู่ที่ CHECK ของ seller_offers และ create_offer บังคับจำนวนเป็นบวก |
| 4. เริ่ม Transaction | [backend/src/server.js:187](../backend/src/server.js#L187) | ทำไมใช้ client เดียวแทน pool.query หลายครั้ง? | transaction อยู่บน connection เดียว; pool อาจแจก connection คนละตัว ถ้ารูปผิดพลาดต้อง ROLLBACK รายการด้วย |
| 5. เรียก Service/Repository | [backend/src/server.js:190](../backend/src/server.js#L190) | Service กับ Repository อยู่ไฟล์ไหน? | ตอนนี้ยังไม่ได้แยกไฟล์: client.query เป็นส่วนเข้าถึง DB ใน server.js และ create_offer เป็นกฎธุรกิจใน PostgreSQL; อย่าบอกว่าแยก layer ครบแล้ว |
| 6. บันทึกรูป | [backend/src/photos.js:39](../backend/src/photos.js#L39) | ทำไมฟังก์ชันรูปไม่ COMMIT เอง? | ผู้เรียกต้องควบคุมรายการขายกับรูปใน transaction เดียว; undefined ไม่แก้รูป, [] ลบชุดรูปเดิม |
| 7. ยืนยัน/ย้อนกลับ | [backend/src/server.js:204](../backend/src/server.js#L204) | ถ้าสร้างรายการสำเร็จแต่รูปไม่สำเร็จจะเป็นอย่างไร? | catch สั่ง ROLLBACK ทั้งรายการและรูป; finally คืน connection ให้ pool |
| 8. สร้างรายการใน DB | [backend/database/schema.sql:469](../backend/database/schema.sql#L469) | ทำไมต้องอ้าง ProductVariant ที่มีอยู่? | ระบบขายเฉพาะแค็ตตาล็อกกลางที่ Owl กำหนด; create_offer ตรวจว่า variant และ Product active |
| 9. ค่าเริ่มต้นและ CHECK | [backend/database/schema.sql:113](../backend/database/schema.sql#L113) | pending มาจากหน้าเว็บหรือไม่? | มาจาก DEFAULT ในตาราง; Backend ไม่เปิดให้ฟอร์มเลือก status อนุมัติเอง และ CHECK ป้องกันค่าผิดแม้ข้าม UI |
| 10. แก้เฉพาะของตนเองที่ pending | [backend/database/schema.sql:487](../backend/database/schema.sql#L487) | เปลี่ยน offer ID ใน URL ไปของคนอื่นได้ไหม? | SQL กรองทั้ง offer_id และ seller_id จาก session แล้วตรวจ pending; FOR UPDATE ล็อกแถวระหว่างตรวจและแก้ |
| 11. ล็อกรายการหลังอนุมัติ | [backend/database/schema.sql:436](../backend/database/schema.sql#L436) | ทำไมซ่อนปุ่ม Edit อย่างเดียวไม่พอ? | ยิง API เองได้ จึงตรวจในฟังก์ชัน DB และมี trigger ป้องกันการแก้ข้อมูลสุดท้ายด้วย |
| 12. ตรวจรหัสผ่าน | [backend/src/security.js:16](../backend/src/security.js#L16) | ทำไมไม่เทียบรหัสผ่านตรง ๆ? | DB เก็บ salt:hash; คำนวณ scrypt จากรหัสที่รับกับ salt เดิมแล้วใช้ timingSafeEqual เปรียบเทียบ |
| 13. Token และ Cookie | [backend/src/security.js:26](../backend/src/security.js#L26) | Login แล้วจำผู้ใช้ได้อย่างไร? | สุ่ม token จริงให้ cookie เก็บเฉพาะ SHA-256 ใน sessions; ทุก request ต้องตรวจหมดอายุ/ถูก revoke อีกครั้ง |
| 14. ตรวจรูป | [backend/src/photos.js:4](../backend/src/photos.js#L4) | รับรูปอะไรก็ได้ไหม? | ไม่เกิน 3 รูป รูปละ 2 MB และชนิด JPG/PNG/WebP ตรวจ Base64 กับ magic bytes; ไม่ใช่ระบบสแกนไวรัส |
| 15. Admin อนุมัติ | [backend/database/schema.sql:573](../backend/database/schema.sql#L573) | ตอนนี้มีหน้า Admin ให้กดหรือยัง? | ยังไม่มีใน branch Backend-only; มีฟังก์ชันฐานข้อมูลตรวจบทบาท Admin แล้วปรับ pending เป็น approved/rejected และจัดคิว |

## แนวทางเดโมให้เห็นหลักฐาน

1. เปิด POST /api/seller/offers ใน server.js แล้วชี้ลำดับ middleware และ transaction
2. ส่งข้อมูลถูกต้องผ่าน UI ของทีม/เครื่องมือทดสอบ API แล้วดู offer_id และ pending ใน DB
3. ลองข้อมูลมือสองผิดเงื่อนไข ให้เห็น error และไม่มีข้อมูลค้าง
4. ลองแก้รายการที่ไม่ใช่ของตัวเองหรือ approved แล้ว ต้องไม่สำเร็จ
5. อธิบายจุด rollback และชุดทดสอบรูป โดยไม่ทำข้อมูลจริงเสียหาย
6. รัน npm test เพื่อแสดงผลทดสอบ API ในฐานข้อมูลชั่วคราว (บัญชี DB ต้องมี CREATEDB)

## ฟังก์ชัน JavaScript ทุกตัวและ Route handlers

| จุดเข้า/ฟังก์ชัน | ไฟล์:บรรทัด |
|---|---|
| `app.use((req, res, next) => {` | [backend/src/server.js:20](../backend/src/server.js#L20) |
| `app.post("/api/login", async (req, res) => {` | [backend/src/server.js:38](../backend/src/server.js#L38) |
| `async function seller(req, res, next) {` | [backend/src/server.js:91](../backend/src/server.js#L91) |
| `async function account(req, res, next) {` | [backend/src/server.js:106](../backend/src/server.js#L106) |
| `app.get("/api/me", account, (req, res) =>` | [backend/src/server.js:118](../backend/src/server.js#L118) |
| `app.post("/api/logout", account, async (req, res) => {` | [backend/src/server.js:128](../backend/src/server.js#L128) |
| `app.get("/api/seller/offers", seller, async (req, res) => {` | [backend/src/server.js:136](../backend/src/server.js#L136) |
| `function offerInput(req, res, next) {` | [backend/src/server.js:149](../backend/src/server.js#L149) |
| `app.post("/api/seller/offers", seller, offerInput, async (req, res) => {` | [backend/src/server.js:175](../backend/src/server.js#L175) |
| `app.patch("/api/seller/offers/:id", seller, offerInput, async (req, res) => {` | [backend/src/server.js:216](../backend/src/server.js#L216) |
| `app.post("/api/seller/offers/:id/withdraw", seller, async (req, res) => {` | [backend/src/server.js:247](../backend/src/server.js#L247) |
| `app.get("/api/seller/sales", seller, async (req, res) => {` | [backend/src/server.js:257](../backend/src/server.js#L257) |
| `app.get("/api/settings", async (req, res) => {` | [backend/src/server.js:277](../backend/src/server.js#L277) |
| `app.get("/api/products/:id/market", async (req, res) => {` | [backend/src/server.js:284](../backend/src/server.js#L284) |
| `app.get("/api/addresses", account, async (req, res) => {` | [backend/src/server.js:294](../backend/src/server.js#L294) |
| `app.post("/api/orders", account, async (req, res) => {` | [backend/src/server.js:302](../backend/src/server.js#L302) |
| `app.get("/api/products", async (req, res) => {` | [backend/src/server.js:341](../backend/src/server.js#L341) |
| `app.get("/api/products/:id/variants", async (req, res) => {` | [backend/src/server.js:354](../backend/src/server.js#L354) |
| `app.get("/api/health", async (req, res) => {` | [backend/src/server.js:375](../backend/src/server.js#L375) |
| `app.get("/", (req, res) =>` | [backend/src/server.js:381](../backend/src/server.js#L381) |
| `app.use((req, res) => res.status(404).json({ error: "Route not found" }));` | [backend/src/server.js:391](../backend/src/server.js#L391) |
| `app.use((err, req, res, next) => {` | [backend/src/server.js:393](../backend/src/server.js#L393) |
| `function stop() {` | [backend/src/server.js:426](../backend/src/server.js#L426) |
| `export function hashPassword(password) {` | [backend/src/security.js:9](../backend/src/security.js#L9) |
| `export function verifyPassword(password, stored) {` | [backend/src/security.js:16](../backend/src/security.js#L16) |
| `export const tokenHash = (token) =>` | [backend/src/security.js:26](../backend/src/security.js#L26) |
| `export const newToken = () => randomBytes(32).toString("hex");` | [backend/src/security.js:29](../backend/src/security.js#L29) |
| `export function readToken(req) {` | [backend/src/security.js:32](../backend/src/security.js#L32) |
| `export function validatePhotos(photos) {` | [backend/src/photos.js:4](../backend/src/photos.js#L4) |
| `export async function savePhotos(client, offerId, photos) {` | [backend/src/photos.js:39](../backend/src/photos.js#L39) |

## ฟังก์ชัน PostgreSQL ทั้ง 51 ตัว

| ฟังก์ชัน | บรรทัด | หน้าที่ |
|---|---:|---|
| `has_role` | [409](../backend/database/schema.sql#L409) | ตรวจว่าบัญชียัง active และมีบทบาทที่ระบุ; คืน BOOLEAN ใช้เป็นเงื่อนไขในฟังก์ชันอื่น |
| `require_role` | [416](../backend/database/schema.sql#L416) | เรียก has_role แล้ว RAISE EXCEPTION ถ้าไม่มีสิทธิ์; ทำให้คำสั่งที่กำลังบันทึกหยุดและ transaction ย้อนกลับได้ |
| `log_action` | [423](../backend/database/schema.sql#L423) | เขียน audit event ลง activity_logs พร้อมผู้ทำ ประเภทงาน และรหัสข้อมูล; ใช้ติดตามว่าใครทำอะไร |
| `log_order` | [429](../backend/database/schema.sql#L429) | เขียนประวัติสถานะออเดอร์พร้อมผู้ทำและหมายเหตุลง activity_logs |
| `guard_offer_edit` | [436](../backend/database/schema.sql#L436) | Trigger ป้องกัน hard delete และการเปลี่ยนรายละเอียดเมื่อไม่ใช่ pending; ถอนขายได้โดยเก็บประวัติ |
| `guard_offer_photo` | [450](../backend/database/schema.sql#L450) | Trigger ตรวจเจ้าของรูปและสถานะ offer; หลัง review จะเพิ่ม แก้ ลบ หรือย้ายรูปไม่ได้ |
| `immutable_record` | [463](../backend/database/schema.sql#L463) | Trigger กลางที่ปฏิเสธ UPDATE/DELETE เสมอ ใช้กับข้อมูลสุดท้ายและประวัติที่ต้องเก็บ |
| `create_offer` | [469](../backend/database/schema.sql#L469) | สร้างรายการเสนอขายจากแค็ตตาล็อกที่ active หลังตรวจ Seller; คืน offer_id และบันทึก audit; DEFAULT/CHECK ของตารางกำหนด pending และกฎมือสอง |
| `edit_pending_offer` | [487](../backend/database/schema.sql#L487) | แก้เฉพาะรายการของ Seller ผู้เรียกที่ยัง pending; FOR UPDATE ล็อกแถวระหว่างตรวจและบันทึก |
| `qc_skip_count` | [502](../backend/database/schema.sql#L502) | ใช้คะแนน QC เฉลี่ยกำหนดจำนวนรอบที่ถูกข้าม 0-3 รอบ; ยังไม่มีคะแนนใช้ค่าเริ่มต้น 4 จึงไม่ถูกข้าม |
| `queue_position` | [509](../backend/database/schema.sql#L509) | เพิ่มตัวนับแล้วคืนเลขท้ายคิวใหม่; ไม่ใช่การอ่านลำดับรอปัจจุบันของ Seller |
| `ensure_group` | [514](../backend/database/schema.sql#L514) | หา/สร้างคิวแยกตาม variant และสภาพ แล้วล็อกกลุ่มคิว; คืน group_id ให้ขั้นตอนอื่นใช้งาน |
| `queue_add` | [523](../backend/database/schema.sql#L523) | เพิ่มหรือเลื่อนข้อเสนอไปท้ายคิว พร้อมจำนวนรอบที่ต้องข้ามตาม QC และบันทึกเหตุการณ์ |
| `advance_queue` | [536](../backend/database/schema.sql#L536) | ล็อกกลุ่ม เลื่อนข้อเสนอที่ครบ 24 ชั่วโมง และข้ามตามคะแนน QC; คืน offer_id ที่ได้แสดงหรือ NULL เมื่อไม่มีของ |
| `refresh_all_queues` | [567](../backend/database/schema.sql#L567) | เรียก advance_queue ให้ทุกกลุ่ม; ไม่ใช่ timer อัตโนมัติ ต้องมีผู้เรียกหรือ scheduler ที่จัดแยก |
| `review_offer` | [573](../backend/database/schema.sql#L573) | เฉพาะ Admin ตัดสิน pending เป็น approved/rejected; reject ต้องมีเหตุผล; approved เข้าคิวและแจ้ง Seller |
| `withdraw_offer` | [593](../backend/database/schema.sql#L593) | ตรวจว่าเป็น offer ของ Seller ผู้เรียก เปลี่ยนเป็น withdrawn นำออกจากคิวและเลื่อนคิวต่อ โดยไม่ลบออเดอร์เก่า |
| `discount_for` | [611](../backend/database/schema.sql#L611) | ตรวจช่วงเวลา ยอดขั้นต่ำ โควตา และประวัติใช้คูปอง; คืนส่วนลดที่ใช้ได้ หรือ 0 ถ้าไม่ได้เลือกคูปอง |
| `checkout` | [626](../backend/database/schema.sql#L626) | สร้างออเดอร์หนึ่งชิ้นจากข้อเสนอที่อยู่หัวคิว; ตรวจที่อยู่ของ Buyer ห้ามซื้อของตัวเอง และ snapshot ราคา/รายละเอียด/ที่อยู่; ยังไม่จอง stock |
| `confirm_payment` | [655](../backend/database/schema.sql#L655) | Admin บันทึกยืนยันยอดชำระที่ตรงออเดอร์; ล็อกคิว/ออเดอร์ ลด stock หนึ่งชิ้น และหมุนคิว; การเรียกซ้ำอ้างอิงเดิมไม่ตัดซ้ำ และไม่ได้เรียกธนาคารจริง |
| `shipment_guard` | [693](../backend/database/schema.sql#L693) | Trigger ตรวจผู้สร้าง shipment และสถานะตามขาการขนส่ง; ห้ามส่งถึง Buyer ก่อน QC ผ่าน |
| `create_shipment` | [713](../backend/database/schema.sql#L713) | สร้างเลขติดตามตามขา seller_to_hub/hub_to_buyer/hub_to_seller และปรับสถานะ; ขาคืน Seller แยกหนี้ค่าส่ง |
| `receive_at_hub` | [732](../backend/database/schema.sql#L732) | QC ยืนยันรับสินค้าที่ศูนย์หลังมี shipment ขาเข้า แล้วเปลี่ยนเป็น awaiting_qc พร้อมบันทึกประวัติ |
| `record_qc` | [746](../backend/database/schema.sql#L746) | QC บันทึกผล คะแนน Seller และหลักฐาน; ผ่านเตรียมส่ง Buyer ไม่ผ่านยกเลิกและขอคืนเงินเต็มยอดที่ Buyer จ่าย |
| `confirm_receipt` | [777](../backend/database/schema.sql#L777) | Buyer เจ้าของออเดอร์ยืนยันรับหลังส่งขาออก; เปลี่ยนออเดอร์และรายการเป็น completed เพื่อให้มีสิทธิ์พิจารณาจ่าย Seller |
| `confirm_seller_return` | [793](../backend/database/schema.sql#L793) | QC ยืนยันว่าของขาคืนถึง Seller แล้ว และบันทึกสถานะ returned พร้อมประวัติ |
| `approve_refund` | [807](../backend/database/schema.sql#L807) | Admin อนุมัติ refund ที่ร้องขอหลังตรวจสถานะและการรับชำระเดิม; ไม่โอนเงินจริง |
| `record_refund_paid` | [820](../backend/database/schema.sql#L820) | Admin บันทึกว่าคืนเงินแล้วพร้อมเลขอ้างอิงไม่ซ้ำ; เป็นการบันทึกการจ่ายภายนอก ไม่ใช่ payment gateway |
| `create_payout` | [833](../backend/database/schema.sql#L833) | Admin รวมยอดขายที่เสร็จ/ชำระแล้ว/ไม่คืนเงิน/ยังไม่จ่ายให้ Seller ตามบัญชีธนาคารที่ตรวจแล้ว; สร้าง payout และรายการย่อย |
| `approve_payout` | [855](../backend/database/schema.sql#L855) | Admin ตรวจและอนุมัติ payout ที่ pending หลังตรวจยอดรายการย่อย; ยังไม่บันทึกว่าจ่ายแล้ว |
| `record_payout_paid` | [869](../backend/database/schema.sql#L869) | Admin บันทึกการจ่าย Seller ที่อนุมัติแล้วพร้อมเลขอ้างอิง; ไม่ติดต่อธนาคารและไม่อนุญาตจ่ายซ้ำ |
| `protect_order_snapshot` | [891](../backend/database/schema.sql#L891) | Trigger ล็อกยอดเงิน ผู้ซื้อ คูปอง และที่อยู่ snapshot ของออเดอร์ เพื่อไม่ให้ข้อมูลประวัติเปลี่ยนตามข้อมูลปัจจุบัน |
| `protect_item_snapshot` | [905](../backend/database/schema.sql#L905) | Trigger ล็อกข้อมูลสินค้าขณะซื้อ เช่น เจ้าของ variant ราคา จำนวน สภาพและตำหนิ; สถานะ fulfillment ยังเปลี่ยนได้ตาม workflow |
| `check_refund_record` | [916](../backend/database/schema.sql#L916) | Trigger ตรวจว่า refund เท่ากับยอด captured เดิมและเป็นออเดอร์ยกเลิก; ล็อกรายละเอียดและลำดับ requested -> approved -> paid |
| `check_payout_record` | [935](../backend/database/schema.sql#L935) | Trigger ตรวจสิทธิ์ Admin และบัญชีธนาคารของ Seller ที่ verified; ล็อกรายละเอียดและลำดับ pending -> approved -> paid |
| `check_payout_item` | [954](../backend/database/schema.sql#L954) | Trigger อนุญาตเฉพาะยอดขายของ Seller ที่ completed จ่ายแล้ว และไม่ถูกคืนเงินเข้ารอบจ่าย |
| `check_qc_actor` | [971](../backend/database/schema.sql#L971) | Trigger ยืนยันบทบาท QC ของ inspector และกำหนดว่ารายการต้องกำลัง awaiting_qc |
| `qc_needs_evidence` | [981](../backend/database/schema.sql#L981) | Deferred trigger ตรวจตอนท้าย transaction ว่าผล QC มีหลักฐานอย่างน้อยหนึ่งรายการ เพื่อให้ insert ผลและรูปในชุดเดียวกันได้ |
| `payment_guard` | [991](../backend/database/schema.sql#L991) | Trigger ตรวจ captured payment ให้ยอดตรงออเดอร์รอชำระและผู้ตรวจเป็น Admin; ยอดที่รับชำระแล้วแก้ไม่ได้ |
| `payout_item_snapshot_guard` | [1004](../backend/database/schema.sql#L1004) | แม้ชื่อมี payout แต่ฟังก์ชันนี้ผูกกับ order_items: ตรวจ snapshot ให้ตรง offer และป้องกัน Buyer ซื้อของตัวเอง |
| `admin_review_guard` | [1017](../backend/database/schema.sql#L1017) | ตัวช่วย trigger เดิมสำหรับตรวจ NEW.admin_id เป็น Admin; schema ฉบับนี้ไม่ได้ผูกใช้งาน ต้องดู compact_review_guard สำหรับ review จริง |
| `catalog_owner_guard` | [1021](../backend/database/schema.sql#L1021) | Trigger ตรวจว่าผู้สร้างสินค้าแค็ตตาล็อกมีบทบาท Admin; Seller เพิ่ม Product กลางเองไม่ได้ |
| `check_queue_entry` | [1027](../backend/database/schema.sql#L1027) | Trigger ตรวจว่า offer ที่ใส่คิวได้รับอนุมัติ มีของ และ variant/สภาพตรงกับกลุ่มคิว |
| `set_cart_item` | [1038](../backend/database/schema.sql#L1038) | ตรวจบทบาท Buyer แล้วเพิ่ม/แทนที่ตัวเลือกใน carts ของผู้ใช้; หนึ่งแถวเก็บหนึ่งตัวเลือกและจำนวนหนึ่ง |
| `verify_seller` | [1046](../backend/database/schema.sql#L1046) | Admin ตรวจคำขอยืนยัน Seller ที่ pending แล้วเก็บผล ผู้ตรวจ เวลาและหมายเหตุ พร้อม audit |
| `request_cancellation` | [1059](../backend/database/schema.sql#L1059) | Buyer ขอเลิกเฉพาะออเดอร์ตัวเองที่ยังไม่ส่งมอบจาก Seller ตามขอบเขตต้นแบบ; คืน request_id |
| `review_cancellation` | [1072](../backend/database/schema.sql#L1072) | Admin ตรวจคำขอ; ถ้าอนุมัติคืน stock เฉพาะเมื่อเคยยืนยันชำระ/จองของ และสร้าง refund เฉพาะยอดที่รับแล้ว |
| `record_return_shipping_paid` | [1105](../backend/database/schema.sql#L1105) | Admin บันทึกว่า Seller ชำระหนี้ค่าส่งคืนแล้วพร้อมเลขอ้างอิง; ไม่หักเงินจาก refund ของ Buyer |
| `compact_asset_guard` | [1159](../backend/database/schema.sql#L1159) | Trigger ห้ามแก้หรือลบ asset ที่เป็นหลักฐาน QC; ภาพสินค้า/ข้อเสนอใช้กฎของตัวเอง |
| `compact_review_guard` | [1164](../backend/database/schema.sql#L1164) | Trigger ตรวจ reviewed_by เป็น Admin และห้ามแก้คำตัดสิน/เหตุผล/เวลาหลังเคย review แล้ว |
| `compact_address_required` | [1174](../backend/database/schema.sql#L1174) | Deferred trigger ตรวจว่ามี shipping snapshot ครบ 6 ช่องเมื่อจบ transaction; checkout จึง insert ออเดอร์แล้วเติมที่อยู่ใน transaction เดียวได้ |

## ข้อจำกัดที่ควรตอบตามจริง

- SQL นี้เป็นสคริปต์ติดตั้ง DB ว่าง ไม่ได้รันทุกครั้งที่ใช้เว็บ; ข้อมูลจริงอยู่ใน PostgreSQL
- สถานะ pending, FK และ CHECK ช่วยรักษากฎที่ DB เพิ่มจาก validation ฝั่ง API
- ฟังก์ชันเงินเป็นการบันทึก/อนุมัติ ไม่ได้ติดต่อธนาคารหรือโอนเงินจริง
- canSell ใช้ช่วยแสดงผล; API Seller ตรวจบทบาทจริงอีกครั้ง
- Database owner มีสิทธิ์กว้าง ฟังก์ชันรับ actor ID จึงไม่ใช่ระบบ Authentication ที่แทน Backend ได้
- admin_review_guard เป็นตัวช่วยเดิมที่ไม่ได้ผูก trigger ใน schema นี้; review จริงใช้ compact_review_guard
