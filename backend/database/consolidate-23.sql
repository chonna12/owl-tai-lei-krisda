-- Upgrade the 30-table backend-es2 schema in one transaction.
-- Back up the database first. Run together with the matching backend code.
-- Multiple bank accounts or verification records are rejected rather than discarded.
BEGIN;
SET search_path TO owl, public;
LOCK TABLE users,orders,products,seller_bank_accounts,seller_verifications,user_roles,roles,categories,platform_settings,cancellation_requests,payouts,activity_logs IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM seller_bank_accounts GROUP BY seller_id HAVING count(*)>1)
 OR EXISTS(SELECT 1 FROM seller_verifications GROUP BY seller_id HAVING count(*)>1)
 THEN RAISE EXCEPTION 'Multiple seller bank/verification records found. Resolve and export them before consolidation.'; END IF;
 IF EXISTS(SELECT 1 FROM platform_settings WHERE platform_fee_percent<>10 OR shipping_fee<>50 OR active_turn_hours<>24)
 THEN RAISE EXCEPTION 'Custom platform settings found. Update platform_configuration before migration.'; END IF;
END; $$;

-- Drop project workflow functions. Their dependent triggers/views are recreated below.
DO $$
DECLARE f RECORD;
BEGIN
 FOR f IN SELECT p.oid::regprocedure::text AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='owl' AND p.prokind='f'
 LOOP EXECUTE 'DROP FUNCTION IF EXISTS '||f.signature||' CASCADE'; END LOOP;
END; $$;
DROP VIEW IF EXISTS public_market,seller_qc_scores,seller_sales,buyer_orders,eligible_payouts,admin_finance_summary;
ALTER TABLE users ADD COLUMN is_buyer BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN is_seller BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN is_qc BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN bank_name VARCHAR(100);
ALTER TABLE users ADD COLUMN account_holder VARCHAR(100);
ALTER TABLE users ADD COLUMN account_number VARCHAR(50);
ALTER TABLE users ADD COLUMN bank_verified BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN bank_archived BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN id_document_reference TEXT;
ALTER TABLE users ADD COLUMN bank_document_reference TEXT;
ALTER TABLE users ADD COLUMN verification_status VARCHAR(20) CHECK(verification_status IN ('pending','approved','rejected'));
ALTER TABLE users ADD COLUMN verification_reviewer_id BIGINT REFERENCES users;
ALTER TABLE users ADD COLUMN verification_review_note TEXT;
ALTER TABLE users ADD COLUMN verification_submitted_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN verification_reviewed_at TIMESTAMPTZ;
ALTER TABLE users ADD CHECK (NOT bank_verified OR (bank_name IS NOT NULL AND account_holder IS NOT NULL AND account_number IS NOT NULL));
ALTER TABLE users ADD CHECK (verification_status IS NULL OR
    (id_document_reference IS NOT NULL AND bank_document_reference IS NOT NULL AND verification_submitted_at IS NOT NULL
      AND ((verification_status='pending' AND verification_reviewer_id IS NULL AND verification_reviewed_at IS NULL)
        OR (verification_status<>'pending' AND verification_reviewer_id IS NOT NULL AND verification_reviewed_at IS NOT NULL))));
ALTER TABLE orders ADD COLUMN cancellation_reason TEXT;
ALTER TABLE orders ADD COLUMN cancellation_status VARCHAR(20) CHECK(cancellation_status IN ('pending','approved','rejected'));
ALTER TABLE orders ADD COLUMN cancellation_reviewed_by BIGINT REFERENCES users;
ALTER TABLE orders ADD COLUMN cancellation_reviewed_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN cancellation_created_at TIMESTAMPTZ;
ALTER TABLE orders ADD CHECK ((cancellation_status IS NULL AND cancellation_reason IS NULL AND cancellation_created_at IS NULL
      AND cancellation_reviewed_by IS NULL AND cancellation_reviewed_at IS NULL)
    OR (cancellation_status IS NOT NULL AND length(trim(cancellation_reason))>0 AND cancellation_created_at IS NOT NULL
      AND ((cancellation_status='pending' AND cancellation_reviewed_by IS NULL AND cancellation_reviewed_at IS NULL)
        OR (cancellation_status<>'pending' AND cancellation_reviewed_by IS NOT NULL AND cancellation_reviewed_at IS NOT NULL))));

UPDATE users SET is_buyer=false;
UPDATE users u SET
 is_buyer=EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name='buyer'),
 is_seller=EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name='seller'),
 is_admin=EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name='admin'),
 is_qc=EXISTS(SELECT 1 FROM user_roles ur JOIN roles r USING(role_id) WHERE ur.user_id=u.user_id AND r.name='qc');
UPDATE users u SET bank_name=b.bank_name,account_holder=b.account_holder,account_number=b.account_number,
 bank_verified=b.is_verified,bank_archived=b.archived FROM seller_bank_accounts b WHERE b.seller_id=u.user_id;
UPDATE users u SET id_document_reference=v.id_document_reference,bank_document_reference=v.bank_document_reference,
 verification_status=v.status,verification_reviewer_id=v.reviewer_id,verification_review_note=v.review_note,
 verification_submitted_at=v.submitted_at,verification_reviewed_at=v.reviewed_at
 FROM seller_verifications v WHERE v.seller_id=u.user_id;
ALTER TABLE products ADD COLUMN category VARCHAR(100);
UPDATE products p SET category=c.name FROM categories c WHERE c.category_id=p.category_id;
ALTER TABLE products ALTER COLUMN category SET NOT NULL;
ALTER TABLE products ADD CHECK(length(trim(category))>0);
ALTER TABLE products DROP COLUMN category_id;
UPDATE orders o SET cancellation_reason=c.reason,cancellation_status=c.status,
 cancellation_reviewed_by=c.reviewed_by,cancellation_reviewed_at=c.reviewed_at,cancellation_created_at=c.created_at
 FROM cancellation_requests c WHERE c.order_id=o.order_id;
ALTER TABLE payouts DROP CONSTRAINT payouts_bank_account_id_fkey;
UPDATE payouts p SET bank_account_id=b.seller_id FROM seller_bank_accounts b WHERE b.bank_account_id=p.bank_account_id;
ALTER TABLE payouts ADD FOREIGN KEY(bank_account_id) REFERENCES users(user_id);
ALTER TABLE payouts ADD CHECK(bank_account_id=seller_id);
ALTER TABLE activity_logs DROP CONSTRAINT activity_logs_verification_id_fkey;
UPDATE activity_logs l SET verification_id=v.seller_id FROM seller_verifications v WHERE v.verification_id=l.verification_id;
UPDATE activity_logs l SET entity_id=v.seller_id FROM seller_verifications v
 WHERE l.entity_type='seller_verification' AND l.entity_id=v.verification_id;
ALTER TABLE activity_logs ADD FOREIGN KEY(verification_id) REFERENCES users(user_id);
DROP TABLE user_roles,roles,seller_bank_accounts,seller_verifications,categories,platform_settings,cancellation_requests;

DROP VIEW IF EXISTS public_market;
DROP VIEW IF EXISTS seller_qc_scores;
DROP VIEW IF EXISTS seller_sales;
DROP VIEW IF EXISTS buyer_orders;
DROP VIEW IF EXISTS eligible_payouts;
DROP VIEW IF EXISTS admin_finance_summary;
-- 002_workflows.sql

SET search_path TO owl, public;

CREATE FUNCTION platform_configuration() RETURNS TABLE(
 platform_fee_percent NUMERIC,shipping_fee NUMERIC,active_turn_hours SMALLINT)
LANGUAGE sql IMMUTABLE AS $$
 SELECT 10.00::NUMERIC,50.00::NUMERIC,24::SMALLINT;
$$;

CREATE FUNCTION has_role(p_user BIGINT,p_role TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path=owl,pg_temp AS $$
 SELECT coalesce((SELECT status='active' AND CASE p_role
 WHEN 'buyer' THEN is_buyer WHEN 'seller' THEN is_seller
 WHEN 'admin' THEN is_admin WHEN 'qc' THEN is_qc ELSE false END
 FROM users WHERE user_id=p_user),false);
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
 IF f.condition='new' THEN v_group:=ensure_group(f.variant_id,f.condition); END IF;
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer FOR UPDATE;
 IF f.status<>'pending' THEN RAISE EXCEPTION 'Offer is no longer pending'; END IF;
 IF p_decision NOT IN ('approve','reject') OR p_decision IS NULL THEN RAISE EXCEPTION 'Decision must be approve or reject'; END IF;
 IF p_decision='reject' AND coalesce(length(trim(p_reason)),0)=0 THEN RAISE EXCEPTION 'Rejection needs a reason'; END IF;
 UPDATE seller_offers SET review_decision=p_decision,reviewed_by=p_admin,review_reason=p_reason,reviewed_at=now() WHERE offer_id=p_offer;
 UPDATE seller_offers SET status=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END WHERE offer_id=p_offer;
 IF p_decision='approve' AND f.condition='new' THEN PERFORM queue_add(v_group,p_offer); PERFORM advance_queue(v_group); END IF;
 INSERT INTO notifications(user_id,offer_id,type,message) VALUES(f.seller_id,p_offer,'offer_review','Offer review: '||p_decision||'. '||p_reason);
 PERFORM log_action(p_admin,'offer_'||p_decision,'seller_offer',p_offer);
END; $$;
CREATE FUNCTION withdraw_offer(p_seller BIGINT,p_offer BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE f seller_offers; v_group BIGINT;
BEGIN
 PERFORM require_role(p_seller,'seller');
 SELECT * INTO f FROM seller_offers WHERE offer_id=p_offer AND seller_id=p_seller;
 IF NOT FOUND THEN RAISE EXCEPTION 'Own offer not found'; END IF;
 IF f.condition='new' THEN v_group:=ensure_group(f.variant_id,f.condition); END IF;
 PERFORM 1 FROM seller_offers WHERE offer_id=p_offer FOR UPDATE;
 UPDATE seller_offers SET status='withdrawn' WHERE offer_id=p_offer;
 IF f.condition='new' THEN
 DELETE FROM queue_entries WHERE offer_id=p_offer;
 UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE group_id=v_group AND active_offer_id=p_offer;
 INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',v_group,p_offer,'withdrawn');
 PERFORM advance_queue(v_group);
 END IF;
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

CREATE FUNCTION checkout_selected(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT,p_address BIGINT,p_coupon BIGINT,p_offer BIGINT) RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE g BIGINT; v_offer BIGINT; f seller_offers; a addresses; cfg RECORD; v_fee NUMERIC; v_discount NUMERIC; v_order BIGINT; v_product RECORD;
BEGIN
 PERFORM require_role(p_buyer,'buyer');
 SELECT * INTO a FROM addresses WHERE address_id=p_address AND user_id=p_buyer AND NOT archived;
 IF NOT FOUND THEN RAISE EXCEPTION 'Own active shipping address required'; END IF;
 IF p_condition='used' THEN
  SELECT * INTO f FROM seller_offers
  WHERE offer_id=p_offer AND variant_id=p_variant AND condition='used'
    AND status='approved' AND available_quantity>0 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Selected second-hand item is unavailable'; END IF;
  v_offer:=f.offer_id;
 ELSE
  g:=ensure_group(p_variant,p_condition); v_offer:=advance_queue(g);
  IF v_offer IS NULL THEN RAISE EXCEPTION 'No approved stock available'; END IF;
  SELECT * INTO f FROM seller_offers WHERE offer_id=v_offer;
 END IF;
 IF f.seller_id=p_buyer THEN RAISE EXCEPTION 'Cannot buy own item'; END IF;
 SELECT * INTO cfg FROM platform_configuration();
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

CREATE FUNCTION checkout(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT,p_address BIGINT,p_coupon BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE sql SET search_path=owl,pg_temp AS $$
 SELECT checkout_selected(p_buyer,p_variant,p_condition,p_address,p_coupon,NULL);
$$;

CREATE FUNCTION confirm_payment(p_admin BIGINT,p_order BIGINT,p_reference TEXT,p_method TEXT DEFAULT 'demo') RETURNS BIGINT
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE o orders; i order_items; f seller_offers; g BIGINT; head BIGINT; paid payments; v_payment BIGINT; d NUMERIC;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO i FROM order_items WHERE order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order item missing'; END IF;
 IF i.condition_snapshot='new' THEN g:=ensure_group(i.variant_id,i.condition_snapshot); END IF;
 SELECT * INTO o FROM orders WHERE order_id=p_order FOR UPDATE;
 SELECT * INTO paid FROM payments WHERE order_id=p_order AND status='captured';
 IF FOUND THEN
  IF paid.reference=p_reference THEN RETURN paid.payment_id; ELSE RAISE EXCEPTION 'Order already paid'; END IF;
 END IF;
 IF o.status<>'awaiting_payment' THEN RAISE EXCEPTION 'Order is not awaiting payment'; END IF;
 IF i.condition_snapshot='new' THEN
 head:=advance_queue(g);
 IF head IS DISTINCT FROM i.offer_id THEN RAISE EXCEPTION 'Queue changed; create a new order before payment'; END IF;
 END IF;
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
 IF i.condition_snapshot='new' THEN
 UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE group_id=g;
 IF f.available_quantity>0 THEN PERFORM queue_add(g,f.offer_id,'sold');
 ELSE DELETE FROM queue_entries WHERE offer_id=f.offer_id; INSERT INTO activity_logs(event_source,group_id,offer_id,event_type) VALUES('queue',g,f.offer_id,'sold'); END IF;
 PERFORM advance_queue(g);
 END IF;
 PERFORM log_order(p_order,'awaiting_seller_shipment',p_admin,'Payment recorded. Stock reserved.');
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
DECLARE b users; v_payout BIGINT; v_total NUMERIC; ids BIGINT[];
BEGIN
 PERFORM require_role(p_admin,'admin');
 -- Serialize settlement batches for the same seller.
 PERFORM 1 FROM users WHERE user_id=p_seller AND seller_status IS NOT NULL FOR UPDATE;
 SELECT * INTO b FROM users WHERE user_id=p_bank AND user_id=p_seller AND bank_verified AND NOT bank_archived;
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
 IF NOT EXISTS(SELECT 1 FROM users WHERE user_id=NEW.bank_account_id AND user_id=NEW.seller_id AND bank_verified AND NOT bank_archived)
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

CREATE FUNCTION verify_seller(p_admin BIGINT,p_verification BIGINT,p_approve BOOLEAN,p_note TEXT) RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
BEGIN
 PERFORM require_role(p_admin,'admin');
 PERFORM 1 FROM users WHERE user_id=p_verification AND verification_status='pending' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Pending verification required'; END IF;
 UPDATE users SET verification_status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
 verification_reviewer_id=p_admin,verification_review_note=p_note,verification_reviewed_at=now() WHERE user_id=p_verification;
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
 IF p_reason IS NULL OR length(trim(p_reason))=0 THEN RAISE EXCEPTION 'Cancellation reason required'; END IF;
 UPDATE orders SET cancellation_reason=p_reason,cancellation_status='pending',cancellation_created_at=now()
 WHERE order_id=p_order AND buyer_id=p_buyer AND cancellation_status IS NULL RETURNING order_id INTO v_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Cancellation was already requested'; END IF;
 RETURN v_id;
END; $$;
CREATE FUNCTION review_cancellation(p_admin BIGINT,p_request BIGINT,p_approve BOOLEAN) RETURNS VOID
LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE r orders; o orders; i order_items; f seller_offers; g BIGINT; paid payments;
BEGIN
 PERFORM require_role(p_admin,'admin');
 SELECT * INTO r FROM orders WHERE order_id=p_request;
 IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
 SELECT * INTO i FROM order_items WHERE order_id=r.order_id;
 IF i.condition_snapshot='new' THEN g:=ensure_group(i.variant_id,i.condition_snapshot); END IF;
 SELECT * INTO r FROM orders WHERE order_id=p_request FOR UPDATE;
 SELECT * INTO o FROM orders WHERE order_id=r.order_id FOR UPDATE;
 SELECT * INTO i FROM order_items WHERE order_id=r.order_id FOR UPDATE;
 IF r.cancellation_status IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'Request already reviewed'; END IF;
 IF p_approve AND i.fulfillment_status NOT IN ('awaiting_payment','awaiting_seller_shipment') THEN RAISE EXCEPTION 'Seller already handed over item'; END IF;
 UPDATE orders SET cancellation_status=CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,cancellation_reviewed_by=p_admin,cancellation_reviewed_at=now() WHERE order_id=p_request;
 IF NOT p_approve THEN RETURN; END IF;
 SELECT * INTO paid FROM payments WHERE order_id=r.order_id AND status='captured';
 IF FOUND THEN
  UPDATE seller_offers SET available_quantity=available_quantity+1 WHERE offer_id=i.offer_id RETURNING * INTO f;
  IF f.status='approved' AND i.condition_snapshot='new' THEN
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
SELECT p.product_id,p.name AS product_name,p.brand_name AS brand,p.category,
 v.variant_id,v.size,v.color,f.condition,'Owl Pai Lei'::TEXT AS sold_by,
 round(f.asking_price*(1+cfg.platform_fee_percent/100),2) AS display_price,
 cfg.shipping_fee,f.condition_notes,f.defects,
 g.active_since+interval '24 hours' AS turn_expires_at,f.offer_id
FROM seller_offers f
JOIN product_variants v ON v.variant_id=f.variant_id JOIN products p USING(product_id)
CROSS JOIN platform_configuration() cfg
LEFT JOIN queue_groups g ON f.condition='new' AND g.active_offer_id=f.offer_id
WHERE (f.condition='used' OR g.active_offer_id IS NOT NULL)
 AND f.status='approved' AND f.available_quantity>0 AND p.active AND v.active;
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



COMMIT;
