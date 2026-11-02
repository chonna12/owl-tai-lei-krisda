-- Owl Pai Lei compact database: 31 tables. Install once in an EMPTY database.
BEGIN;

-- 001_schema.sql
-- Owl Pai Lei: compact complete-project implementation design, PostgreSQL 18.
-- Run once in an EMPTY dedicated database. Existing Seller tables are not migrated.

CREATE SCHEMA owl;
SET search_path TO owl, public;

CREATE TABLE users (
  user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(254) NOT NULL UNIQUE CHECK (email=lower(email)),
  phone VARCHAR(30),
  password_hash TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  seller_display_name VARCHAR(100),
  seller_status VARCHAR(20) CHECK(seller_status IN ('active','suspended')),
  seller_since TIMESTAMPTZ,
  CHECK ((seller_display_name IS NULL AND seller_status IS NULL AND seller_since IS NULL) OR
    (seller_display_name IS NOT NULL AND seller_status IS NOT NULL AND seller_since IS NOT NULL))
);
CREATE TABLE roles (
  role_id SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name VARCHAR(20) NOT NULL UNIQUE CHECK(name IN ('buyer','seller','admin','qc'))
);
CREATE TABLE user_roles (
  user_id BIGINT NOT NULL REFERENCES users,
  role_id SMALLINT NOT NULL REFERENCES roles,
  PRIMARY KEY(user_id,role_id)
);
CREATE TABLE sessions (
  session_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);
CREATE TABLE addresses (
  address_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users,
  recipient_name VARCHAR(100) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  address_line TEXT NOT NULL,
  district VARCHAR(100) NOT NULL,
  province VARCHAR(100) NOT NULL,
  postal_code VARCHAR(15) NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  archived BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX one_default_address ON addresses(user_id) WHERE is_default AND NOT archived;
CREATE TABLE seller_bank_accounts (
  bank_account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  bank_name VARCHAR(100) NOT NULL,
  account_holder VARCHAR(100) NOT NULL,
  account_number VARCHAR(50) NOT NULL,
  is_verified BOOLEAN NOT NULL DEFAULT false,
  archived BOOLEAN NOT NULL DEFAULT false
);
CREATE TABLE seller_verifications (
  verification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  id_document_reference TEXT NOT NULL,
  bank_document_reference TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
  reviewer_id BIGINT REFERENCES users,
  review_note TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  CHECK ((status='pending' AND reviewer_id IS NULL AND reviewed_at IS NULL)
    OR (status<>'pending' AND reviewer_id IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE categories (
  category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE
);
CREATE TABLE products (
  product_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id BIGINT NOT NULL REFERENCES categories,
  brand_name VARCHAR(100) NOT NULL,
  name VARCHAR(150) NOT NULL UNIQUE,
  description TEXT NOT NULL DEFAULT '',
  active BOOLEAN NOT NULL DEFAULT true,
  created_by BIGINT NOT NULL REFERENCES users,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE product_variants (
  variant_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products,
  size VARCHAR(30) NOT NULL,
  color VARCHAR(50) NOT NULL,
  sku VARCHAR(80) NOT NULL UNIQUE,
  active BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(product_id,size,color)
);
CREATE TABLE platform_settings (
  migration_reference_data JSONB NOT NULL DEFAULT '{}',
  settings_id SMALLINT PRIMARY KEY CHECK(settings_id=1),
  platform_fee_percent NUMERIC(5,2) NOT NULL CHECK(platform_fee_percent BETWEEN 0 AND 100),
  shipping_fee NUMERIC(12,2) NOT NULL CHECK(shipping_fee>=0),
  active_turn_hours SMALLINT NOT NULL DEFAULT 24 CHECK(active_turn_hours=24),
  note TEXT NOT NULL
);

CREATE TABLE seller_offers (
  offer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  variant_id BIGINT NOT NULL REFERENCES product_variants,
  condition VARCHAR(10) NOT NULL CHECK(condition IN ('new','used')),
  condition_notes TEXT NOT NULL DEFAULT '',
  defects TEXT NOT NULL DEFAULT '',
  asking_price NUMERIC(12,2) NOT NULL CHECK(asking_price>0),
  available_quantity INTEGER NOT NULL CHECK(available_quantity>=0),
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','withdrawn')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  review_decision VARCHAR(10) CHECK(review_decision IN ('approve','reject')),
  reviewed_by BIGINT REFERENCES users(user_id),
  review_reason TEXT,
  reviewed_at TIMESTAMPTZ,
  CHECK ((review_decision IS NULL AND reviewed_by IS NULL AND reviewed_at IS NULL) OR
    (review_decision IS NOT NULL AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CHECK (review_decision IS DISTINCT FROM 'reject' OR length(trim(review_reason))>0),
  CHECK(condition<>'used' OR (available_quantity<=1 AND length(trim(defects))>0))
);
CREATE INDEX offers_seller_idx ON seller_offers(seller_id,status);
CREATE TABLE queue_groups (
  group_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  variant_id BIGINT NOT NULL REFERENCES product_variants,
  condition VARCHAR(10) NOT NULL CHECK(condition IN ('new','used')),
  active_offer_id BIGINT REFERENCES seller_offers,
  active_since TIMESTAMPTZ,
  next_position BIGINT NOT NULL DEFAULT 0,
  UNIQUE(variant_id,condition),
  CHECK((active_offer_id IS NULL)=(active_since IS NULL))
);
CREATE TABLE queue_entries (
  offer_id BIGINT PRIMARY KEY REFERENCES seller_offers,
  group_id BIGINT NOT NULL REFERENCES queue_groups,
  position BIGINT NOT NULL,
  skips_remaining SMALLINT NOT NULL CHECK(skips_remaining BETWEEN 0 AND 3),
  UNIQUE(group_id,position)
);

CREATE TABLE wishlist_items (
  user_id BIGINT NOT NULL REFERENCES users,
  product_id BIGINT NOT NULL REFERENCES products,
  added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,product_id)
);
CREATE TABLE carts (
  cart_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL UNIQUE REFERENCES users,
  variant_id BIGINT REFERENCES product_variants,
  condition VARCHAR(10) CHECK(condition IN ('new','used')),
  quantity SMALLINT NOT NULL DEFAULT 1 CHECK(quantity=1),
  added_at TIMESTAMPTZ,
  CHECK ((variant_id IS NULL AND condition IS NULL AND added_at IS NULL) OR
    (variant_id IS NOT NULL AND condition IS NOT NULL AND added_at IS NOT NULL))
);
-- PK(cart_id) deliberately limits each cart to one selected item.
CREATE TABLE coupons (
  coupon_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code VARCHAR(40) NOT NULL UNIQUE,
  discount_type VARCHAR(10) NOT NULL CHECK(discount_type IN ('fixed','percent')),
  value NUMERIC(12,2) NOT NULL CHECK(value>0),
  min_spend NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(min_spend>=0),
  starts_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  usage_limit INTEGER NOT NULL CHECK(usage_limit>0),
  active BOOLEAN NOT NULL DEFAULT true,
  created_by BIGINT NOT NULL REFERENCES users,
  CHECK(expires_at>starts_at),
  CHECK(discount_type<>'percent' OR value<=100)
);

CREATE TABLE orders (
  order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  buyer_id BIGINT NOT NULL REFERENCES users,
  status VARCHAR(20) NOT NULL DEFAULT 'awaiting_payment'
    CHECK(status IN ('awaiting_payment','processing','completed','cancelled')),
  item_subtotal NUMERIC(12,2) NOT NULL CHECK(item_subtotal>0),
  platform_fee NUMERIC(12,2) NOT NULL CHECK(platform_fee>=0),
  discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(discount>=0),
  shipping_fee NUMERIC(12,2) NOT NULL CHECK(shipping_fee>=0),
  total NUMERIC(12,2) NOT NULL CHECK(total>=0),
  coupon_id BIGINT REFERENCES coupons,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  shipping_recipient_name VARCHAR(100),
  shipping_phone VARCHAR(30),
  shipping_address_line TEXT,
  shipping_district VARCHAR(100),
  shipping_province VARCHAR(100),
  shipping_postal_code VARCHAR(15),
  CHECK(discount<=item_subtotal+platform_fee),
  CHECK(total=item_subtotal+platform_fee-discount+shipping_fee),
  CHECK((status='completed')=(completed_at IS NOT NULL))
);
CREATE INDEX orders_buyer_idx ON orders(buyer_id,created_at);
CREATE TABLE order_items (
  order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL UNIQUE REFERENCES orders,
  offer_id BIGINT NOT NULL REFERENCES seller_offers,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  variant_id BIGINT NOT NULL REFERENCES product_variants,
  product_name_snapshot VARCHAR(150) NOT NULL,
  size_snapshot VARCHAR(30) NOT NULL,
  color_snapshot VARCHAR(50) NOT NULL,
  condition_snapshot VARCHAR(10) NOT NULL CHECK(condition_snapshot IN ('new','used')),
  defects_snapshot TEXT NOT NULL,
  quantity SMALLINT NOT NULL DEFAULT 1 CHECK(quantity=1),
  unit_price NUMERIC(12,2) NOT NULL CHECK(unit_price>0),
  fulfillment_status VARCHAR(30) NOT NULL DEFAULT 'awaiting_payment'
    CHECK(fulfillment_status IN ('awaiting_payment','awaiting_seller_shipment','inbound','awaiting_qc',
      'ready_to_ship','outbound','completed','qc_failed','return_in_transit','returned','cancelled'))
);
CREATE INDEX order_items_seller_idx ON order_items(seller_id,fulfillment_status);
CREATE TABLE coupon_redemptions (
  redemption_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coupon_id BIGINT NOT NULL REFERENCES coupons,
  user_id BIGINT NOT NULL REFERENCES users,
  order_id BIGINT NOT NULL UNIQUE REFERENCES orders,
  discount_applied NUMERIC(12,2) NOT NULL CHECK(discount_applied>0),
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(coupon_id,user_id)
);
CREATE TABLE payments (
  payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>=0),
  method VARCHAR(30) NOT NULL,
  status VARCHAR(20) NOT NULL CHECK(status IN ('pending','failed','captured')),
  reference VARCHAR(120) NOT NULL UNIQUE,
  verified_by BIGINT REFERENCES users,
  paid_at TIMESTAMPTZ,
  CHECK((status='captured')=(paid_at IS NOT NULL)),
  CHECK(status<>'captured' OR verified_by IS NOT NULL)
);
CREATE UNIQUE INDEX one_captured_payment ON payments(order_id) WHERE status='captured';
CREATE TABLE cancellation_requests (
  request_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL UNIQUE REFERENCES orders,
  buyer_id BIGINT NOT NULL REFERENCES users,
  reason TEXT NOT NULL CHECK(length(trim(reason))>0),
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
  reviewed_by BIGINT REFERENCES users,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE qc_inspections (
  inspection_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_item_id BIGINT NOT NULL UNIQUE REFERENCES order_items,
  inspector_id BIGINT NOT NULL REFERENCES users,
  result VARCHAR(10) NOT NULL CHECK(result IN ('pass','fail')),
  seller_score SMALLINT NOT NULL CHECK(seller_score BETWEEN 1 AND 5),
  notes TEXT NOT NULL CHECK(length(trim(notes))>0),
  inspected_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE shipments (
  shipment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_item_id BIGINT NOT NULL REFERENCES order_items,
  leg VARCHAR(20) NOT NULL CHECK(leg IN ('seller_to_hub','hub_to_buyer','hub_to_seller')),
  carrier VARCHAR(80) NOT NULL,
  tracking_number VARCHAR(120) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'in_transit' CHECK(status IN ('in_transit','delivered')),
  shipping_cost NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK(shipping_cost>=0),
  payer VARCHAR(10) NOT NULL CHECK(payer IN ('seller','buyer','platform')),
  created_by BIGINT NOT NULL REFERENCES users,
  shipped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ,
  UNIQUE(order_item_id,leg),
  UNIQUE(carrier,tracking_number),
  CHECK((status='delivered')=(delivered_at IS NOT NULL)),
  CHECK(leg<>'hub_to_seller' OR payer='seller')
);
CREATE TABLE refunds (
  refund_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL UNIQUE REFERENCES orders,
  payment_id BIGINT NOT NULL UNIQUE REFERENCES payments,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>=0),
  reason TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','approved','paid')),
  approved_by BIGINT REFERENCES users,
  approved_at TIMESTAMPTZ,
  paid_by BIGINT REFERENCES users,
  paid_at TIMESTAMPTZ,
  transfer_reference VARCHAR(120) UNIQUE,
  CHECK((status IN ('approved','paid'))=(approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK((status='paid')=(paid_by IS NOT NULL AND paid_at IS NOT NULL AND transfer_reference IS NOT NULL))
);
CREATE TABLE seller_charges (
  charge_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  shipment_id BIGINT NOT NULL UNIQUE REFERENCES shipments,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>=0),
  reason VARCHAR(30) NOT NULL DEFAULT 'return_shipping' CHECK(reason='return_shipping'),
  status VARCHAR(20) NOT NULL DEFAULT 'unpaid' CHECK(status IN ('unpaid','paid')),
  payment_reference VARCHAR(120),
  recorded_by BIGINT NOT NULL REFERENCES users,
  paid_at TIMESTAMPTZ,
  CHECK((status='paid')=(payment_reference IS NOT NULL AND paid_at IS NOT NULL))
);
CREATE TABLE payouts (
  payout_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  seller_id BIGINT NOT NULL REFERENCES users(user_id),
  bank_account_id BIGINT NOT NULL REFERENCES seller_bank_accounts,
  bank_name_snapshot VARCHAR(100) NOT NULL,
  account_holder_snapshot VARCHAR(100) NOT NULL,
  account_number_snapshot VARCHAR(50) NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','paid')),
  created_by BIGINT NOT NULL REFERENCES users,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by BIGINT REFERENCES users,
  approved_at TIMESTAMPTZ,
  paid_by BIGINT REFERENCES users,
  paid_at TIMESTAMPTZ,
  transfer_reference VARCHAR(120) UNIQUE,
  CHECK((status IN ('approved','paid'))=(approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK((status='paid')=(paid_by IS NOT NULL AND paid_at IS NOT NULL AND transfer_reference IS NOT NULL))
);
CREATE TABLE payout_items (
  payout_id BIGINT NOT NULL REFERENCES payouts,
  order_item_id BIGINT NOT NULL UNIQUE REFERENCES order_items,
  amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
  PRIMARY KEY(payout_id,order_item_id)
);
CREATE TABLE notifications (
  notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users,
  order_id BIGINT REFERENCES orders,
  offer_id BIGINT REFERENCES seller_offers,
  type VARCHAR(40) NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications(user_id,is_read,created_at);

-- Image/evidence ownership retains real FKs; no JSON array or polymorphic owner ID.
CREATE TABLE assets (
 asset_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 product_id BIGINT REFERENCES products,
 offer_id BIGINT REFERENCES seller_offers,
 inspection_id BIGINT REFERENCES qc_inspections,
 file_reference TEXT NOT NULL,
 caption TEXT NOT NULL DEFAULT '',
 sort_order SMALLINT NOT NULL DEFAULT 0 CHECK(sort_order>=0),
 source_table VARCHAR(30),
 source_record_id BIGINT,
 CHECK(num_nonnulls(product_id,offer_id,inspection_id)=1),
 CHECK((source_table IS NULL)=(source_record_id IS NULL)),
 UNIQUE(source_table,source_record_id)
);
CREATE UNIQUE INDEX assets_product_file ON assets(product_id,file_reference) WHERE product_id IS NOT NULL;
CREATE UNIQUE INDEX assets_offer_file ON assets(offer_id,file_reference) WHERE offer_id IS NOT NULL;
CREATE UNIQUE INDEX assets_qc_file ON assets(inspection_id,file_reference) WHERE inspection_id IS NOT NULL;

-- One append-only journal; important business references keep FK constraints.
CREATE TABLE activity_logs (
 log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 event_source VARCHAR(10) NOT NULL CHECK(event_source IN ('queue','shipment','order','audit')),
 event_type VARCHAR(60) NOT NULL DEFAULT 'status_changed',
 actor_id BIGINT REFERENCES users,
 order_id BIGINT REFERENCES orders,
 shipment_id BIGINT REFERENCES shipments,
 group_id BIGINT REFERENCES queue_groups,
 offer_id BIGINT REFERENCES seller_offers,
 refund_id BIGINT REFERENCES refunds,
 payout_id BIGINT REFERENCES payouts,
 verification_id BIGINT REFERENCES seller_verifications,
 charge_id BIGINT REFERENCES seller_charges,
 status VARCHAR(40),
 location VARCHAR(150),
 note TEXT NOT NULL DEFAULT '',
 details JSONB NOT NULL DEFAULT '{}',
 entity_type VARCHAR(40),
 entity_id BIGINT,
 source_record_id BIGINT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK((event_source='queue' AND group_id IS NOT NULL) OR
       (event_source='shipment' AND shipment_id IS NOT NULL AND actor_id IS NOT NULL) OR
       (event_source='order' AND order_id IS NOT NULL AND status IS NOT NULL AND actor_id IS NOT NULL) OR
       (event_source='audit' AND entity_type IS NOT NULL AND entity_id IS NOT NULL AND actor_id IS NOT NULL)),
 UNIQUE(event_source,source_record_id)
);
CREATE INDEX activity_order_idx ON activity_logs(order_id,created_at);
CREATE INDEX activity_shipment_idx ON activity_logs(shipment_id,created_at);
CREATE INDEX activity_group_idx ON activity_logs(group_id,created_at);
CREATE INDEX activity_actor_idx ON activity_logs(actor_id,created_at);


-- 002_workflows.sql

SET search_path TO owl, public;

CREATE FUNCTION has_role(p_user BIGINT,p_role TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path=owl,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) JOIN users u USING(user_id)
 WHERE ur.user_id=p_user AND r.name=p_role AND u.status='active');
$$;
CREATE FUNCTION require_role(p_user BIGINT,p_role TEXT) RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF NOT has_role(p_user,p_role) THEN RAISE EXCEPTION 'Active % role required',p_role; END IF;
END; $$;
CREATE FUNCTION log_action(p_actor BIGINT,p_action TEXT,p_entity TEXT,p_id BIGINT) RETURNS VOID
LANGUAGE sql SET search_path=owl,pg_temp AS $$
 INSERT INTO activity_logs(event_source,actor_id,event_type,entity_type,entity_id) VALUES('audit',p_actor,p_action,p_entity,p_id);
$$;
CREATE FUNCTION log_order(p_order BIGINT,p_status TEXT,p_actor BIGINT,p_note TEXT DEFAULT '') RETURNS VOID
LANGUAGE sql SET search_path=owl,pg_temp AS $$
 INSERT INTO activity_logs(event_source,order_id,status,actor_id,note) VALUES('order',p_order,p_status,p_actor,p_note);
$$;

CREATE FUNCTION guard_offer_edit() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Withdraw offers; never hard-delete their history'; END IF;
 IF OLD.status<>'pending' AND
   ROW(NEW.seller_id,NEW.variant_id,NEW.condition,NEW.defects,NEW.condition_notes,NEW.asking_price)
   IS DISTINCT FROM ROW(OLD.seller_id,OLD.variant_id,OLD.condition,OLD.defects,OLD.condition_notes,OLD.asking_price)
 THEN RAISE EXCEPTION 'Approved/rejected/withdrawn offer details are immutable'; END IF;
 IF OLD.status<>'pending' AND NEW.status<>OLD.status AND NEW.status<>'withdrawn'
 THEN RAISE EXCEPTION 'Submit a new offer to request approval again'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER protect_offer BEFORE UPDATE OR DELETE ON seller_offers FOR EACH ROW EXECUTE FUNCTION guard_offer_edit();
CREATE FUNCTION guard_offer_photo() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE v_offer BIGINT;
BEGIN
 v_offer:=CASE WHEN TG_OP='DELETE' THEN OLD.offer_id ELSE NEW.offer_id END;
 IF EXISTS(SELECT 1 FROM seller_offers WHERE offer_id=v_offer AND status<>'pending')
 THEN RAISE EXCEPTION 'Photos cannot change after review'; END IF;
 IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM seller_offers WHERE offer_id=OLD.offer_id AND status<>'pending')
 THEN RAISE EXCEPTION 'Reviewed photos cannot move'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
CREATE TRIGGER protect_offer_photos BEFORE INSERT OR UPDATE OR DELETE ON assets FOR EACH ROW EXECUTE FUNCTION guard_offer_photo();
CREATE FUNCTION immutable_record() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Final or historical records cannot be edited or deleted'; END; $$;
CREATE TRIGGER immutable_qc BEFORE UPDATE OR DELETE ON qc_inspections FOR EACH ROW EXECUTE FUNCTION immutable_record();

CREATE FUNCTION create_offer(p_seller BIGINT,p_variant BIGINT,p_condition TEXT,p_price NUMERIC,
 p_quantity INTEGER,p_defects TEXT DEFAULT '',p_notes TEXT DEFAULT '') RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE v_id BIGINT;
BEGIN
 PERFORM require_role(p_seller,'seller');
 IF NOT EXISTS(SELECT 1 FROM users WHERE user_id=p_seller AND seller_status='active') THEN RAISE EXCEPTION 'Active seller profile required'; END IF;
 IF p_quantity<1 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
 IF NOT EXISTS(SELECT 1 FROM product_variants v JOIN products p USING(product_id) WHERE v.variant_id=p_variant AND v.active AND p.active)
 THEN RAISE EXCEPTION 'Choose an existing active Owl catalog variant'; END IF;
 INSERT INTO seller_offers(seller_id,variant_id,condition,asking_price,available_quantity,defects,condition_notes)
 VALUES(p_seller,p_variant,p_condition,p_price,p_quantity,p_defects,p_notes) RETURNING offer_id INTO v_id;
 PERFORM log_action(p_seller,'offer_created','seller_offer',v_id);
 RETURN v_id;
END; $$;
CREATE FUNCTION edit_pending_offer(p_seller BIGINT,p_offer BIGINT,p_price NUMERIC,p_quantity INTEGER,p_defects TEXT,p_notes TEXT DEFAULT '')
RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers;
BEGIN
 PERFORM require_role(p_seller,'seller');
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer AND seller_id=p_seller FOR UPDATE;
 IF NOT FOUND OR f.status<>'pending' THEN RAISE EXCEPTION 'Only your pending offer can be edited'; END IF;
 IF p_quantity<1 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
 UPDATE seller_offers SET asking_price=p_price,available_quantity=p_quantity,defects=p_defects,condition_notes=p_notes WHERE offer_id=p_offer;
 PERFORM log_action(p_seller,'offer_edited','seller_offer',p_offer);
END; $$;

CREATE FUNCTION qc_skip_count(p_seller BIGINT) RETURNS SMALLINT LANGUAGE sql STABLE SET search_path=owl,pg_temp AS $$
 SELECT CASE WHEN coalesce(avg(q.seller_score),4)>=4 THEN 0 WHEN avg(q.seller_score)>=3 THEN 1
 WHEN avg(q.seller_score)>=2 THEN 2 ELSE 3 END::smallint
 FROM qc_inspections q JOIN order_items i USING(order_item_id) WHERE i.seller_id=p_seller;
$$;
CREATE FUNCTION queue_position(p_group BIGINT) RETURNS BIGINT LANGUAGE sql SET search_path=owl,pg_temp AS $$
 UPDATE queue_groups SET next_position=next_position+1 WHERE group_id=p_group RETURNING next_position;
$$;
CREATE FUNCTION ensure_group(p_variant BIGINT,p_condition TEXT) RETURNS BIGINT LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE v_id BIGINT;
BEGIN
 INSERT INTO queue_groups(variant_id,condition) VALUES(p_variant,p_condition) ON CONFLICT(variant_id,condition) DO NOTHING;
 SELECT group_id INTO v_id FROM queue_groups WHERE variant_id=p_variant AND condition=p_condition FOR UPDATE;
 RETURN v_id;
END; $$;
CREATE FUNCTION queue_add(p_group BIGINT,p_offer BIGINT,p_event TEXT DEFAULT 'joined') RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers;
BEGIN
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer;
 INSERT INTO queue_entries(offer_id,group_id,position,skips_remaining)
 VALUES(p_offer,p_group,queue_position(p_group),qc_skip_count(f.seller_id))
 ON CONFLICT(offer_id) DO UPDATE SET position=excluded.position,skips_remaining=excluded.skips_remaining;
 INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',p_group,p_offer,p_event);
END; $$;

CREATE FUNCTION advance_queue(p_group BIGINT,p_now TIMESTAMPTZ DEFAULT now()) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE g queue_groups; f seller_offers; e queue_entries; n INTEGER; tries INTEGER;
BEGIN
 SELECT * INTO g FROM queue_groups WHERE group_id=p_group FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Queue group missing'; END IF;
 IF g.active_offer_id IS NOT NULL THEN
  SELECT * INTO f FROM seller_offers WHERE offer_id=g.active_offer_id FOR UPDATE;
  IF f.status='approved' AND f.available_quantity>0 AND g.active_since>p_now-interval '24 hours' THEN RETURN f.offer_id; END IF;
  IF f.status='approved' AND f.available_quantity>0 THEN PERFORM queue_add(p_group,f.offer_id,'expired');
  ELSE DELETE FROM queue_entries WHERE offer_id=g.active_offer_id; END IF;
  UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE group_id=p_group;
 END IF;
 DELETE FROM queue_entries qe USING seller_offers sf WHERE qe.offer_id=sf.offer_id AND qe.group_id=p_group AND (sf.status<>'approved' OR sf.available_quantity=0);
 SELECT count(*) INTO n FROM queue_entries WHERE group_id=p_group;
 FOR tries IN 1..(n*4+1) LOOP
  SELECT * INTO e FROM queue_entries WHERE group_id=p_group ORDER BY position LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF e.skips_remaining>0 THEN
   UPDATE queue_entries SET position=queue_position(p_group),skips_remaining=skips_remaining-1 WHERE offer_id=e.offer_id;
   INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',p_group,e.offer_id,'skipped');
  ELSE
   UPDATE queue_groups SET active_offer_id=e.offer_id,active_since=p_now WHERE group_id=p_group;
   INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',p_group,e.offer_id,'activated');
   RETURN e.offer_id;
  END IF;
 END LOOP;
 RAISE EXCEPTION 'Queue failed to settle';
END; $$;
CREATE FUNCTION refresh_all_queues() RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE g RECORD;
BEGIN FOR g IN SELECT group_id FROM queue_groups ORDER BY group_id LOOP PERFORM advance_queue(g.group_id); END LOOP; END; $$;

CREATE FUNCTION review_offer(p_admin BIGINT,p_offer BIGINT,p_decision TEXT,p_reason TEXT DEFAULT '') RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers; v_group BIGINT;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer;
 IF NOT FOUND THEN RAISE EXCEPTION 'Offer missing'; END IF;
 v_group:=ensure_group(f.variant_id,f.condition);
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer FOR UPDATE;
 IF f.status<>'pending' THEN RAISE EXCEPTION 'Offer is no longer pending'; END IF;
 IF p_decision NOT IN ('approve','reject') OR p_decision IS NULL THEN RAISE EXCEPTION 'Decision must be approve or reject'; END IF;
 IF p_decision='reject' AND coalesce(length(trim(p_reason)),0)=0 THEN RAISE EXCEPTION 'Rejection needs a reason'; END IF;
 UPDATE seller_offers SET review_decision=p_decision,reviewed_by=p_admin,review_reason=p_reason,reviewed_at=now() WHERE offer_id=p_offer;
 UPDATE seller_offers SET status=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END WHERE offer_id=p_offer;
 IF p_decision='approve' THEN PERFORM queue_add(v_group,p_offer); PERFORM advance_queue(v_group); END IF;
 INSERT INTO notifications(user_id,offer_id,type,message) VALUES(f.seller_id,p_offer,'offer_review','Offer review: '||p_decision||'. '||p_reason);
 PERFORM log_action(p_admin,'offer_'||p_decision,'seller_offer',p_offer);
END; $$;
CREATE FUNCTION withdraw_offer(p_seller BIGINT,p_offer BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers; v_group BIGINT;
BEGIN
 PERFORM require_role(p_seller,'seller');
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer AND seller_id=p_seller;
 IF NOT FOUND THEN RAISE EXCEPTION 'Own offer not found'; END IF;
 v_group:=ensure_group(f.variant_id,f.condition);
 PERFORM 1 FROM seller_offers WHERE offer_id=p_offer FOR UPDATE;
 UPDATE seller_offers SET status='withdrawn' WHERE offer_id=p_offer;
 DELETE FROM queue_entries WHERE offer_id=p_offer;
 UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE group_id=v_group AND active_offer_id=p_offer;
 INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',v_group,p_offer,'withdrawn');
 PERFORM advance_queue(v_group);
 PERFORM log_action(p_seller,'offer_withdrawn','seller_offer',p_offer);
END; $$;

CREATE FUNCTION discount_for(p_coupon BIGINT,p_buyer BIGINT,p_subtotal NUMERIC) RETURNS NUMERIC
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE c coupons; d NUMERIC;
BEGIN
 IF p_coupon IS NULL THEN RETURN 0; END IF;
 SELECT * INTO c FROM coupons WHERE coupon_id=p_coupon FOR UPDATE;
 IF NOT FOUND OR NOT c.active OR now()<c.starts_at OR now()>=c.expires_at OR p_subtotal<c.min_spend THEN RAISE EXCEPTION 'Coupon unavailable'; END IF;
 IF EXISTS(SELECT 1 FROM coupon_redemptions WHERE coupon_id=p_coupon AND user_id=p_buyer) THEN RAISE EXCEPTION 'Coupon already used by this buyer'; END IF;
 IF (SELECT count(*) FROM coupon_redemptions WHERE coupon_id=p_coupon)>=c.usage_limit THEN RAISE EXCEPTION 'Coupon quota reached'; END IF;
 d:=CASE WHEN c.discount_type='fixed' THEN c.value ELSE round(p_subtotal*c.value/100,2) END;
 RETURN least(d,p_subtotal);
END; $$;

CREATE FUNCTION checkout(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT,p_address BIGINT,p_coupon BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE g BIGINT; v_offer BIGINT; f seller_offers; a addresses; cfg platform_settings; v_fee NUMERIC; v_discount NUMERIC; v_order BIGINT; v_product RECORD;
BEGIN
 PERFORM require_role(p_buyer,'buyer');
 SELECT * INTO a FROM addresses WHERE address_id=p_address AND user_id=p_buyer AND NOT archived;
 IF NOT FOUND THEN RAISE EXCEPTION 'Own active shipping address required'; END IF;
 g:=ensure_group(p_variant,p_condition); v_offer:=advance_queue(g);
 IF v_offer IS NULL THEN RAISE EXCEPTION 'No approved stock available'; END IF;
 SELECT * INTO f FROM seller_offers WHERE offer_id=v_offer;
 IF f.seller_id=p_buyer THEN RAISE EXCEPTION 'Cannot buy own item'; END IF;
 SELECT * INTO cfg FROM platform_settings WHERE settings_id=1;
 v_fee:=round(f.asking_price*cfg.platform_fee_percent/100,2);
 v_discount:=discount_for(p_coupon,p_buyer,f.asking_price+v_fee);
 SELECT p.name,v.size,v.color INTO v_product FROM product_variants v JOIN products p USING(product_id)
 WHERE v.variant_id=p_variant AND p.active AND v.active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Catalog variant unavailable'; END IF;
 INSERT INTO orders(buyer_id,item_subtotal,platform_fee,discount,shipping_fee,total,coupon_id)
 VALUES(p_buyer,f.asking_price,v_fee,v_discount,cfg.shipping_fee,f.asking_price+v_fee-v_discount+cfg.shipping_fee,p_coupon) RETURNING order_id INTO v_order;
 UPDATE orders SET shipping_recipient_name=a.recipient_name,shipping_phone=a.phone,
 shipping_address_line=a.address_line,shipping_district=a.district,shipping_province=a.province,shipping_postal_code=a.postal_code WHERE order_id=v_order;
 INSERT INTO order_items(order_id,offer_id,seller_id,variant_id,product_name_snapshot,size_snapshot,color_snapshot,condition_snapshot,defects_snapshot,unit_price)
 VALUES(v_order,v_offer,f.seller_id,p_variant,v_product.name,v_product.size,v_product.color,f.condition,f.defects,f.asking_price);
 PERFORM log_order(v_order,'awaiting_payment',p_buyer,'One-item order; stock not reserved until payment verification.');
 RETURN v_order;
END; $$;

CREATE FUNCTION confirm_payment(p_admin BIGINT,p_order BIGINT,p_reference TEXT,p_method TEXT DEFAULT 'demo') RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE o orders; i order_items; f seller_offers; g BIGINT; head BIGINT; paid payments; v_payment BIGINT; d NUMERIC;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO i FROM order_items WHERE order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order item missing'; END IF;
 g:=ensure_group(i.variant_id,i.condition_snapshot);
 SELECT * INTO o FROM orders WHERE order_id=p_order FOR UPDATE;
 SELECT * INTO paid FROM payments WHERE order_id=p_order AND status='captured';
 IF FOUND THEN
  IF paid.reference=p_reference THEN RETURN paid.payment_id; ELSE RAISE EXCEPTION 'Order already paid'; END IF;
 END IF;
 IF o.status<>'awaiting_payment' THEN RAISE EXCEPTION 'Order is not awaiting payment'; END IF;
 head:=advance_queue(g);
 IF head IS DISTINCT FROM i.offer_id THEN RAISE EXCEPTION 'Queue changed; create a new order before payment'; END IF;
 SELECT * INTO f FROM seller_offers WHERE offer_id=i.offer_id FOR UPDATE;
 IF f.status<>'approved' OR f.available_quantity<1 OR f.asking_price<>i.unit_price THEN RAISE EXCEPTION 'Offer unavailable or price changed'; END IF;
 d:=discount_for(o.coupon_id,o.buyer_id,o.item_subtotal+o.platform_fee);
 IF d<>o.discount THEN RAISE EXCEPTION 'Coupon changed; create a new order'; END IF;
 INSERT INTO payments(order_id,amount,method,status,reference,verified_by,paid_at)
 VALUES(p_order,o.total,p_method,'captured',p_reference,p_admin,now()) RETURNING payment_id INTO v_payment;
 IF o.coupon_id IS NOT NULL THEN INSERT INTO coupon_redemptions(coupon_id,user_id,order_id,discount_applied)
 VALUES(o.coupon_id,o.buyer_id,p_order,o.discount); END IF;
 UPDATE seller_offers SET available_quantity=available_quantity-1 WHERE offer_id=i.offer_id RETURNING * INTO f;
 UPDATE orders SET status='processing' WHERE order_id=p_order;
 UPDATE order_items SET fulfillment_status='awaiting_seller_shipment' WHERE order_id=p_order;
 UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE group_id=g;
 IF f.available_quantity>0 THEN PERFORM queue_add(g,f.offer_id,'sold');
 ELSE DELETE FROM queue_entries WHERE offer_id=f.offer_id; INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',g,f.offer_id,'sold'); END IF;
 PERFORM advance_queue(g);
 PERFORM log_order(p_order,'awaiting_seller_shipment',p_admin,'Payment recorded. Stock reserved; queue rotated.');
 INSERT INTO notifications(user_id,order_id,type,message) VALUES(i.seller_id,p_order,'sale_paid','An item sold. Send it to the QC hub.');
 RETURN v_payment;
END; $$;

CREATE FUNCTION shipment_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items;
BEGIN
 SELECT * INTO i FROM order_items WHERE order_item_id=NEW.order_item_id FOR UPDATE;
 IF NEW.leg='seller_to_hub' THEN
  PERFORM require_role(NEW.created_by,'seller');
  IF NEW.created_by<>i.seller_id OR i.fulfillment_status<>'awaiting_seller_shipment' THEN RAISE EXCEPTION 'Only owning seller can ship this item to hub'; END IF;
 ELSIF NEW.leg='hub_to_buyer' THEN
  PERFORM require_role(NEW.created_by,'admin');
  IF i.fulfillment_status<>'ready_to_ship' OR NOT EXISTS(SELECT 1 FROM qc_inspections WHERE order_item_id=i.order_item_id AND result='pass')
  THEN RAISE EXCEPTION 'Saved QC PASS required before buyer dispatch'; END IF;
 ELSE
  PERFORM require_role(NEW.created_by,'qc');
  IF i.fulfillment_status<>'qc_failed' THEN RAISE EXCEPTION 'Only QC-failed items can be returned'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER check_shipment BEFORE INSERT ON shipments FOR EACH ROW EXECUTE FUNCTION shipment_guard();
CREATE FUNCTION create_shipment(p_actor BIGINT,p_order BIGINT,p_leg TEXT,p_carrier TEXT,p_tracking TEXT,p_cost NUMERIC DEFAULT 0) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items; v_ship BIGINT; next_state TEXT; who TEXT;
BEGIN
 SELECT * INTO i FROM order_items WHERE order_id=p_order FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order missing'; END IF;
 next_state:=CASE p_leg WHEN 'seller_to_hub' THEN 'inbound' WHEN 'hub_to_buyer' THEN 'outbound' WHEN 'hub_to_seller' THEN 'return_in_transit' END;
 IF next_state IS NULL THEN RAISE EXCEPTION 'Unknown shipping leg'; END IF;
 who:=CASE WHEN p_leg='hub_to_buyer' THEN 'buyer' ELSE 'seller' END;
 INSERT INTO shipments(order_item_id,leg,carrier,tracking_number,shipping_cost,payer,created_by)
 VALUES(i.order_item_id,p_leg,p_carrier,p_tracking,p_cost,who,p_actor) RETURNING shipment_id INTO v_ship;
 UPDATE order_items SET fulfillment_status=next_state WHERE order_item_id=i.order_item_id;
 INSERT INTO activity_logs(event_source,shipment_id,status,actor_id) VALUES('shipment',v_ship,'in_transit',p_actor);
 IF p_leg='hub_to_seller' THEN INSERT INTO seller_charges(seller_id,shipment_id,amount,recorded_by) VALUES(i.seller_id,v_ship,p_cost,p_actor); END IF;
 PERFORM log_order(p_order,next_state,p_actor,p_carrier||' / '||p_tracking);
 RETURN v_ship;
END; $$;
CREATE FUNCTION receive_at_hub(p_qc BIGINT,p_order BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items; v_ship BIGINT;
BEGIN
 PERFORM require_role(p_qc,'qc');
 SELECT * INTO i FROM order_items WHERE order_id=p_order FOR UPDATE;
 IF NOT FOUND OR i.fulfillment_status<>'inbound' THEN RAISE EXCEPTION 'Item is not inbound'; END IF;
 UPDATE shipments SET status='delivered',delivered_at=now() WHERE order_item_id=i.order_item_id AND leg='seller_to_hub' RETURNING shipment_id INTO v_ship;
 UPDATE order_items SET fulfillment_status='awaiting_qc' WHERE order_item_id=i.order_item_id;
 INSERT INTO activity_logs(event_source,shipment_id,status,actor_id,location) VALUES('shipment',v_ship,'delivered',p_qc,'QC hub');
 PERFORM log_order(p_order,'awaiting_qc',p_qc);
END; $$;

CREATE FUNCTION record_qc(p_qc BIGINT,p_order BIGINT,p_result TEXT,p_score INTEGER,p_notes TEXT,p_evidence TEXT[]) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items; o orders; paid payments; v_qc BIGINT; ref TEXT; next_state TEXT;
BEGIN
 PERFORM require_role(p_qc,'qc');
 SELECT * INTO o FROM orders WHERE order_id=p_order FOR UPDATE;
 SELECT * INTO i FROM order_items WHERE order_id=p_order FOR UPDATE;
 IF NOT FOUND OR i.fulfillment_status<>'awaiting_qc' THEN RAISE EXCEPTION 'Item is not awaiting QC'; END IF;
 IF coalesce(array_length(p_evidence,1),0)=0 THEN RAISE EXCEPTION 'QC evidence required'; END IF;
 INSERT INTO qc_inspections(order_item_id,inspector_id,result,seller_score,notes)
 VALUES(i.order_item_id,p_qc,p_result,p_score,p_notes) RETURNING inspection_id INTO v_qc;
 FOREACH ref IN ARRAY p_evidence LOOP
  IF ref IS NULL OR length(trim(ref))=0 THEN RAISE EXCEPTION 'Empty evidence reference'; END IF;
  INSERT INTO assets(inspection_id,file_reference) VALUES(v_qc,ref);
 END LOOP;
 next_state:=CASE WHEN p_result='pass' THEN 'ready_to_ship' ELSE 'qc_failed' END;
 UPDATE order_items SET fulfillment_status=next_state WHERE order_item_id=i.order_item_id;
 IF p_result='fail' THEN
  UPDATE orders SET status='cancelled' WHERE order_id=p_order;
  SELECT * INTO paid FROM payments WHERE order_id=p_order AND status='captured';
  IF NOT FOUND THEN RAISE EXCEPTION 'Captured payment missing'; END IF;
  INSERT INTO refunds(order_id,payment_id,amount,reason) VALUES(p_order,paid.payment_id,paid.amount,'QC failed: full buyer payment including initial shipping');
 END IF;
 PERFORM log_order(p_order,next_state,p_qc,p_notes);
 INSERT INTO notifications(user_id,order_id,type,message) VALUES
 (i.seller_id,p_order,'qc_result','QC result: '||p_result),(o.buyer_id,p_order,'qc_result','QC result: '||p_result);
 RETURN v_qc;
END; $$;

CREATE FUNCTION confirm_receipt(p_buyer BIGINT,p_order BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE o orders; i order_items; v_ship BIGINT;
BEGIN
 PERFORM require_role(p_buyer,'buyer');
 SELECT * INTO o FROM orders WHERE order_id=p_order AND buyer_id=p_buyer FOR UPDATE;
 IF NOT FOUND OR o.status<>'processing' THEN RAISE EXCEPTION 'Own processing order required'; END IF;
 SELECT * INTO i FROM order_items WHERE order_id=p_order FOR UPDATE;
 IF i.fulfillment_status<>'outbound' THEN RAISE EXCEPTION 'Item is not shipped to buyer'; END IF;
 UPDATE shipments SET status='delivered',delivered_at=now() WHERE order_item_id=i.order_item_id AND leg='hub_to_buyer' RETURNING shipment_id INTO v_ship;
 UPDATE order_items SET fulfillment_status='completed' WHERE order_id=p_order;
 UPDATE orders SET status='completed',completed_at=now() WHERE order_id=p_order;
 INSERT INTO activity_logs(event_source,shipment_id,status,actor_id) VALUES('shipment',v_ship,'delivered',p_buyer);
 PERFORM log_order(p_order,'completed',p_buyer,'Buyer confirmed receipt and item check.');
END; $$;
CREATE FUNCTION confirm_seller_return(p_qc BIGINT,p_order BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items; v_ship BIGINT;
BEGIN
 PERFORM require_role(p_qc,'qc');
 SELECT * INTO i FROM order_items WHERE order_id=p_order FOR UPDATE;
 IF NOT FOUND OR i.fulfillment_status<>'return_in_transit' THEN RAISE EXCEPTION 'Return is not in transit'; END IF;
 UPDATE shipments SET status='delivered',delivered_at=now() WHERE order_item_id=i.order_item_id AND leg='hub_to_seller' RETURNING shipment_id INTO v_ship;
 UPDATE order_items SET fulfillment_status='returned' WHERE order_id=p_order;
 INSERT INTO activity_logs(event_source,shipment_id,status,actor_id) VALUES('shipment',v_ship,'delivered',p_qc);
 PERFORM log_order(p_order,'returned',p_qc);
END; $$;

CREATE FUNCTION approve_refund(p_admin BIGINT,p_refund BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE r refunds; paid payments;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO r FROM refunds WHERE refund_id=p_refund FOR UPDATE;
 IF NOT FOUND OR r.status<>'requested' THEN RAISE EXCEPTION 'Requested refund required'; END IF;
 SELECT * INTO paid FROM payments WHERE payment_id=r.payment_id;
 IF paid.status<>'captured' OR r.amount<>paid.amount OR r.order_id<>paid.order_id THEN RAISE EXCEPTION 'Full original payment must be refunded'; END IF;
 UPDATE refunds SET status='approved',approved_by=p_admin,approved_at=now() WHERE refund_id=p_refund;
 PERFORM log_action(p_admin,'refund_approved','refund',p_refund);
END; $$;
CREATE FUNCTION record_refund_paid(p_admin BIGINT,p_refund BIGINT,p_reference TEXT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE r refunds;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO r FROM refunds WHERE refund_id=p_refund FOR UPDATE;
 IF NOT FOUND OR r.status<>'approved' THEN RAISE EXCEPTION 'Approved refund required'; END IF;
 IF length(trim(p_reference))=0 THEN RAISE EXCEPTION 'Transfer reference required'; END IF;
 UPDATE refunds SET status='paid',paid_by=p_admin,paid_at=now(),transfer_reference=p_reference WHERE refund_id=p_refund;
 PERFORM log_action(p_admin,'refund_payment_recorded','refund',p_refund);
END; $$;

CREATE FUNCTION create_payout(p_admin BIGINT,p_seller BIGINT,p_bank BIGINT) RETURNS BIGINT LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE b seller_bank_accounts; v_payout BIGINT; v_total NUMERIC; ids BIGINT[];
BEGIN
 PERFORM require_role(p_admin,'admin');
 -- Serialize settlement batches for the same seller.
 PERFORM 1 FROM users WHERE user_id=p_seller AND seller_status IS NOT NULL FOR UPDATE;
 SELECT * INTO b FROM seller_bank_accounts WHERE bank_account_id=p_bank AND seller_id=p_seller AND is_verified AND NOT archived;
 IF NOT FOUND THEN RAISE EXCEPTION 'Verified bank account owned by seller required'; END IF;
 SELECT array_agg(i.order_item_id),sum(i.unit_price) INTO ids,v_total FROM order_items i JOIN orders o USING(order_id)
 WHERE i.seller_id=p_seller AND o.status='completed' AND i.fulfillment_status='completed'
 AND EXISTS(SELECT 1 FROM payments p WHERE p.order_id=o.order_id AND p.status='captured')
 AND NOT EXISTS(SELECT 1 FROM refunds r WHERE r.order_id=o.order_id)
 AND NOT EXISTS(SELECT 1 FROM payout_items pi WHERE pi.order_item_id=i.order_item_id);
 IF ids IS NULL THEN RAISE EXCEPTION 'No completed unpaid sales eligible for payout'; END IF;
 INSERT INTO payouts(seller_id,bank_account_id,bank_name_snapshot,account_holder_snapshot,account_number_snapshot,amount,created_by)
 VALUES(p_seller,p_bank,b.bank_name,b.account_holder,b.account_number,v_total,p_admin) RETURNING payout_id INTO v_payout;
 INSERT INTO payout_items SELECT v_payout,i.order_item_id,i.unit_price FROM order_items i WHERE i.order_item_id=ANY(ids);
 PERFORM log_action(p_admin,'payout_created','payout',v_payout);
 RETURN v_payout;
END; $$;
CREATE FUNCTION approve_payout(p_admin BIGINT,p_payout BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE n INTEGER;
BEGIN
 PERFORM require_role(p_admin,'admin');
 PERFORM 1 FROM payouts WHERE payout_id=p_payout FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM payouts WHERE payout_id=p_payout AND status='pending') THEN RAISE EXCEPTION 'Pending payout required'; END IF;
 IF EXISTS(SELECT 1 FROM payout_items pi JOIN order_items i USING(order_item_id) JOIN orders o USING(order_id)
 WHERE pi.payout_id=p_payout AND (o.status<>'completed' OR EXISTS(SELECT 1 FROM refunds r WHERE r.order_id=o.order_id))) THEN RAISE EXCEPTION 'Payout contains ineligible sale'; END IF;
 IF (SELECT amount FROM payouts WHERE payout_id=p_payout)<>(SELECT sum(amount) FROM payout_items WHERE payout_id=p_payout) THEN RAISE EXCEPTION 'Payout total mismatch'; END IF;
 UPDATE payouts SET status='approved',approved_by=p_admin,approved_at=now() WHERE payout_id=p_payout;
 PERFORM log_action(p_admin,'payout_approved','payout',p_payout);
END; $$;
CREATE FUNCTION record_payout_paid(p_admin BIGINT,p_payout BIGINT,p_reference TEXT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(p_admin,'admin');
 PERFORM 1 FROM payouts WHERE payout_id=p_payout AND status='approved' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approved payout required'; END IF;
 IF length(trim(p_reference))=0 THEN RAISE EXCEPTION 'Transfer reference required'; END IF;
 UPDATE payouts SET status='paid',paid_by=p_admin,paid_at=now(),transfer_reference=p_reference WHERE payout_id=p_payout;
 PERFORM log_action(p_admin,'seller_payment_recorded','payout',p_payout);
END; $$;

-- Functions check business roles using p_actor. Backend must get actor from a
-- trusted authenticated session. These parameters are NOT database login auth.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA owl FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA owl FROM PUBLIC;


-- 003_guards_views.sql

SET search_path TO owl, public;

CREATE FUNCTION protect_order_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.shipping_address_line IS NOT NULL AND
 ROW(NEW.shipping_recipient_name,NEW.shipping_phone,NEW.shipping_address_line,NEW.shipping_district,NEW.shipping_province,NEW.shipping_postal_code)
 IS DISTINCT FROM ROW(OLD.shipping_recipient_name,OLD.shipping_phone,OLD.shipping_address_line,OLD.shipping_district,OLD.shipping_province,OLD.shipping_postal_code)
 THEN RAISE EXCEPTION 'Historical shipping address is immutable'; END IF;
 IF ROW(NEW.buyer_id,NEW.item_subtotal,NEW.platform_fee,NEW.discount,NEW.shipping_fee,NEW.total,NEW.coupon_id)
 IS DISTINCT FROM ROW(OLD.buyer_id,OLD.item_subtotal,OLD.platform_fee,OLD.discount,OLD.shipping_fee,OLD.total,OLD.coupon_id)
 THEN RAISE EXCEPTION 'Order financial snapshot is immutable'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER order_snapshot BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION protect_order_snapshot();
CREATE FUNCTION protect_item_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF ROW(NEW.order_id,NEW.offer_id,NEW.seller_id,NEW.variant_id,NEW.unit_price,NEW.quantity,NEW.product_name_snapshot,NEW.size_snapshot,NEW.color_snapshot,NEW.condition_snapshot,NEW.defects_snapshot)
 IS DISTINCT FROM ROW(OLD.order_id,OLD.offer_id,OLD.seller_id,OLD.variant_id,OLD.unit_price,OLD.quantity,OLD.product_name_snapshot,OLD.size_snapshot,OLD.color_snapshot,OLD.condition_snapshot,OLD.defects_snapshot)
 THEN RAISE EXCEPTION 'Order item snapshot is immutable'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER item_snapshot BEFORE UPDATE ON order_items FOR EACH ROW EXECUTE FUNCTION protect_item_snapshot();

CREATE FUNCTION check_refund_record() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE p payments;
BEGIN
 SELECT * INTO p FROM payments WHERE payment_id=NEW.payment_id;
 IF p.status<>'captured' OR p.order_id<>NEW.order_id OR p.amount<>NEW.amount THEN RAISE EXCEPTION 'Refund must equal the full original captured payment'; END IF;
 IF NOT EXISTS(SELECT 1 FROM orders WHERE order_id=NEW.order_id AND status='cancelled') THEN RAISE EXCEPTION 'Refund requires a cancelled order'; END IF;
 IF TG_OP='UPDATE' THEN
  IF ROW(NEW.order_id,NEW.payment_id,NEW.amount,NEW.reason) IS DISTINCT FROM ROW(OLD.order_id,OLD.payment_id,OLD.amount,OLD.reason)
  THEN RAISE EXCEPTION 'Refund financial details cannot change'; END IF;
  IF OLD.status='paid' OR (OLD.status='approved' AND NEW.status<>'paid') OR (OLD.status='requested' AND NEW.status<>'approved')
  THEN RAISE EXCEPTION 'Invalid refund transition'; END IF;
 END IF;
 IF NEW.approved_by IS NOT NULL THEN PERFORM require_role(NEW.approved_by,'admin'); END IF;
 IF NEW.paid_by IS NOT NULL THEN PERFORM require_role(NEW.paid_by,'admin'); END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER refund_guard BEFORE INSERT OR UPDATE ON refunds FOR EACH ROW EXECUTE FUNCTION check_refund_record();
CREATE FUNCTION check_payout_record() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(NEW.created_by,'admin');
 IF NOT EXISTS(SELECT 1 FROM seller_bank_accounts WHERE bank_account_id=NEW.bank_account_id AND seller_id=NEW.seller_id AND is_verified AND NOT archived)
 THEN RAISE EXCEPTION 'Payout bank account does not belong to seller or is not verified'; END IF;
 IF TG_OP='UPDATE' THEN
  IF ROW(NEW.seller_id,NEW.bank_account_id,NEW.amount,NEW.bank_name_snapshot,NEW.account_holder_snapshot,NEW.account_number_snapshot)
   IS DISTINCT FROM ROW(OLD.seller_id,OLD.bank_account_id,OLD.amount,OLD.bank_name_snapshot,OLD.account_holder_snapshot,OLD.account_number_snapshot)
  THEN RAISE EXCEPTION 'Payout financial details cannot change'; END IF;
  IF OLD.status='paid' OR (OLD.status='approved' AND NEW.status<>'paid') OR (OLD.status='pending' AND NEW.status<>'approved')
  THEN RAISE EXCEPTION 'Invalid payout transition'; END IF;
 END IF;
 IF NEW.approved_by IS NOT NULL THEN PERFORM require_role(NEW.approved_by,'admin'); END IF;
 IF NEW.paid_by IS NOT NULL THEN PERFORM require_role(NEW.paid_by,'admin'); END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER payout_guard BEFORE INSERT OR UPDATE ON payouts FOR EACH ROW EXECUTE FUNCTION check_payout_record();
CREATE FUNCTION check_payout_item() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE i order_items; p payouts;
BEGIN
 SELECT * INTO i FROM order_items WHERE order_item_id=NEW.order_item_id;
 SELECT * INTO p FROM payouts WHERE payout_id=NEW.payout_id;
 IF i.seller_id<>p.seller_id OR i.unit_price<>NEW.amount OR i.fulfillment_status<>'completed'
 OR NOT EXISTS(SELECT 1 FROM orders WHERE order_id=i.order_id AND status='completed')
 OR EXISTS(SELECT 1 FROM refunds WHERE order_id=i.order_id)
 OR NOT EXISTS(SELECT 1 FROM payments WHERE order_id=i.order_id AND status='captured')
 THEN RAISE EXCEPTION 'Only completed, paid, non-refunded sales for this seller can be settled'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER payout_item_guard BEFORE INSERT ON payout_items FOR EACH ROW EXECUTE FUNCTION check_payout_item();
CREATE TRIGGER immutable_payout_items BEFORE UPDATE OR DELETE ON payout_items FOR EACH ROW EXECUTE FUNCTION immutable_record();

CREATE FUNCTION check_qc_actor() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(NEW.inspector_id,'qc');
 IF NOT EXISTS(SELECT 1 FROM order_items WHERE order_item_id=NEW.order_item_id AND fulfillment_status='awaiting_qc')
 THEN RAISE EXCEPTION 'Inspection must be for an awaiting-QC item'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER qc_actor_guard BEFORE INSERT ON qc_inspections FOR EACH ROW EXECUTE FUNCTION check_qc_actor();
CREATE FUNCTION qc_needs_evidence() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM assets WHERE inspection_id=NEW.inspection_id) THEN RAISE EXCEPTION 'Final QC needs at least one evidence row'; END IF;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER final_qc_evidence AFTER INSERT ON qc_inspections DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION qc_needs_evidence();

CREATE FUNCTION payment_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF TG_OP='UPDATE' AND OLD.status='captured' THEN RAISE EXCEPTION 'Captured payment is immutable'; END IF;
 IF NEW.status='captured' THEN
  PERFORM require_role(NEW.verified_by,'admin');
  IF NOT EXISTS(SELECT 1 FROM orders WHERE order_id=NEW.order_id AND total=NEW.amount AND status='awaiting_payment')
  THEN RAISE EXCEPTION 'Captured payment must match the awaiting-payment order total'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER captured_payment_guard BEFORE INSERT OR UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION payment_guard();
CREATE FUNCTION payout_item_snapshot_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers; o orders;
BEGIN
 SELECT * INTO f FROM seller_offers WHERE offer_id=NEW.offer_id;
 SELECT * INTO o FROM orders WHERE order_id=NEW.order_id;
 IF f.seller_id<>NEW.seller_id OR f.variant_id<>NEW.variant_id OR f.asking_price<>NEW.unit_price
 OR f.condition<>NEW.condition_snapshot OR o.buyer_id=NEW.seller_id
 THEN RAISE EXCEPTION 'Item must match its offer; buyer cannot be seller'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER item_source_guard BEFORE INSERT ON order_items FOR EACH ROW EXECUTE FUNCTION payout_item_snapshot_guard();
CREATE FUNCTION admin_review_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN PERFORM require_role(NEW.admin_id,'admin'); RETURN NEW; END; $$;
CREATE FUNCTION catalog_owner_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN PERFORM require_role(NEW.created_by,'admin'); RETURN NEW; END; $$;
CREATE TRIGGER catalog_actor_guard BEFORE INSERT ON products FOR EACH ROW EXECUTE FUNCTION catalog_owner_guard();

CREATE FUNCTION check_queue_entry() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM seller_offers f JOIN queue_groups g ON g.group_id=NEW.group_id
 WHERE f.offer_id=NEW.offer_id AND f.variant_id=g.variant_id AND f.condition=g.condition AND f.status='approved' AND f.available_quantity>0)
 THEN RAISE EXCEPTION 'Queue entry must match approved in-stock offer and queue group'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER queue_entry_guard BEFORE INSERT OR UPDATE ON queue_entries FOR EACH ROW EXECUTE FUNCTION check_queue_entry();

CREATE FUNCTION set_cart_item(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(p_buyer,'buyer');
 INSERT INTO carts(user_id,variant_id,condition,added_at) VALUES(p_buyer,p_variant,p_condition,now())
 ON CONFLICT(user_id) DO UPDATE SET variant_id=excluded.variant_id,condition=excluded.condition,added_at=now();
END; $$;
CREATE FUNCTION verify_seller(p_admin BIGINT,p_verification BIGINT,p_approve BOOLEAN,p_note TEXT) RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(p_admin,'admin');
 PERFORM 1 FROM seller_verifications WHERE verification_id=p_verification AND status='pending' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pending verification required'; END IF;
 UPDATE seller_verifications SET status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
 reviewer_id=p_admin,review_note=p_note,reviewed_at=now() WHERE verification_id=p_verification;
 PERFORM log_action(p_admin,'seller_verification_reviewed','seller_verification',p_verification);
END; $$;

CREATE FUNCTION request_cancellation(p_buyer BIGINT,p_order BIGINT,p_reason TEXT) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE v_id BIGINT;
BEGIN
 PERFORM require_role(p_buyer,'buyer');
 IF NOT EXISTS(SELECT 1 FROM orders o JOIN order_items i USING(order_id) WHERE o.order_id=p_order AND o.buyer_id=p_buyer
 AND i.fulfillment_status IN ('awaiting_payment','awaiting_seller_shipment'))
 THEN RAISE EXCEPTION 'Cancellation request allowed only before seller handover in this prototype'; END IF;
 INSERT INTO cancellation_requests(order_id,buyer_id,reason) VALUES(p_order,p_buyer,p_reason) RETURNING request_id INTO v_id;
 RETURN v_id;
END; $$;
CREATE FUNCTION review_cancellation(p_admin BIGINT,p_request BIGINT,p_approve BOOLEAN) RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE r cancellation_requests; o orders; i order_items; f seller_offers; g BIGINT; paid payments;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO r FROM cancellation_requests WHERE request_id=p_request;
 IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
 SELECT * INTO i FROM order_items WHERE order_id=r.order_id;
 g:=ensure_group(i.variant_id,i.condition_snapshot);
 SELECT * INTO r FROM cancellation_requests WHERE request_id=p_request FOR UPDATE;
 SELECT * INTO o FROM orders WHERE order_id=r.order_id FOR UPDATE;
 SELECT * INTO i FROM order_items WHERE order_id=r.order_id FOR UPDATE;
 IF r.status<>'pending' THEN RAISE EXCEPTION 'Request already reviewed'; END IF;
 IF p_approve AND i.fulfillment_status NOT IN ('awaiting_payment','awaiting_seller_shipment') THEN RAISE EXCEPTION 'Seller already handed over item'; END IF;
 UPDATE cancellation_requests SET status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,reviewed_by=p_admin,reviewed_at=now() WHERE request_id=p_request;
 IF NOT p_approve THEN RETURN; END IF;
 SELECT * INTO paid FROM payments WHERE order_id=r.order_id AND status='captured';
 IF FOUND THEN
  UPDATE seller_offers SET available_quantity=available_quantity+1 WHERE offer_id=i.offer_id RETURNING * INTO f;
  IF f.status='approved' THEN
   IF NOT EXISTS(SELECT 1 FROM queue_entries WHERE offer_id=f.offer_id) THEN PERFORM queue_add(g,f.offer_id,'restored'); END IF;
   PERFORM advance_queue(g);
  END IF;
 END IF;
 UPDATE orders SET status='cancelled' WHERE order_id=o.order_id;
 UPDATE order_items SET fulfillment_status='cancelled' WHERE order_id=o.order_id;
 IF paid.payment_id IS NOT NULL THEN
  INSERT INTO refunds(order_id,payment_id,amount,reason) VALUES(o.order_id,paid.payment_id,paid.amount,'Admin-approved cancellation before seller handover');
 END IF;
 PERFORM log_order(o.order_id,'cancelled',p_admin,'Stock restored only if payment had reserved one unit.');
END; $$;
CREATE FUNCTION record_return_shipping_paid(p_admin BIGINT,p_charge BIGINT,p_reference TEXT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(p_admin,'admin');
 IF length(trim(p_reference))=0 THEN RAISE EXCEPTION 'Reference required'; END IF;
 UPDATE seller_charges SET status='paid',paid_at=now(),payment_reference=p_reference WHERE charge_id=p_charge AND status='unpaid';
 IF NOT FOUND THEN RAISE EXCEPTION 'Unpaid seller charge required'; END IF;
 PERFORM log_action(p_admin,'return_shipping_paid','seller_charge',p_charge);
END; $$;

-- Public product view intentionally omits seller identity and bank data.
-- Refresh queue timers using refresh_all_queues() in the server's scheduler.
CREATE VIEW public_market AS
SELECT p.product_id,p.name AS product_name,p.brand_name AS brand,c.name AS category,
 v.variant_id,v.size,v.color,g.condition,'Owl Pai Lei'::TEXT AS sold_by,
 round(f.asking_price*(1+cfg.platform_fee_percent/100),2) AS display_price,
 cfg.shipping_fee,f.condition_notes,f.defects,
 g.active_since+interval '24 hours' AS turn_expires_at
FROM queue_groups g JOIN seller_offers f ON f.offer_id=g.active_offer_id
JOIN product_variants v ON v.variant_id=g.variant_id JOIN products p USING(product_id)
JOIN categories c USING(category_id) CROSS JOIN platform_settings cfg
WHERE f.status='approved' AND f.available_quantity>0 AND p.active AND v.active;
CREATE VIEW seller_qc_scores AS
SELECT s.user_id AS seller_id,count(q.inspection_id)::INTEGER AS inspections,
 round(avg(q.seller_score),2) AS average_score,qc_skip_count(s.user_id) AS skipped_opportunities
FROM users s LEFT JOIN order_items i ON i.seller_id=s.user_id LEFT JOIN qc_inspections q USING(order_item_id)
WHERE s.seller_status IS NOT NULL GROUP BY s.user_id;
CREATE VIEW seller_sales AS
SELECT i.seller_id,o.order_id,o.status AS order_status,i.fulfillment_status,i.product_name_snapshot,
 i.size_snapshot,i.color_snapshot,i.condition_snapshot,i.unit_price,q.result AS qc_result,q.seller_score,
 CASE WHEN q.inspection_id IS NULL THEN 'No QC result yet' ELSE q.result END AS qc_display,
 o.created_at,o.completed_at
FROM order_items i JOIN orders o USING(order_id) LEFT JOIN qc_inspections q USING(order_item_id);
CREATE VIEW buyer_orders AS
SELECT o.buyer_id,o.order_id,o.status,i.fulfillment_status,i.product_name_snapshot,i.size_snapshot,
 i.color_snapshot,i.condition_snapshot,'Owl Pai Lei'::TEXT AS sold_by,o.item_subtotal,o.platform_fee,
 o.discount,o.shipping_fee,o.total,o.created_at,o.completed_at
FROM orders o JOIN order_items i USING(order_id);
CREATE VIEW eligible_payouts AS
SELECT i.seller_id,i.order_item_id,i.order_id,i.unit_price AS seller_amount
FROM order_items i JOIN orders o USING(order_id)
WHERE o.status='completed' AND i.fulfillment_status='completed'
AND EXISTS(SELECT 1 FROM payments p WHERE p.order_id=o.order_id AND p.status='captured')
AND NOT EXISTS(SELECT 1 FROM refunds r WHERE r.order_id=o.order_id)
AND NOT EXISTS(SELECT 1 FROM payout_items pi WHERE pi.order_item_id=i.order_item_id);
CREATE VIEW admin_finance_summary AS
SELECT (SELECT coalesce(sum(amount),0) FROM payments WHERE status='captured') AS captured_payments,
 (SELECT coalesce(sum(amount),0) FROM refunds WHERE status='paid') AS recorded_buyer_refunds,
 (SELECT coalesce(sum(amount),0) FROM payouts WHERE status='paid') AS recorded_seller_payouts,
 (SELECT coalesce(sum(amount),0) FROM seller_charges WHERE status='unpaid') AS return_shipping_due;


CREATE TRIGGER immutable_activity BEFORE UPDATE OR DELETE ON activity_logs FOR EACH ROW EXECUTE FUNCTION immutable_record();
CREATE FUNCTION compact_asset_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF OLD.inspection_id IS NOT NULL THEN RAISE EXCEPTION 'QC evidence is immutable'; END IF; IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW; END; $$;
CREATE TRIGGER immutable_evidence BEFORE UPDATE OR DELETE ON assets FOR EACH ROW EXECUTE FUNCTION compact_asset_guard();
CREATE FUNCTION compact_review_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 IF TG_OP='UPDATE' AND OLD.reviewed_by IS NOT NULL AND ROW(NEW.review_decision,NEW.reviewed_by,NEW.review_reason,NEW.reviewed_at) IS DISTINCT FROM ROW(OLD.review_decision,OLD.reviewed_by,OLD.review_reason,OLD.reviewed_at) THEN RAISE EXCEPTION 'Review is immutable'; END IF;
 IF NEW.reviewed_by IS NOT NULL THEN PERFORM require_role(NEW.reviewed_by,'admin'); END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER review_guard BEFORE INSERT OR UPDATE ON seller_offers FOR EACH ROW EXECUTE FUNCTION compact_review_guard();

CREATE FUNCTION compact_address_required() RETURNS trigger LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE o orders;
BEGIN SELECT * INTO o FROM orders WHERE order_id=NEW.order_id;
 IF num_nonnulls(o.shipping_recipient_name,o.shipping_phone,o.shipping_address_line,o.shipping_district,o.shipping_province,o.shipping_postal_code)<>6 THEN RAISE EXCEPTION 'Order requires a complete shipping snapshot'; END IF;
 RETURN NEW;
END; $$;
CREATE CONSTRAINT TRIGGER address_required AFTER INSERT OR UPDATE ON orders DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION compact_address_required();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA owl FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA owl FROM PUBLIC;


-- 004_seed.sql
-- Fictional classroom data only. Password for the five accounts: OwlDemo123!
-- Run once after schema/workflows/views in an empty project database.

SET search_path TO owl, public;
INSERT INTO roles(name) VALUES('buyer'),('seller'),('admin'),('qc');
INSERT INTO users(full_name,email,phone,password_hash) VALUES
 ('Demo Seller One','seller1@owl.test','DEMO-PHONE-1','8d2d02d1a1339aa33410bb512a44d84c:88ec81aeffc0ea1c228f7f938c33f5ef25a5085b24b56f6ba227fd682c506a47cab150e6fb5458c26c46694b6c5f8bd104e303c5da26006fcb19ee318e0ae35c'),
 ('Demo Seller Two','seller2@owl.test','DEMO-PHONE-2','8d2d02d1a1339aa33410bb512a44d84c:88ec81aeffc0ea1c228f7f938c33f5ef25a5085b24b56f6ba227fd682c506a47cab150e6fb5458c26c46694b6c5f8bd104e303c5da26006fcb19ee318e0ae35c'),
 ('Demo Buyer','buyer@owl.test','DEMO-PHONE-3','8d2d02d1a1339aa33410bb512a44d84c:88ec81aeffc0ea1c228f7f938c33f5ef25a5085b24b56f6ba227fd682c506a47cab150e6fb5458c26c46694b6c5f8bd104e303c5da26006fcb19ee318e0ae35c'),
 ('Demo Admin','admin@owl.test',NULL,'8d2d02d1a1339aa33410bb512a44d84c:88ec81aeffc0ea1c228f7f938c33f5ef25a5085b24b56f6ba227fd682c506a47cab150e6fb5458c26c46694b6c5f8bd104e303c5da26006fcb19ee318e0ae35c'),
 ('Demo QC Staff','qc@owl.test',NULL,'8d2d02d1a1339aa33410bb512a44d84c:88ec81aeffc0ea1c228f7f938c33f5ef25a5085b24b56f6ba227fd682c506a47cab150e6fb5458c26c46694b6c5f8bd104e303c5da26006fcb19ee318e0ae35c');
INSERT INTO user_roles(user_id,role_id) VALUES(1,1),(1,2),(2,1),(2,2),(3,1),(4,3),(5,4);
UPDATE users SET seller_display_name=full_name,seller_status='active',seller_since=created_at WHERE user_id IN (1,2);
INSERT INTO seller_bank_accounts(seller_id,bank_name,account_holder,account_number,is_verified) VALUES
 (1,'Fictional Demo Bank','Demo Seller One','DEMO-ACCOUNT-001',true),
 (2,'Fictional Demo Bank','Demo Seller Two','DEMO-ACCOUNT-002',true);
INSERT INTO seller_verifications(seller_id,id_document_reference,bank_document_reference,status,reviewer_id,review_note,reviewed_at) VALUES
 (1,'demo://seller1-id','demo://seller1-bank','approved',4,'Fictional demo documents only',now()),
 (2,'demo://seller2-id','demo://seller2-bank','approved',4,'Fictional demo documents only',now());
INSERT INTO addresses(user_id,recipient_name,phone,address_line,district,province,postal_code,is_default) VALUES
 (3,'Demo Buyer','DEMO-PHONE-3','Sample address for classroom use','Demo District','Bangkok','10000',true),
 (1,'Demo Seller One','DEMO-PHONE-1','Fictional seller address 1','Demo District','Bangkok','10000',true),
 (2,'Demo Seller Two','DEMO-PHONE-2','Fictional seller address 2','Demo District','Bangkok','10000',true);
INSERT INTO categories(name) VALUES('Shoes'),('Clothing'),('Accessories');
INSERT INTO platform_settings(settings_id,platform_fee_percent,shipping_fee,active_turn_hours,note) VALUES(1,10.00,50.00,24,
 'Prototype proposal: platform fee 10% includes listing and QC; shipping example 50 THB. Update before real use.');

DO $$
DECLARE n INTEGER; p_id BIGINT; v_size TEXT; cat BIGINT; brand TEXT; label TEXT; sizes TEXT[];
BEGIN
 FOR n IN 1..100 LOOP
  cat:=((n-1)%3)+1;
  brand:=CASE WHEN n=1 THEN 'Adidas' WHEN n=2 THEN 'Nike' ELSE 'Demo Brand' END;
  label:=CASE WHEN n=1 THEN 'Adidas Campus Demo' WHEN n=2 THEN 'Nike Apparel Demo'
    ELSE 'Sample Catalog Product '||lpad(n::TEXT,3,'0') END;
  INSERT INTO products(category_id,brand_name,name,description,created_by)
  VALUES(cat,brand,label,'Sample catalog. Replace with the actual 100 products selected by Owl.',4) RETURNING product_id INTO p_id;
  INSERT INTO assets(product_id,file_reference) VALUES(p_id,'demo://catalog/'||n);
  sizes:=CASE WHEN cat=1 THEN ARRAY['9','10','11'] WHEN cat=2 THEN ARRAY['S','M','L'] ELSE ARRAY['One size'] END;
  FOREACH v_size IN ARRAY sizes LOOP
   INSERT INTO product_variants(product_id,size,color,sku) VALUES(p_id,v_size,'Standard','DEMO-'||n||'-'||replace(v_size,' ','-'));
  END LOOP;
 END LOOP;
END; $$;
INSERT INTO carts(user_id) VALUES(1),(2),(3);
SELECT set_cart_item(3,3,'new');
INSERT INTO wishlist_items(user_id,product_id) VALUES(3,1),(3,2);
INSERT INTO coupons(code,discount_type,value,min_spend,starts_at,expires_at,usage_limit,created_by) VALUES
 ('OWL50','fixed',50,100,now()-interval '1 day',now()+interval '365 days',20,4),
 ('OWL10','percent',10,100,now()-interval '1 day',now()+interval '365 days',20,4);
SELECT create_offer(1,3,'new',1000,3,'','Unused, demo packaging');
SELECT create_offer(2,3,'new',1200,2,'','Unused, demo packaging');
SELECT create_offer(1,3,'used',700,1,'Small mark on left shoe','Fictional used-item example');
INSERT INTO assets(offer_id,file_reference,caption) VALUES(3,'demo://offer3/mark','Sample defect photo reference, not a real upload');
SELECT review_offer(4,1,'approve','Demo offer approved');
SELECT review_offer(4,2,'approve','Demo offer approved');


COMMIT;
