-- For an existing database only. Export any old cart data before running.
-- Refuse to remove a cart that still contains a selected item.
BEGIN;
DO $$
BEGIN
  IF to_regclass('owl.carts') IS NOT NULL THEN
    LOCK TABLE owl.carts IN ACCESS EXCLUSIVE MODE;
    IF EXISTS (SELECT 1 FROM owl.carts WHERE variant_id IS NOT NULL) THEN
      RAISE EXCEPTION 'Existing cart selections found. Export and clear them before removing carts.';
    END IF;
  END IF;
END;
$$;
DROP FUNCTION IF EXISTS owl.set_cart_item(BIGINT,BIGINT,TEXT);
DROP TABLE IF EXISTS owl.carts;
COMMIT;
