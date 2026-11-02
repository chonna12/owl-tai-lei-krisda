import pg from 'pg';
import {readFile} from 'node:fs/promises';
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});
try {
  await pool.query(await readFile(new URL('../database/migrations/001_asset_file_hash_indexes.sql',import.meta.url),'utf8'));
  console.log('Image indexes updated. Existing image and offer data retained.');
} catch(error) {console.error('Migration stopped:',error.message);process.exitCode=1;}
finally {await pool.end();}
