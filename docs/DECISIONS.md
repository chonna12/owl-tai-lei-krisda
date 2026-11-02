# Database decisions and traceability

| Requirement | Database support |
|---|---|
| One account buys and sells | users + roles + user_roles |
| Owl selects the catalog | products + variants, created_by Admin guard |
| Many sellers offer the same item | seller_offers references shared variant |
| New multiple units, used one unit with defects | seller_offers CHECK + create_offer |
| Admin approves before sale | seller_offers.review_* + review_offer |
| Approved offer cannot be edited | offer protection triggers |
| FIFO turn, 24-hour timeout | queue_groups + queue_entries + advance_queue |
| Lower QC rating reduces opportunities | qc_skip_count + stored skip counter |
| One item per cart/order | PK(cart_id), UNIQUE(order_id), quantity=1 checks |
| Reserve after confirmed payment | confirm_payment transaction and group lock |
| Buyer never sees Seller identity | public_market and buyer_orders omit seller references |
| Preserve purchase-time details | immutable order/item/address snapshots |
| Coupon one use per buyer and order | two unique constraints + locked quota check |
| QC staff rate Seller, not Buyer | qc_inspections inspector role guard; no buyer rating table |
| QC evidence and saved PASS before dispatch | deferred evidence constraint + shipment guard |
| Return Buyer full payment including initial shipping | refund amount equals captured payment |
| Seller pays return shipping | hub_to_seller payer constraint + seller_charges |
| Admin pays Seller after Buyer receipt | eligible_payouts + payout workflow |
| Prevent duplicate payout | UNIQUE(order_item_id) in payout_items |
| No hard deletion of historic transactions | referenced records, withdrawal and immutable histories |
| Notifications and audit | recipient user FK, action records without secrets |

## Normalization and snapshots

Catalog names and options are separated from seller price, condition and stock. Roles use a bridge table.
QC evidence and shipping events are child rows rather than comma-separated text fields.
One-item cart/order constraints follow the current scope.

Order item details, bank destination and shipping address snapshots intentionally repeat data to preserve
the agreement at transaction time. They are historical records, not claims of strict 3NF for every table.
Order totals are stored with arithmetic checks. Financial and item snapshots are immutable.

## Backend integration boundary

The existing Seller API project has its own 14-table prototype. This 41-table schema is a new full-project
design, not a drop-in migration. Update the old API queries or wrap these functions in new endpoints.
This delivery does not claim that existing Frontend or payment/courier integrations have been built.

## Finance interpretation

The user's latest clarification is interpreted as Admin review/payment to Seller after completion.
For QC failures the simplest proposed policy is a full refund to Buyer, including initial shipping,
with return shipping billed to Seller separately. Admin records refund approval and transfer as a support workflow.
The example SQL uses DEMO references and never calls a bank or transfers money.


See CONSOLIDATION.md for merged storage. `platform_settings.migration_reference_data` is an archive of retired reference IDs, not a runtime business-rule store. Buyer-facing views omit seller identities but do not themselves enforce per-user row access. Backend must bind authenticated actors and use parameterized queries. Workflow actor IDs are not a substitute for authentication; database-owner credentials can bypass application rules. No real payment gateway, courier integration, scheduler, or production access-control deployment is included.
