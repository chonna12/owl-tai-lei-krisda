import { hashPassword } from './security.js';

const isId = value => /^[1-9][0-9]{0,17}$/.test(String(value));
const isCondition = value => ['new', 'used'].includes(value);
const clean = value => typeof value === 'string' ? value.trim() : '';
const fail = (res, status, error) => res.status(status).json({ error });
const addressFields = {
  recipientName: ['recipient_name', 100],
  phone: ['phone', 30],
  addressLine: ['address_line', 500],
  district: ['district', 100],
  province: ['province', 100],
  postalCode: ['postal_code', 15]
};
const addressColumns = 'address_id,recipient_name,phone,address_line,district,province,postal_code,is_default';

async function transaction(pool, work) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export function mountBuyerRoutes(app, pool, account) {
  const buyer = [account, async (req, res, next) => {
    const { rows } = await pool.query("SELECT has_role($1,'buyer') AS allowed", [req.seller.user_id]);
    if (!rows[0].allowed) return fail(res, 403, 'Buyer role required');
    next();
  }];
  const userId = req => req.seller.user_id;

  app.post('/api/register', async (req, res) => {
    const b = req.body || {};
    const fullName = clean(b.fullName ?? b.name);
    const email = clean(b.email).toLowerCase();
    const password = b.password;
    if (!fullName || fullName.length > 100 || email.length > 254 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        typeof password !== 'string' || password.length < 8 || password.length > 200) {
      return fail(res, 400, 'Enter a name, valid email and password of 8 to 200 characters');
    }
    try {
      const user = await transaction(pool, async client => {
        const { rows: roles } = await client.query("SELECT role_id FROM roles WHERE name='buyer'");
        if (!roles.length) throw new Error('Buyer role has not been seeded');
        const { rows } = await client.query(
          'INSERT INTO users(full_name,email,password_hash) VALUES($1,$2,$3) RETURNING user_id,full_name,email',
          [fullName, email, hashPassword(password)]
        );
        await client.query('INSERT INTO user_roles(user_id,role_id) VALUES($1,$2)', [rows[0].user_id, roles[0].role_id]);
        return rows[0];
      });
      res.status(201).json({ user: { id: user.user_id, name: user.full_name, email: user.email, canSell: false } });
    } catch (error) {
      if (error.code === '23505') return fail(res, 409, 'Email already registered');
      throw error;
    }
  });

  app.get('/api/wishlist', buyer, async (req, res) => {
    const { rows } = await pool.query(`
      SELECT p.product_id,p.name,p.brand_name,w.added_at
      FROM wishlist_items w JOIN products p USING(product_id)
      WHERE w.user_id=$1 AND p.active ORDER BY w.added_at DESC,p.product_id
    `, [userId(req)]);
    res.json({ items: rows });
  });

  app.post('/api/wishlist', buyer, async (req, res) => {
    const productId = req.body?.productId;
    if (!isId(productId)) return fail(res, 400, 'Invalid product ID');
    const result = await pool.query(`
      INSERT INTO wishlist_items(user_id,product_id)
      SELECT $1,product_id FROM products WHERE product_id=$2 AND active
      ON CONFLICT DO NOTHING
    `, [userId(req), productId]);
    if (!result.rowCount) {
      const existing = await pool.query('SELECT 1 FROM wishlist_items WHERE user_id=$1 AND product_id=$2', [userId(req), productId]);
      if (!existing.rowCount) return fail(res, 404, 'Product not found');
    }
    res.json({ ok: true });
  });

  app.delete('/api/wishlist/:id', buyer, async (req, res) => {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid product ID');
    await pool.query('DELETE FROM wishlist_items WHERE user_id=$1 AND product_id=$2', [userId(req), req.params.id]);
    res.json({ ok: true });
  });

  async function saveAddress(req, res) {
    const id = req.params.id;
    if (id && !isId(id)) return fail(res, 400, 'Invalid address ID');
    const b = req.body || {};
    const fields = Object.entries(addressFields).filter(([key]) => !id || Object.hasOwn(b, key));
    const values = fields.map(([key]) => clean(b[key]));
    if (!fields.length || fields.some(([, [, max]], i) => !values[i] || values[i].length > max)) {
      return fail(res, 400, 'Enter valid shipping address details');
    }
    const names = fields.map(([, [column]]) => column);
    const placeholders = values.map((_, i) => '$' + (i + 1));
    values.push(userId(req));
    let sql = 'INSERT INTO addresses(' + names.join(',') + ',user_id) VALUES(' + placeholders.join(',') + ',$' + values.length + ')';
    if (id) {
      sql = 'UPDATE addresses SET ' + names.map((name, i) => name + '=' + placeholders[i]).join(',') +
        ' WHERE user_id=$' + values.length + ' AND address_id=$' + (values.length + 1) + ' AND NOT archived';
      values.push(id);
    }
    const { rows } = await pool.query(sql + ' RETURNING ' + addressColumns, values);
    if (!rows.length) return fail(res, 404, 'Address not found');
    res.status(id ? 200 : 201).json({ address: rows[0] });
  }

  app.post('/api/addresses', buyer, saveAddress);
  app.patch('/api/addresses/:id', buyer, saveAddress);
  app.delete('/api/addresses/:id', buyer, async (req, res) => {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid address ID');
    const result = await pool.query('UPDATE addresses SET archived=true WHERE user_id=$1 AND address_id=$2 AND NOT archived', [userId(req), req.params.id]);
    if (!result.rowCount) return fail(res, 404, 'Address not found');
    res.json({ ok: true });
  });

  app.get('/api/cart', buyer, async (req, res) => {
    const { rows } = await pool.query(`
      SELECT c.variant_id,c.condition,c.quantity,p.product_id,p.name,v.size,v.color
      FROM carts c JOIN product_variants v USING(variant_id) JOIN products p USING(product_id)
      WHERE c.user_id=$1
    `, [userId(req)]);
    res.json({ item: rows[0] || null });
  });

  app.put('/api/cart', buyer, async (req, res) => {
    const { variantId, condition, quantity = 1 } = req.body || {};
    if (!isId(variantId) || !isCondition(condition) || quantity !== 1) {
      return fail(res, 400, 'Select a variant, condition and quantity of one');
    }
    const { rowCount } = await pool.query(`
      SELECT 1 FROM product_variants v JOIN products p USING(product_id)
      WHERE v.variant_id=$1 AND v.active AND p.active
    `, [variantId]);
    if (!rowCount) return fail(res, 404, 'Variant not found');
    await pool.query('SELECT set_cart_item($1,$2,$3)', [userId(req), variantId, condition]);
    res.json({ ok: true });
  });

  app.delete('/api/cart', buyer, async (req, res) => {
    await pool.query('DELETE FROM carts WHERE user_id=$1', [userId(req)]);
    res.json({ ok: true });
  });

  app.get('/api/orders', buyer, async (req, res) => {
    const { rows } = await pool.query(`
      SELECT b.*,c.request_id AS cancellation_request_id,c.status AS cancellation_status,
             s.tracking_number,s.carrier,s.status AS shipment_status
      FROM buyer_orders b
      LEFT JOIN order_items i USING(order_id)
      LEFT JOIN shipments s ON s.order_item_id=i.order_item_id AND s.leg='hub_to_buyer'
      LEFT JOIN cancellation_requests c ON c.order_id=b.order_id AND c.buyer_id=b.buyer_id
      WHERE b.buyer_id=$1 ORDER BY b.order_id DESC
    `, [userId(req)]);
    res.json({ orders: rows, demoPayment: process.env.DEMO_PAYMENT === 'true' });
  });

    app.post('/api/orders/:id/demo-payment', buyer, async (req, res) => {
    if (process.env.DEMO_PAYMENT !== 'true') return fail(res, 404, 'Demo payment is disabled');
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid order ID');
    const { rows } = await pool.query(`
      SELECT o.order_id, u.user_id AS admin_id
      FROM orders o
      LEFT JOIN users u ON u.email = 'admin@owl.test' AND has_role(u.user_id, 'admin')
      WHERE o.order_id = $1 AND o.buyer_id = $2
    `, [req.params.id, userId(req)]);
    if (!rows.length) return fail(res, 404, 'Order not found');
    const { order_id, admin_id } = rows[0];
    if (!admin_id) return fail(res, 409, 'Demo admin account is unavailable');
    await pool.query('SELECT confirm_payment($1,$2,$3,$4)', [admin_id, order_id, 'buyer-demo-' + order_id, 'demo']);
    res.json({ ok: true });
  });

app.post('/api/orders/:id/cancel', buyer, async (req, res) => {
    const reason = clean(req.body?.reason);
    if (!isId(req.params.id) || !reason || reason.length > 500) return fail(res, 400, 'Enter an order ID and cancellation reason');
    try {
      const { rows } = await pool.query('SELECT request_cancellation($1,$2,$3) AS request_id', [userId(req), req.params.id, reason]);
      res.status(201).json({ requestId: rows[0].request_id, status: 'pending' });
    } catch (error) {
      if (error.code === '23505') return fail(res, 409, 'Cancellation was already requested');
      throw error;
    }
  });

  app.post('/api/orders/:id/receipt', buyer, async (req, res) => {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid order ID');
    await pool.query('SELECT confirm_receipt($1,$2)', [userId(req), req.params.id]);
    res.json({ ok: true, status: 'completed' });
  });
}
