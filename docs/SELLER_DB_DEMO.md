# Seller demo verification

- Browser test: automatically authenticated as Demo Seller One; selected product and real PNG photo; entered THB 1234.56 and quantity 2; submitted through UI.
- The pending page showed offer #41. A direct PostgreSQL SELECT confirmed seller_id=1, status=pending, asking_price=1234.56, available_quantity=2 and one saved image. Notes identify it as a UI-to-PostgreSQL demo acceptance test.
- My sell orders loaded that offer and photo via authenticated API, not localStorage.
- PostgreSQL originally rejected the image because a B-tree index included the entire Base64 text. The new migration uses small MD5 deduplication keys. MD5 here is only an index-sizing/deduplication choice, not a password hash. Existing records were retained.
- npm test passed using an isolated temporary database and a realistic 128x128 PNG fixture larger than 30 KB; role, address and approved-offer checks remain covered.
- No Login UI added. The fictional seed account is automatically authenticated for presentation. Production must use a real sign-in flow.
