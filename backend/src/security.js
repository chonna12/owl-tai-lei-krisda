import { randomBytes, scryptSync, timingSafeEqual, createHash } from 'node:crypto';

export function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  return `${salt}:${scryptSync(password, salt, 64).toString('hex')}`;
}

export function verifyPassword(password, stored) {
  const [salt, hex] = stored.split(':');
  const expected = Buffer.from(hex, 'hex');
  const actual = scryptSync(password, salt, 64);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

export const tokenHash = token => createHash('sha256').update(token).digest('hex');
export const newToken = () => randomBytes(32).toString('hex');

export function readToken(req) {
  const bearer = req.headers.authorization;
  if (bearer?.startsWith('Bearer ')) return bearer.slice(7);
  const cookie = (req.headers.cookie || '').split(';').find(x => x.trim().startsWith('owl_session='));
  return cookie ? cookie.trim().slice('owl_session='.length) : '';
}
