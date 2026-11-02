import {
  randomBytes,
  scryptSync,
  timingSafeEqual,
  createHash,
} from "node:crypto";

// สร้าง salt สุ่มแล้วทำแฮชด้วย scrypt; คืน salt:hash สำหรับเก็บแทนรหัสผ่านตรง ๆ (เตรียมไว้ ยังไม่มี API Register)
export function hashPassword(password) {
  // salt ทำให้รหัสผ่านเหมือนกันได้แฮชต่างกัน; salt ไม่ใช่รหัสลับ
  const salt = randomBytes(16).toString("hex");
  return `${salt}:${scryptSync(password, salt, 64).toString("hex")}`;
}

// รับรหัสที่กรอกกับ salt:hash ใน DB; คำนวณใหม่ด้วย salt เดิม แล้วคืน true/false จากการเปรียบเทียบ
export function verifyPassword(password, stored) {
  // แยกข้อมูลเดิมด้วย : แล้วแปลง hex กลับเป็นไบต์สำหรับเปรียบเทียบ
  const [salt, hex] = stored.split(":");
  const expected = Buffer.from(hex, "hex");
  const actual = scryptSync(password, salt, 64);
  // ต้องยาวเท่ากันก่อนใช้ timingSafeEqual ซึ่งช่วยลดการรั่วไหลจากเวลาเปรียบเทียบ
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

// ทำ SHA-256 ของ token ก่อนเก็บ/ค้นใน sessions; token จริงจะไม่ถูกเก็บตรง ๆ ในฐานข้อมูล
export const tokenHash = (token) =>
  createHash("sha256").update(token).digest("hex");
// สุ่ม 32 ไบต์เป็นข้อความ hex 64 ตัวอักษร เพื่อสร้าง session token ใหม่หลัง Login สำเร็จ
export const newToken = () => randomBytes(32).toString("hex");

// อ่าน Bearer token ก่อน ถ้าไม่มีจึงอ่าน cookie owl_session; ไม่พบคืนข้อความว่าง และยังต้องตรวจ session ใน server.js
export function readToken(req) {
  const bearer = req.headers.authorization;
  if (bearer?.startsWith("Bearer ")) return bearer.slice(7);
  const cookie = (req.headers.cookie || "")
    .split(";")
    .find((x) => x.trim().startsWith("owl_session="));
  return cookie ? cookie.trim().slice("owl_session=".length) : "";
}
