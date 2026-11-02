# Owl Pai Lei — Backend + Database

Branch: `backend+database`. Based on the team repository main branch. This branch adds the Backend and PostgreSQL database only; it does not include Frontend files or modify main/assignment.

## Structure

- backend/src/: Express API, session authentication, role checks and photo validation
- backend/database/schema.sql: PostgreSQL schema (31 tables), workflow functions and fictional seed data
- backend/scripts/: safe one-time database installer
- backend/tests/: isolated database/API tests; no Frontend dependency
- docs/: ER, data dictionary, business rules and design notes
- package.json / package-lock.json: root npm workspace commands

## Install and run

1. Install Node.js 22+ and PostgreSQL (tested with version 18).
2. Run `npm ci` from this repository root.
3. Create an empty database named owl_pai_lei_compact in pgAdmin.
4. Copy backend/.env.example to backend/.env and enter your own PostgreSQL username, password and port.
5. Run `npm run db:setup` once in the empty database. It refuses to overwrite an existing owl schema. Alternatively, execute backend/database/schema.sql in pgAdmin; use only one setup method.
6. Run `npm start`. Backend is available at http://127.0.0.1:3188.

GET / returns service information, not a website. GET /api/health tests the connection. The database SQL contains fictional demo data; local database contents and private credentials are not uploaded.

## Demo accounts

- Seller: seller1@owl.test / OwlDemo123!
- Second seller: seller2@owl.test / OwlDemo123!
- Buyer: buyer@owl.test / OwlDemo123!

The seller demo accounts also have Buyer roles. Admin and QC screens are not included. Production deployment is not configured.

## API

- GET /api/products
- GET /api/products/:id/variants
- GET /api/products/:id/market
- GET /api/settings
- POST /api/login
- GET /api/me
- POST /api/logout
- GET/POST /api/seller/offers
- PATCH /api/seller/offers/:id
- POST /api/seller/offers/:id/withdraw
- GET /api/seller/sales
- GET /api/addresses
- POST /api/orders

Seller offers require Admin approval. Approved details/photos cannot be edited. Used items require defect descriptions and quantity 1. Photos accept up to three JPG/PNG/WebP images of 2 MB each. Buyer order creation records awaiting_payment; it does not collect real payment. Session cookies are HttpOnly and SameSite=Strict. Seller IDs come from authenticated sessions.

## Tests

Run `npm test`. The database user needs CREATEDB; tests use temporary databases and port 3199. They do not change the live app database and run without any Frontend files.

## Connecting the team's Frontend

The API uses relative /api paths and cookie sessions. Serve the team's Frontend and proxy /api to this Backend on the same origin, or configure a narrow allowed frontend origin and credential handling for a separate-origin deployment. Cross-origin writes are rejected by default. A standalone Frontend server requires integration configuration; do not disable these checks globally.

.env, node_modules, logs and runtime PID files are ignored by Git. Never commit private database credentials.

## อ่านโค้ดเตรียมเดโม

ดู [คู่มือภาษาไทยพร้อมเลขบรรทัดและคำถามที่ควรซ้อม](docs/DEMO_CODE_GUIDE_TH.md) มีคอมเมนต์ในทุกฟังก์ชัน Backend และฟังก์ชัน SQL พร้อมจุดเน้นของเส้นทางเสนอขาย
