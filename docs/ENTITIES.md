# Database entities

The full project schema contains 30 tables. Direct one-item checkout replaces the old cart.
Fresh installations use schema.sql. Existing databases may use remove-unused-cart.sql after exporting and clearing any selected cart items. The script refuses to remove carts with selected items.

| Table | Purpose |
|---|---|
| users | Account identity and status |
| roles | Buyer, seller, admin and QC roles |
| user_roles | Multiple roles for each account |
| sessions | Login sessions |
| addresses | User delivery addresses |
| seller_bank_accounts | Seller bank details for payouts |
| seller_verifications | Verification decisions and evidence |
| categories | Catalog categories |
| products | Platform-managed catalog products |
| product_variants | Product sizes and colors |
| platform_settings | Platform fee and shipping configuration |
| seller_offers | Seller price, condition, defects, stock and approval |
| queue_groups | Queue for each variant and condition |
| queue_entries | Offer positions and turns |
| wishlist_items | Saved products |
| coupons | Discount rules |
| orders | Buyer, totals, shipping snapshot and order status |
| order_items | Purchased offer and price snapshot |
| coupon_redemptions | Coupon usage history and limits |
| payments | Payment records and duplicate protection |
| cancellation_requests | Cancellation requests and review |
| qc_inspections | QC results and seller scores |
| shipments | Seller-to-hub, hub-to-buyer and return tracking |
| refunds | Buyer refund review and payment |
| seller_charges | Seller charges such as return shipping |
| payouts | Seller settlement batches |
| payout_items | Sales included in each settlement |
| notifications | Order and workflow messages |
| assets | Catalog, offer and QC images or evidence |
| activity_logs | Workflow and queue history |

Some workflow tables are accessed through PostgreSQL functions and views rather than directly from JavaScript. They remain part of the complete project scope.
