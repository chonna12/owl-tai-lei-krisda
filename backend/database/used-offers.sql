-- For the consolidated 23-table schema only. Older databases must run consolidate-23.sql first.
BEGIN;

SET LOCAL search_path TO owl, public;

CREATE OR REPLACE FUNCTION refresh_all_queues() RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
DECLARE g RECORD;
BEGIN FOR g IN SELECT group_id FROM queue_groups ORDER BY group_id LOOP PERFORM advance_queue(g.group_id); END LOOP; END; $$;

CREATE OR REPLACE FUNCTION review_offer(p_admin BIGINT,p_offer BIGINT,p_decision TEXT,p_reason TEXT DEFAULT '') RETURNS VOID
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

CREATE OR REPLACE FUNCTION withdraw_offer(p_seller BIGINT,p_offer BIGINT) RETURNS VOID LANGUAGE plpgsql SET search_path=owl,pg_temp AS $$
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

CREATE OR REPLACE FUNCTION checkout_selected(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT,p_address BIGINT,p_coupon BIGINT,p_offer BIGINT) RETURNS BIGINT
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

CREATE OR REPLACE FUNCTION checkout(p_buyer BIGINT,p_variant BIGINT,p_condition TEXT,p_address BIGINT,p_coupon BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE sql SET search_path=owl,pg_temp AS $$
 SELECT checkout_selected(p_buyer,p_variant,p_condition,p_address,p_coupon,NULL);
$$;

CREATE OR REPLACE FUNCTION confirm_payment(p_admin BIGINT,p_order BIGINT,p_reference TEXT,p_method TEXT DEFAULT 'demo') RETURNS BIGINT
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

CREATE OR REPLACE FUNCTION review_cancellation(p_admin BIGINT,p_request BIGINT,p_approve BOOLEAN) RETURNS VOID
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

CREATE OR REPLACE VIEW public_market AS
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

DELETE FROM queue_entries e USING queue_groups g WHERE e.group_id=g.group_id AND g.condition='used';

UPDATE queue_groups SET active_offer_id=NULL,active_since=NULL WHERE condition='used' AND active_offer_id IS NOT NULL;

REVOKE ALL ON FUNCTION checkout_selected(BIGINT,BIGINT,TEXT,BIGINT,BIGINT,BIGINT) FROM PUBLIC;

COMMIT;
