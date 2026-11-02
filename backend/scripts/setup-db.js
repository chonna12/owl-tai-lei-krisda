// สคริปต์ติดตั้งครั้งเดียว: ใช้กับ DB ว่างที่สร้างไว้แล้ว ไม่ใช่ไฟล์ที่รันทุกครั้งเมื่อผู้ใช้เพิ่มสินค้า
import pg from "pg";
import { readFile } from "node:fs/promises";
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
try {
  const exists = await pool.query(
    "SELECT 1 FROM information_schema.schemata WHERE schema_name='owl'",
  );
  // ถ้ามี schema แล้วให้หยุด ป้องกันการรัน SQL ซ้ำหรือเขียนทับข้อมูลเดิม
  if (exists.rowCount)
    throw Error(
      "Schema owl already exists. Nothing overwritten. Use the existing database or create a new empty database.",
    );
  await pool.query(
    await readFile(new URL("../database/schema.sql", import.meta.url), "utf8"),
  );
  console.log("Created 31 tables and fictional catalog data. Run npm start.");
} catch (e) {
  console.error("Setup stopped:", e.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
