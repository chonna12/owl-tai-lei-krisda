# Owl Pai Lei — Team Demo

## Seller UI is connected to PostgreSQL

The frontend automatically signs in to the fictional Demo Seller One account using the existing /api/login endpoint. No Login screen is required for this classroom demo. Backend session and Seller checks remain enabled. This shared demo account is not a production authentication flow.

- Submit sends POST /api/seller/offers with variant, condition, price, quantity, defects, notes and optional photos.
- The pending page is shown only after the API confirms the database commit.
- My sell orders reads GET /api/seller/offers from PostgreSQL. Browser localStorage is no longer used for offers. Old browser-only entries are not imported automatically.
- Photo picker supports three JPG/PNG/WebP files up to 2 MB each, with previews and removal before submit. Photos are saved in assets along with the offer in one transaction.
- New items support multiple units. Used items require defect details and quantity one.
- Buy remains a placeholder in this team's UI.

## Run

Install Node.js 22+ and PostgreSQL 18. Run npm ci from the root, copy backend/.env.example to backend/.env, and configure your own PostgreSQL credentials.

For a new empty database, create it in pgAdmin and run **npm run db:setup** once. The current schema.sql already includes the fixed image indexes. Existing databases that have already been updated can run the app directly. Do not run setup against an existing schema.

Run **npm start** and open http://127.0.0.1:3188 (or the port in backend/.env). This computer's team demo uses port 3190.

## Demo presentation flow

UI submit -> authenticated API -> create_offer in PostgreSQL -> savePhotos -> COMMIT -> Pending page -> My sell orders reads DB.

The old code still combines Service/Repository responsibilities in server.js and SQL functions. This fix connects the UI, not a refactor into separate layer files.

## Existing Backend reference

# Owl Pai Lei — Backend + Database

Branch: `backend+database`. Based on the team repository main branch. The team main branch also contains the Frontend.

## Structure

- backend/src/: Express API, session authentication, role checks and photo validation
- backend/database/schema.sql: PostgreSQL schema (31 tables), workflow functions and fictional seed data
- backend/scripts/: safe one-time database installer
- docs/: ER, data dictionary, business rules and design notes
- package.json / package-lock.json: root npm workspace commands

## Install and run

1. Install Node.js 22+ and PostgreSQL (tested with version 18).
2. Run `npm ci` from this repository root.
3. Create an empty database named owl_pai_lei_compact in pgAdmin.
4. Copy backend/.env.example to backend/.env and enter your own PostgreSQL username, password and port.
5. Run `npm run db:setup` once in the empty database. It refuses to overwrite an existing owl schema. Alternatively, execute backend/database/schema.sql in pgAdmin; use only one setup method.
6. Run `npm start`. Backend is available at http://127.0.0.1:3188.

GET / serves the team Frontend. GET /api/health tests the connection. The database SQL contains fictional demo data; local database contents and private credentials are not uploaded.

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

The automated test suite is no longer included. Verify the seller workflow manually: submit an offer with a photo, reload the offers list, and confirm that approved offers cannot be edited.

## Connecting the team's Frontend

The API uses relative /api paths and cookie sessions. Serve the team's Frontend and proxy /api to this Backend on the same origin, or configure a narrow allowed frontend origin and credential handling for a separate-origin deployment. Cross-origin writes are rejected by default. A standalone Frontend server requires integration configuration; do not disable these checks globally.

.env, node_modules, logs and runtime PID files are ignored by Git. Never commit private database credentials.
