-- Existing databases: rebuild only image deduplication indexes, without changing image data.
-- MD5 is used to keep deduplication index keys small, not for passwords or authentication.
BEGIN;
DROP INDEX IF EXISTS owl.assets_product_file;
DROP INDEX IF EXISTS owl.assets_offer_file;
DROP INDEX IF EXISTS owl.assets_qc_file;
CREATE UNIQUE INDEX assets_product_file ON owl.assets(product_id,md5(file_reference)) WHERE product_id IS NOT NULL;
CREATE UNIQUE INDEX assets_offer_file ON owl.assets(offer_id,md5(file_reference)) WHERE offer_id IS NOT NULL;
CREATE UNIQUE INDEX assets_qc_file ON owl.assets(inspection_id,md5(file_reference)) WHERE inspection_id IS NOT NULL;
COMMIT;
