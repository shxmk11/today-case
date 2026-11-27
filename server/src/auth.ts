import { randomBytes, scrypt as scryptCb, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import type { Request } from "express";
import { one, query } from "./db.js";

const scrypt = promisify(scryptCb) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;

/** 비밀번호는 scrypt 해시로만 저장한다: "scrypt$소금$해시" (16진수) */
export async function hashPassword(password: string) {
  const salt = randomBytes(16);
  const hash = await scrypt(password, salt, 32);
  return `scrypt$${salt.toString("hex")}$${hash.toString("hex")}`;
}

export async function checkPassword(password: string, stored: string) {
  const [kind, saltHex, hashHex] = stored.split("$");
  if (kind !== "scrypt" || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, "hex");
  const got = await scrypt(password, Buffer.from(saltHex, "hex"), expected.length);
  return got.length === expected.length && timingSafeEqual(got, expected);
}

export const isGuestId = (id: string) => id.startsWith("guest_");

export async function newSession(memberId: string) {
  const token = randomBytes(32).toString("hex");
  await query(`INSERT INTO login_session (token, member_id) VALUES (?, ?)`, [token, memberId]);
  return token;
}

/** 게스트 회원을 만들고 세션을 준다. 게스트 기록은 이 브라우저의 토큰으로만 이어진다 */
export async function newGuest() {
  const id = `guest_${randomBytes(7).toString("hex")}`; // 20자
  await query(`INSERT INTO member (member_id, password, nickname) VALUES (?, '', ?)`, [id, id]);
  return { memberId: id, token: await newSession(id) };
}

export function tokenOf(req: Request) {
  const h = req.get("authorization") ?? "";
  const m = h.match(/^Bearer ([0-9a-f]{64})$/);
  return m ? m[1] : null;
}

export interface Me {
  memberId: string;
  nickname: string;
  guest: boolean;
}

/** 요청의 토큰으로 회원을 찾는다 (없거나 만료면 null) */
export async function whoAmI(req: Request): Promise<Me | null> {
  const token = tokenOf(req);
  if (!token) return null;
  const m = await one<{ member_id: string; nickname: string }>(
    `SELECT m.member_id, m.nickname FROM login_session s JOIN member m ON m.member_id = s.member_id WHERE s.token = ?`,
    [token],
  );
  return m ? { memberId: m.member_id, nickname: m.nickname, guest: isGuestId(m.member_id) } : null;
}

/** 게스트로 하던 판을 로그인한 계정으로 옮긴다 */
export async function adoptGuestPlays(fromGuest: string, to: string) {
  if (!isGuestId(fromGuest) || fromGuest === to) return;
  await query(`UPDATE participant SET member_id = ? WHERE member_id = ?`, [to, fromGuest]);
  await query(`DELETE FROM member WHERE member_id = ?`, [fromGuest]);
}
