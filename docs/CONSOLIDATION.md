# Consolidation map — 41 → 31 tables

| Original | Compact location | Preservation / tradeoff |
|---|---|---|
| seller_profiles | users.seller_display_name / seller_status / seller_since | Seller role still uses user_roles. Non-sellers have null profile fields. |
| brands | products.brand_name | Brand name remains filterable; no centralized brand FK. Old IDs and unused brand names remain in platform_settings.migration_reference_data after migration. |
| offer_reviews | seller_offers.review_decision / reviewed_by / review_reason / reviewed_at | One final review per offer. Reviewed offer must be withdrawn and resubmitted for changes. Old review IDs archived in migration metadata. |
| carts + cart_items | carts | One selected variant/condition per cart. Empty cart has null selection and quantity 1 as the default selection quantity. |
| order_addresses | orders.shipping_* | Purchase-time address snapshot remains immutable. Personal addresses remain separately editable. |
| product_images + offer_photos + qc_evidence | assets | Exactly one real product/offer/inspection FK owner; caption, ordering and source IDs retained. QC evidence immutable. |
| queue_events + shipment_events + order_status_history + audit_logs | activity_logs | event_source distinguishes queue/shipment/order/audit. Existing timestamps, actors, notes and details retained. Journal is append-only. |

The other 24 tables retain their business responsibilities. 31 is the physical table count; views are not counted as replacement tables.

## Tables retained separately

Payments, refunds, seller charges, payouts and payout items remain separate to distinguish buyer receipts, full refunds, seller return-shipping debt and seller settlements. QC inspections remain separate from approval. Bank accounts, verification, sessions and role assignments remain separate because they can have multiple independent records per user.

## Backend changes required

- Replace image/evidence inserts with assets and set exactly one owner FK.
- Replace historical log queries with activity_logs filtered by event_source.
- Read profile and approval fields from users/seller_offers.
- Read shipping snapshots from orders, not current personal addresses.
- Read/write one selected item directly on carts.
- Filter brands using products.brand_name. Renaming a brand now requires updating its products together.
- Use the same workflow functions where possible: create_offer, review_offer, checkout, record_qc, etc.

The merge reduces tables, not the underlying business complexity. The combined assets/log tables have nullable type-specific columns; this is a deliberate prototype tradeoff. No claim is made that merging these tables automatically improves normalization or performance.
