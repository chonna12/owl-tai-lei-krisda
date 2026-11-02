import pg from 'pg';
import {readFile} from 'node:fs/promises';
const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});
try{
  const exists=await pool.query("SELECT 1 FROM information_schema.schemata WHERE schema_name='owl'");
  if(exists.rowCount)throw Error('Schema owl already exists. Nothing overwritten. Use the existing database or create a new empty database.');
  await pool.query(await readFile(new URL('../database/schema.sql',import.meta.url),'utf8'));
  console.log('Created 31 tables and fictional catalog data. Run npm start.');
}catch(e){console.error('Setup stopped:',e.message);process.exitCode=1;}finally{await pool.end();}
