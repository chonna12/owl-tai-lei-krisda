# Database dictionary

Current consolidated schema with 23 tables.

## activity_logs

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| log_id | bigint | NO | PK |  |
| event_source | character varying(10) | NO |  |  |
| event_type | character varying(60) | NO |  |  |
| actor_id | bigint | YES |  | users.user_id |
| order_id | bigint | YES |  | orders.order_id |
| shipment_id | bigint | YES |  | shipments.shipment_id |
| group_id | bigint | YES |  | queue_groups.group_id |
| offer_id | bigint | YES |  | seller_offers.offer_id |
| refund_id | bigint | YES |  | refunds.refund_id |
| payout_id | bigint | YES |  | payouts.payout_id |
| verification_id | bigint | YES |  | users.user_id |
| charge_id | bigint | YES |  | seller_charges.charge_id |
| status | character varying(40) | YES |  |  |
| location | character varying(150) | YES |  |  |
| note | text | NO |  |  |
| details | jsonb | NO |  |  |
| entity_type | character varying(40) | YES |  |  |
| entity_id | bigint | YES |  |  |
| source_record_id | bigint | YES |  |  |
| created_at | timestamp with time zone | NO |  |  |

## addresses

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| address_id | bigint | NO | PK |  |
| user_id | bigint | NO |  | users.user_id |
| recipient_name | character varying(100) | NO |  |  |
| phone | character varying(30) | NO |  |  |
| address_line | text | NO |  |  |
| district | character varying(100) | NO |  |  |
| province | character varying(100) | NO |  |  |
| postal_code | character varying(15) | NO |  |  |
| is_default | boolean | NO |  |  |
| archived | boolean | NO |  |  |

## assets

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| asset_id | bigint | NO | PK |  |
| product_id | bigint | YES |  | products.product_id |
| offer_id | bigint | YES |  | seller_offers.offer_id |
| inspection_id | bigint | YES |  | qc_inspections.inspection_id |
| file_reference | text | NO |  |  |
| caption | text | NO |  |  |
| sort_order | smallint | NO |  |  |
| source_table | character varying(30) | YES |  |  |
| source_record_id | bigint | YES |  |  |

## coupon_redemptions

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| redemption_id | bigint | NO | PK |  |
| coupon_id | bigint | NO |  | coupons.coupon_id |
| user_id | bigint | NO |  | users.user_id |
| order_id | bigint | NO |  | orders.order_id |
| discount_applied | numeric(12,2) | NO |  |  |
| redeemed_at | timestamp with time zone | NO |  |  |

## coupons

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| coupon_id | bigint | NO | PK |  |
| code | character varying(40) | NO |  |  |
| discount_type | character varying(10) | NO |  |  |
| value | numeric(12,2) | NO |  |  |
| min_spend | numeric(12,2) | NO |  |  |
| starts_at | timestamp with time zone | NO |  |  |
| expires_at | timestamp with time zone | NO |  |  |
| usage_limit | integer | NO |  |  |
| active | boolean | NO |  |  |
| created_by | bigint | NO |  | users.user_id |

## notifications

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| notification_id | bigint | NO | PK |  |
| user_id | bigint | NO |  | users.user_id |
| order_id | bigint | YES |  | orders.order_id |
| offer_id | bigint | YES |  | seller_offers.offer_id |
| type | character varying(40) | NO |  |  |
| message | text | NO |  |  |
| is_read | boolean | NO |  |  |
| created_at | timestamp with time zone | NO |  |  |

## order_items

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| order_item_id | bigint | NO | PK |  |
| order_id | bigint | NO |  | orders.order_id |
| offer_id | bigint | NO |  | seller_offers.offer_id |
| seller_id | bigint | NO |  | users.user_id |
| variant_id | bigint | NO |  | product_variants.variant_id |
| product_name_snapshot | character varying(150) | NO |  |  |
| size_snapshot | character varying(30) | NO |  |  |
| color_snapshot | character varying(50) | NO |  |  |
| condition_snapshot | character varying(10) | NO |  |  |
| defects_snapshot | text | NO |  |  |
| quantity | smallint | NO |  |  |
| unit_price | numeric(12,2) | NO |  |  |
| fulfillment_status | character varying(30) | NO |  |  |

## orders

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| order_id | bigint | NO | PK |  |
| buyer_id | bigint | NO |  | users.user_id |
| status | character varying(20) | NO |  |  |
| item_subtotal | numeric(12,2) | NO |  |  |
| platform_fee | numeric(12,2) | NO |  |  |
| discount | numeric(12,2) | NO |  |  |
| shipping_fee | numeric(12,2) | NO |  |  |
| total | numeric(12,2) | NO |  |  |
| coupon_id | bigint | YES |  | coupons.coupon_id |
| created_at | timestamp with time zone | NO |  |  |
| cancellation_reason | text | YES |  |  |
| cancellation_status | character varying(20) | YES |  |  |
| cancellation_reviewed_by | bigint | YES |  | users.user_id |
| cancellation_reviewed_at | timestamp with time zone | YES |  |  |
| cancellation_created_at | timestamp with time zone | YES |  |  |
| completed_at | timestamp with time zone | YES |  |  |
| shipping_recipient_name | character varying(100) | YES |  |  |
| shipping_phone | character varying(30) | YES |  |  |
| shipping_address_line | text | YES |  |  |
| shipping_district | character varying(100) | YES |  |  |
| shipping_province | character varying(100) | YES |  |  |
| shipping_postal_code | character varying(15) | YES |  |  |

## payments

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| payment_id | bigint | NO | PK |  |
| order_id | bigint | NO |  | orders.order_id |
| amount | numeric(12,2) | NO |  |  |
| method | character varying(30) | NO |  |  |
| status | character varying(20) | NO |  |  |
| reference | character varying(120) | NO |  |  |
| verified_by | bigint | YES |  | users.user_id |
| paid_at | timestamp with time zone | YES |  |  |

## payout_items

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| payout_id | bigint | NO | PK | payouts.payout_id |
| order_item_id | bigint | NO | PK | order_items.order_item_id |
| amount | numeric(12,2) | NO |  |  |

## payouts

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| payout_id | bigint | NO | PK |  |
| seller_id | bigint | NO |  | users.user_id |
| bank_account_id | bigint | NO |  | users.user_id |
| bank_name_snapshot | character varying(100) | NO |  |  |
| account_holder_snapshot | character varying(100) | NO |  |  |
| account_number_snapshot | character varying(50) | NO |  |  |
| amount | numeric(12,2) | NO |  |  |
| status | character varying(20) | NO |  |  |
| created_by | bigint | NO |  | users.user_id |
| created_at | timestamp with time zone | NO |  |  |
| approved_by | bigint | YES |  | users.user_id |
| approved_at | timestamp with time zone | YES |  |  |
| paid_by | bigint | YES |  | users.user_id |
| paid_at | timestamp with time zone | YES |  |  |
| transfer_reference | character varying(120) | YES |  |  |

## product_variants

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| variant_id | bigint | NO | PK |  |
| product_id | bigint | NO |  | products.product_id |
| size | character varying(30) | NO |  |  |
| color | character varying(50) | NO |  |  |
| sku | character varying(80) | NO |  |  |
| active | boolean | NO |  |  |

## products

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| product_id | bigint | NO | PK |  |
| category | character varying(100) | NO |  |  |
| brand_name | character varying(100) | NO |  |  |
| name | character varying(150) | NO |  |  |
| description | text | NO |  |  |
| active | boolean | NO |  |  |
| created_by | bigint | NO |  | users.user_id |
| created_at | timestamp with time zone | NO |  |  |

## qc_inspections

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| inspection_id | bigint | NO | PK |  |
| order_item_id | bigint | NO |  | order_items.order_item_id |
| inspector_id | bigint | NO |  | users.user_id |
| result | character varying(10) | NO |  |  |
| seller_score | smallint | NO |  |  |
| notes | text | NO |  |  |
| inspected_at | timestamp with time zone | NO |  |  |

## queue_entries

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| offer_id | bigint | NO | PK | seller_offers.offer_id |
| group_id | bigint | NO |  | queue_groups.group_id |
| position | bigint | NO |  |  |
| skips_remaining | smallint | NO |  |  |

## queue_groups

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| group_id | bigint | NO | PK |  |
| variant_id | bigint | NO |  | product_variants.variant_id |
| condition | character varying(10) | NO |  |  |
| active_offer_id | bigint | YES |  | seller_offers.offer_id |
| active_since | timestamp with time zone | YES |  |  |
| next_position | bigint | NO |  |  |

## refunds

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| refund_id | bigint | NO | PK |  |
| order_id | bigint | NO |  | orders.order_id |
| payment_id | bigint | NO |  | payments.payment_id |
| amount | numeric(12,2) | NO |  |  |
| reason | text | NO |  |  |
| status | character varying(20) | NO |  |  |
| approved_by | bigint | YES |  | users.user_id |
| approved_at | timestamp with time zone | YES |  |  |
| paid_by | bigint | YES |  | users.user_id |
| paid_at | timestamp with time zone | YES |  |  |
| transfer_reference | character varying(120) | YES |  |  |

## seller_charges

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| charge_id | bigint | NO | PK |  |
| seller_id | bigint | NO |  | users.user_id |
| shipment_id | bigint | NO |  | shipments.shipment_id |
| amount | numeric(12,2) | NO |  |  |
| reason | character varying(30) | NO |  |  |
| status | character varying(20) | NO |  |  |
| payment_reference | character varying(120) | YES |  |  |
| recorded_by | bigint | NO |  | users.user_id |
| paid_at | timestamp with time zone | YES |  |  |

## seller_offers

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| offer_id | bigint | NO | PK |  |
| seller_id | bigint | NO |  | users.user_id |
| variant_id | bigint | NO |  | product_variants.variant_id |
| condition | character varying(10) | NO |  |  |
| condition_notes | text | NO |  |  |
| defects | text | NO |  |  |
| asking_price | numeric(12,2) | NO |  |  |
| available_quantity | integer | NO |  |  |
| status | character varying(20) | NO |  |  |
| created_at | timestamp with time zone | NO |  |  |
| review_decision | character varying(10) | YES |  |  |
| reviewed_by | bigint | YES |  | users.user_id |
| review_reason | text | YES |  |  |
| reviewed_at | timestamp with time zone | YES |  |  |

## sessions

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| session_id | bigint | NO | PK |  |
| user_id | bigint | NO |  | users.user_id |
| token_hash | character(64) | NO |  |  |
| expires_at | timestamp with time zone | NO |  |  |
| revoked_at | timestamp with time zone | YES |  |  |

## shipments

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| shipment_id | bigint | NO | PK |  |
| order_item_id | bigint | NO |  | order_items.order_item_id |
| leg | character varying(20) | NO |  |  |
| carrier | character varying(80) | NO |  |  |
| tracking_number | character varying(120) | NO |  |  |
| status | character varying(20) | NO |  |  |
| shipping_cost | numeric(12,2) | NO |  |  |
| payer | character varying(10) | NO |  |  |
| created_by | bigint | NO |  | users.user_id |
| shipped_at | timestamp with time zone | NO |  |  |
| delivered_at | timestamp with time zone | YES |  |  |

## users

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| user_id | bigint | NO | PK |  |
| full_name | character varying(100) | NO |  |  |
| email | character varying(254) | NO |  |  |
| phone | character varying(30) | YES |  |  |
| password_hash | text | NO |  |  |
| status | character varying(20) | NO |  |  |
| created_at | timestamp with time zone | NO |  |  |
| is_buyer | boolean | NO |  |  |
| is_seller | boolean | NO |  |  |
| is_admin | boolean | NO |  |  |
| is_qc | boolean | NO |  |  |
| bank_name | character varying(100) | YES |  |  |
| account_holder | character varying(100) | YES |  |  |
| account_number | character varying(50) | YES |  |  |
| bank_verified | boolean | NO |  |  |
| bank_archived | boolean | NO |  |  |
| id_document_reference | text | YES |  |  |
| bank_document_reference | text | YES |  |  |
| verification_status | character varying(20) | YES |  |  |
| verification_reviewer_id | bigint | YES |  | users.user_id |
| verification_review_note | text | YES |  |  |
| verification_submitted_at | timestamp with time zone | YES |  |  |
| verification_reviewed_at | timestamp with time zone | YES |  |  |
| seller_display_name | character varying(100) | YES |  |  |
| seller_status | character varying(20) | YES |  |  |
| seller_since | timestamp with time zone | YES |  |  |

## wishlist_items

| Column | Type | Nullable | Key | References |
|---|---|---|---|---|
| user_id | bigint | NO | PK | users.user_id |
| product_id | bigint | NO | PK | products.product_id |
| added_at | timestamp with time zone | NO |  |  |
