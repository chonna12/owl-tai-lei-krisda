# ฐานข้อมูลที่ใช้กับ API ปัจจุบัน

เหลือ 22 ตาราง โดยคงทุก Route ใน backend/src/server.js ไม่ใช่เฉพาะปุ่มที่หน้าเว็บแสดง รวมตารางที่ SQL เรียกต่อด้วย

## บัญชีและสิทธิ์

`users`, `roles`, `user_roles`, `sessions`

## สินค้ากลาง

`categories`, `products`, `product_variants`, `platform_settings`

## Seller ลงขายและคิว

`seller_offers`, `queue_groups`, `queue_entries`, `assets`, `notifications`, `activity_logs`

## API ออเดอร์และผล QC

`addresses`, `coupons`, `coupon_redemptions`, `orders`, `order_items`, `qc_inspections`

## ข้อมูลยอดจ่ายที่ API อ่าน

`seller_bank_accounts`, `payouts`

## จุดที่ใช้จริง

- Login และตรวจสิทธิ์: users roles user_roles sessions
- Catalog และไซซ์: categories products product_variants assets
- ลงขาย แก้ไข ถอนขาย และแสดงรายการ: seller_offers assets queue_groups queue_entries activity_logs notifications
- แสดงราคาสินค้าที่ได้คิวขาย: public_market และ platform_settings
- สร้างคำสั่งซื้อผ่าน API: addresses orders order_items coupons coupon_redemptions และฟังก์ชัน checkout
- ดูยอดขายและ QC: seller_sales และ seller_qc_scores ใช้ orders order_items qc_inspections
- API ยอดขายยังอ่าน payouts จึงต้องเก็บ payouts และ seller_bank_accounts ที่ FK ชี้ถึง

## สิ่งที่ตัดออก

cancellation_requests, carts, payments, payout_items, refunds, seller_charges, seller_verifications, shipments, wishlist_items

ตัดฟังก์ชันชำระเงิน คืนเงิน ขนส่ง ยืนยันเอกสาร Wishlist ตะกร้า และจ่ายเงินที่ยังไม่มี API รองรับออกด้วย ไม่เปลี่ยนให้ฟังก์ชันเหล่านี้ตอบว่าสำเร็จปลอม

## ข้อจำกัดของงานปัจจุบัน

หน้าเว็บ Buy ยังเป็นตัวอย่าง ส่วน API สร้าง Order ทำได้ถึง awaiting_payment ไม่มี API ยืนยันชำระหรือขนส่ง ขั้นตอนหลังจากนี้จึงยังไม่ใช่ flow ที่ทำงานครบทั้งระบบ ผล QC และยอดจ่ายอ่านผ่าน API ได้ แต่ยังไม่มี API สร้างผล QC หรือจ่ายเงินจริง

## ฐานข้อมูลเดิม

ฐานข้อมูลเดิม 31 ตารางยังเก็บไว้ ไม่ใช้ DROP TABLE กับข้อมูลเดิม การติดตั้ง schema.sql ใหม่นี้ใช้กับฐานข้อมูลว่างเท่านั้น

## แหล่งอ้างอิง

backend/src/server.js, backend/src/photos.js และ backend/database/schema.sql เป็นข้อมูลอ้างอิงปัจจุบัน เอกสาร ER และ Data Dictionary เดิมอาจยังเป็นแบบ 31 ตาราง
