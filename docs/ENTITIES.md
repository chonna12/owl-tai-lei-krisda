# Database entities

The full-project schema contains 23 tables. Buyer and Seller API responses retain their existing fields.

## Consolidation choices

- Roles are four flags on users. Each account can hold several roles.
- Each seller has one current bank account and one current identity verification on users.
- Each product stores its category name directly.
- Each order stores its single cancellation request and review.
- Platform fee and shipping values are defined by platform_configuration().
- Addresses remain separate because an account can have several.
- Sessions remain separate because accounts can log in on several devices.
- Images remain separate because each catalog product, seller offer or QC inspection can have several.
- Finance, stock, queue, shipping and audit records remain separate to retain their distinct histories and constraints.

| Entity | Purpose |
|---|---|
| users | Identity, roles, seller status, bank details and current verification |
| sessions | Login tokens and expiry |
| addresses | Multiple delivery addresses |
| products | Platform catalog and category names |
| product_variants | Sizes, colors and SKUs |
| seller_offers | Seller price, condition, defects, stock and approval |
| queue_groups | Queue for each variant and condition |
| queue_entries | Offer positions and turns |
| wishlist_items | Saved products |
| coupons | Discount rules |
| orders | Buyer, totals, shipping snapshot, cancellation and order status |
| order_items | Purchased offer and immutable price/item snapshot |
| coupon_redemptions | Usage limits and coupon history |
| payments | Payment records and duplicate protection |
| qc_inspections | QC results and seller scores |
| shipments | Inbound, outbound and return tracking |
| refunds | Buyer refunds |
| seller_charges | Seller costs such as return shipping |
| payouts | Seller settlement batches |
| payout_items | Sales included in each settlement |
| notifications | Workflow messages |
| assets | Catalog, offer and QC images/evidence |
| activity_logs | Audit, order, shipment and queue history |

These are deliberate simplifications for this prototype. Seller bank and verification history are reduced to one current record. An order can have one cancellation request. Categories use text and platform settings are maintained in SQL code.

## Validation

Fresh installation and migration from the prior 30-table schema passed against PostgreSQL 18 using fictional data. Verified registration, role checks, login, catalog, addresses, seller offers/sales, checkout, idempotent demo payment, queue price rotation, QC, receipt, payout, used-item selection, cancellation, refund and seller verification.
