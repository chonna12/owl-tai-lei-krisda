# Data Dictionary — Owl Pai Lei

Generated from the installed PostgreSQL schema. 31 tables.

## activity_logs

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| log_id | BIGINT | NO | PK | Generated identity |
| event_source | VARCHAR(10) | NO | UK |  |
| event_type | VARCHAR(60) | NO |  | 'status_changed'::character varying |
| actor_id | BIGINT | YES | FK → users.user_id |  |
| order_id | BIGINT | YES | FK → orders.order_id |  |
| shipment_id | BIGINT | YES | FK → shipments.shipment_id |  |
| group_id | BIGINT | YES | FK → queue_groups.group_id |  |
| offer_id | BIGINT | YES | FK → seller_offers.offer_id |  |
| refund_id | BIGINT | YES | FK → refunds.refund_id |  |
| payout_id | BIGINT | YES | FK → payouts.payout_id |  |
| verification_id | BIGINT | YES | FK → seller_verifications.verification_id |  |
| charge_id | BIGINT | YES | FK → seller_charges.charge_id |  |
| status | VARCHAR(40) | YES |  |  |
| location | VARCHAR(150) | YES |  |  |
| note | TEXT | NO |  | ''::text |
| details | JSONB | NO |  | '{}'::jsonb |
| entity_type | VARCHAR(40) | YES |  |  |
| entity_id | BIGINT | YES |  |  |
| source_record_id | BIGINT | YES | UK |  |
| created_at | TIMESTAMPTZ | NO |  | now() |

## addresses

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| address_id | BIGINT | NO | PK | Generated identity |
| user_id | BIGINT | NO | FK → users.user_id |  |
| recipient_name | VARCHAR(100) | NO |  |  |
| phone | VARCHAR(30) | NO |  |  |
| address_line | TEXT | NO |  |  |
| district | VARCHAR(100) | NO |  |  |
| province | VARCHAR(100) | NO |  |  |
| postal_code | VARCHAR(15) | NO |  |  |
| is_default | BOOLEAN | NO |  | false |
| archived | BOOLEAN | NO |  | false |

## assets

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| asset_id | BIGINT | NO | PK | Generated identity |
| product_id | BIGINT | YES | FK → products.product_id |  |
| offer_id | BIGINT | YES | FK → seller_offers.offer_id |  |
| inspection_id | BIGINT | YES | FK → qc_inspections.inspection_id |  |
| file_reference | TEXT | NO |  |  |
| caption | TEXT | NO |  | ''::text |
| sort_order | SMALLINT | NO |  | 0 |
| source_table | VARCHAR(30) | YES | UK |  |
| source_record_id | BIGINT | YES | UK |  |

## cancellation_requests

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| request_id | BIGINT | NO | PK | Generated identity |
| order_id | BIGINT | NO | UK, FK → orders.order_id |  |
| buyer_id | BIGINT | NO | FK → users.user_id |  |
| reason | TEXT | NO |  |  |
| status | VARCHAR(20) | NO |  | 'pending'::character varying |
| reviewed_by | BIGINT | YES | FK → users.user_id |  |
| reviewed_at | TIMESTAMPTZ | YES |  |  |
| created_at | TIMESTAMPTZ | NO |  | now() |

## carts

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| cart_id | BIGINT | NO | PK | Generated identity |
| user_id | BIGINT | NO | UK, FK → users.user_id |  |
| variant_id | BIGINT | YES | FK → product_variants.variant_id |  |
| condition | VARCHAR(10) | YES |  |  |
| quantity | SMALLINT | NO |  | 1 |
| added_at | TIMESTAMPTZ | YES |  |  |

## categories

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| category_id | BIGINT | NO | PK | Generated identity |
| name | VARCHAR(100) | NO | UK |  |

## coupon_redemptions

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| redemption_id | BIGINT | NO | PK | Generated identity |
| coupon_id | BIGINT | NO | UK, FK → coupons.coupon_id |  |
| user_id | BIGINT | NO | UK, FK → users.user_id |  |
| order_id | BIGINT | NO | UK, FK → orders.order_id |  |
| discount_applied | NUMERIC(12,2) | NO |  |  |
| redeemed_at | TIMESTAMPTZ | NO |  | now() |

## coupons

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| coupon_id | BIGINT | NO | PK | Generated identity |
| code | VARCHAR(40) | NO | UK |  |
| discount_type | VARCHAR(10) | NO |  |  |
| value | NUMERIC(12,2) | NO |  |  |
| min_spend | NUMERIC(12,2) | NO |  | 0 |
| starts_at | TIMESTAMPTZ | NO |  |  |
| expires_at | TIMESTAMPTZ | NO |  |  |
| usage_limit | INTEGER | NO |  |  |
| active | BOOLEAN | NO |  | true |
| created_by | BIGINT | NO | FK → users.user_id |  |

## notifications

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| notification_id | BIGINT | NO | PK | Generated identity |
| user_id | BIGINT | NO | FK → users.user_id |  |
| order_id | BIGINT | YES | FK → orders.order_id |  |
| offer_id | BIGINT | YES | FK → seller_offers.offer_id |  |
| type | VARCHAR(40) | NO |  |  |
| message | TEXT | NO |  |  |
| is_read | BOOLEAN | NO |  | false |
| created_at | TIMESTAMPTZ | NO |  | now() |

## order_items

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| order_item_id | BIGINT | NO | PK | Generated identity |
| order_id | BIGINT | NO | UK, FK → orders.order_id |  |
| offer_id | BIGINT | NO | FK → seller_offers.offer_id |  |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| variant_id | BIGINT | NO | FK → product_variants.variant_id |  |
| product_name_snapshot | VARCHAR(150) | NO |  |  |
| size_snapshot | VARCHAR(30) | NO |  |  |
| color_snapshot | VARCHAR(50) | NO |  |  |
| condition_snapshot | VARCHAR(10) | NO |  |  |
| defects_snapshot | TEXT | NO |  |  |
| quantity | SMALLINT | NO |  | 1 |
| unit_price | NUMERIC(12,2) | NO |  |  |
| fulfillment_status | VARCHAR(30) | NO |  | 'awaiting_payment'::character varying |

## orders

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| order_id | BIGINT | NO | PK | Generated identity |
| buyer_id | BIGINT | NO | FK → users.user_id |  |
| status | VARCHAR(20) | NO |  | 'awaiting_payment'::character varying |
| item_subtotal | NUMERIC(12,2) | NO |  |  |
| platform_fee | NUMERIC(12,2) | NO |  |  |
| discount | NUMERIC(12,2) | NO |  | 0 |
| shipping_fee | NUMERIC(12,2) | NO |  |  |
| total | NUMERIC(12,2) | NO |  |  |
| coupon_id | BIGINT | YES | FK → coupons.coupon_id |  |
| created_at | TIMESTAMPTZ | NO |  | now() |
| completed_at | TIMESTAMPTZ | YES |  |  |
| shipping_recipient_name | VARCHAR(100) | YES |  |  |
| shipping_phone | VARCHAR(30) | YES |  |  |
| shipping_address_line | TEXT | YES |  |  |
| shipping_district | VARCHAR(100) | YES |  |  |
| shipping_province | VARCHAR(100) | YES |  |  |
| shipping_postal_code | VARCHAR(15) | YES |  |  |

## payments

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| payment_id | BIGINT | NO | PK | Generated identity |
| order_id | BIGINT | NO | FK → orders.order_id |  |
| amount | NUMERIC(12,2) | NO |  |  |
| method | VARCHAR(30) | NO |  |  |
| status | VARCHAR(20) | NO |  |  |
| reference | VARCHAR(120) | NO | UK |  |
| verified_by | BIGINT | YES | FK → users.user_id |  |
| paid_at | TIMESTAMPTZ | YES |  |  |

## payout_items

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| payout_id | BIGINT | NO | PK, FK → payouts.payout_id |  |
| order_item_id | BIGINT | NO | PK, UK, FK → order_items.order_item_id |  |
| amount | NUMERIC(12,2) | NO |  |  |

## payouts

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| payout_id | BIGINT | NO | PK | Generated identity |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| bank_account_id | BIGINT | NO | FK → seller_bank_accounts.bank_account_id |  |
| bank_name_snapshot | VARCHAR(100) | NO |  |  |
| account_holder_snapshot | VARCHAR(100) | NO |  |  |
| account_number_snapshot | VARCHAR(50) | NO |  |  |
| amount | NUMERIC(12,2) | NO |  |  |
| status | VARCHAR(20) | NO |  | 'pending'::character varying |
| created_by | BIGINT | NO | FK → users.user_id |  |
| created_at | TIMESTAMPTZ | NO |  | now() |
| approved_by | BIGINT | YES | FK → users.user_id |  |
| approved_at | TIMESTAMPTZ | YES |  |  |
| paid_by | BIGINT | YES | FK → users.user_id |  |
| paid_at | TIMESTAMPTZ | YES |  |  |
| transfer_reference | VARCHAR(120) | YES | UK |  |

## platform_settings

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| migration_reference_data | JSONB | NO |  | '{}'::jsonb |
| settings_id | SMALLINT | NO | PK |  |
| platform_fee_percent | NUMERIC(5,2) | NO |  |  |
| shipping_fee | NUMERIC(12,2) | NO |  |  |
| active_turn_hours | SMALLINT | NO |  | 24 |
| note | TEXT | NO |  |  |

## product_variants

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| variant_id | BIGINT | NO | PK | Generated identity |
| product_id | BIGINT | NO | UK, FK → products.product_id |  |
| size | VARCHAR(30) | NO | UK |  |
| color | VARCHAR(50) | NO | UK |  |
| sku | VARCHAR(80) | NO | UK |  |
| active | BOOLEAN | NO |  | true |

## products

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| product_id | BIGINT | NO | PK | Generated identity |
| category_id | BIGINT | NO | FK → categories.category_id |  |
| brand_name | VARCHAR(100) | NO |  |  |
| name | VARCHAR(150) | NO | UK |  |
| description | TEXT | NO |  | ''::text |
| active | BOOLEAN | NO |  | true |
| created_by | BIGINT | NO | FK → users.user_id |  |
| created_at | TIMESTAMPTZ | NO |  | now() |

## qc_inspections

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| inspection_id | BIGINT | NO | PK | Generated identity |
| order_item_id | BIGINT | NO | UK, FK → order_items.order_item_id |  |
| inspector_id | BIGINT | NO | FK → users.user_id |  |
| result | VARCHAR(10) | NO |  |  |
| seller_score | SMALLINT | NO |  |  |
| notes | TEXT | NO |  |  |
| inspected_at | TIMESTAMPTZ | NO |  | now() |

## queue_entries

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| offer_id | BIGINT | NO | PK, FK → seller_offers.offer_id |  |
| group_id | BIGINT | NO | UK, FK → queue_groups.group_id |  |
| position | BIGINT | NO | UK |  |
| skips_remaining | SMALLINT | NO |  |  |

## queue_groups

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| group_id | BIGINT | NO | PK | Generated identity |
| variant_id | BIGINT | NO | UK, FK → product_variants.variant_id |  |
| condition | VARCHAR(10) | NO | UK |  |
| active_offer_id | BIGINT | YES | FK → seller_offers.offer_id |  |
| active_since | TIMESTAMPTZ | YES |  |  |
| next_position | BIGINT | NO |  | 0 |

## refunds

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| refund_id | BIGINT | NO | PK | Generated identity |
| order_id | BIGINT | NO | UK, FK → orders.order_id |  |
| payment_id | BIGINT | NO | UK, FK → payments.payment_id |  |
| amount | NUMERIC(12,2) | NO |  |  |
| reason | TEXT | NO |  |  |
| status | VARCHAR(20) | NO |  | 'requested'::character varying |
| approved_by | BIGINT | YES | FK → users.user_id |  |
| approved_at | TIMESTAMPTZ | YES |  |  |
| paid_by | BIGINT | YES | FK → users.user_id |  |
| paid_at | TIMESTAMPTZ | YES |  |  |
| transfer_reference | VARCHAR(120) | YES | UK |  |

## roles

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| role_id | SMALLINT | NO | PK | Generated identity |
| name | VARCHAR(20) | NO | UK |  |

## seller_bank_accounts

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| bank_account_id | BIGINT | NO | PK | Generated identity |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| bank_name | VARCHAR(100) | NO |  |  |
| account_holder | VARCHAR(100) | NO |  |  |
| account_number | VARCHAR(50) | NO |  |  |
| is_verified | BOOLEAN | NO |  | false |
| archived | BOOLEAN | NO |  | false |

## seller_charges

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| charge_id | BIGINT | NO | PK | Generated identity |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| shipment_id | BIGINT | NO | UK, FK → shipments.shipment_id |  |
| amount | NUMERIC(12,2) | NO |  |  |
| reason | VARCHAR(30) | NO |  | 'return_shipping'::character varying |
| status | VARCHAR(20) | NO |  | 'unpaid'::character varying |
| payment_reference | VARCHAR(120) | YES |  |  |
| recorded_by | BIGINT | NO | FK → users.user_id |  |
| paid_at | TIMESTAMPTZ | YES |  |  |

## seller_offers

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| offer_id | BIGINT | NO | PK | Generated identity |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| variant_id | BIGINT | NO | FK → product_variants.variant_id |  |
| condition | VARCHAR(10) | NO |  |  |
| condition_notes | TEXT | NO |  | ''::text |
| defects | TEXT | NO |  | ''::text |
| asking_price | NUMERIC(12,2) | NO |  |  |
| available_quantity | INTEGER | NO |  |  |
| status | VARCHAR(20) | NO |  | 'pending'::character varying |
| created_at | TIMESTAMPTZ | NO |  | now() |
| review_decision | VARCHAR(10) | YES |  |  |
| reviewed_by | BIGINT | YES | FK → users.user_id |  |
| review_reason | TEXT | YES |  |  |
| reviewed_at | TIMESTAMPTZ | YES |  |  |

## seller_verifications

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| verification_id | BIGINT | NO | PK | Generated identity |
| seller_id | BIGINT | NO | FK → users.user_id |  |
| id_document_reference | TEXT | NO |  |  |
| bank_document_reference | TEXT | NO |  |  |
| status | VARCHAR(20) | NO |  | 'pending'::character varying |
| reviewer_id | BIGINT | YES | FK → users.user_id |  |
| review_note | TEXT | YES |  |  |
| submitted_at | TIMESTAMPTZ | NO |  | now() |
| reviewed_at | TIMESTAMPTZ | YES |  |  |

## sessions

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| session_id | BIGINT | NO | PK | Generated identity |
| user_id | BIGINT | NO | FK → users.user_id |  |
| token_hash | VARCHAR(64) | NO | UK |  |
| expires_at | TIMESTAMPTZ | NO |  |  |
| revoked_at | TIMESTAMPTZ | YES |  |  |

## shipments

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| shipment_id | BIGINT | NO | PK | Generated identity |
| order_item_id | BIGINT | NO | UK, FK → order_items.order_item_id |  |
| leg | VARCHAR(20) | NO | UK |  |
| carrier | VARCHAR(80) | NO | UK |  |
| tracking_number | VARCHAR(120) | NO | UK |  |
| status | VARCHAR(20) | NO |  | 'in_transit'::character varying |
| shipping_cost | NUMERIC(12,2) | NO |  | 0 |
| payer | VARCHAR(10) | NO |  |  |
| created_by | BIGINT | NO | FK → users.user_id |  |
| shipped_at | TIMESTAMPTZ | NO |  | now() |
| delivered_at | TIMESTAMPTZ | YES |  |  |

## user_roles

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| user_id | BIGINT | NO | PK, FK → users.user_id |  |
| role_id | SMALLINT | NO | PK, FK → roles.role_id |  |

## users

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| user_id | BIGINT | NO | PK | Generated identity |
| full_name | VARCHAR(100) | NO |  |  |
| email | VARCHAR(254) | NO | UK |  |
| phone | VARCHAR(30) | YES |  |  |
| password_hash | TEXT | NO |  |  |
| status | VARCHAR(20) | NO |  | 'active'::character varying |
| created_at | TIMESTAMPTZ | NO |  | now() |
| seller_display_name | VARCHAR(100) | YES |  |  |
| seller_status | VARCHAR(20) | YES |  |  |
| seller_since | TIMESTAMPTZ | YES |  |  |

## wishlist_items

| Column | Type | Null allowed | Key / target | Default |
|---|---|---|---|---|
| user_id | BIGINT | NO | PK, FK → users.user_id |  |
| product_id | BIGINT | NO | PK, FK → products.product_id |  |
| added_at | TIMESTAMPTZ | NO |  | now() |

## Reading the ER

The diagram summarizes foreign-key links. Optionality and composite/unique cardinalities are specified in this dictionary and the SQL constraints, not exhaustively in the compact overview.
