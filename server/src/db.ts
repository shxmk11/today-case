import mysql from "mysql2/promise";

export const pool = mysql.createPool({
  host: process.env.DB_HOST ?? "localhost",
  port: Number(process.env.DB_PORT ?? 3306),
  user: process.env.DB_USER ?? "root",
  password: process.env.DB_PASSWORD ?? "",
  database: process.env.DB_NAME ?? "today_case",
  charset: "utf8mb4",
  // TINYINT(1) 컬럼(BOOLEAN)을 true/false로 받기
  typeCast(field, next) {
    if (field.type === "TINY" && field.length === 1) {
      const v = field.string();
      return v === null ? null : v === "1";
    }
    return next();
  },
});

export async function query<T>(sql: string, params: unknown[] = []): Promise<T[]> {
  const [rows] = await pool.query(sql, params);
  return rows as T[];
}

export async function one<T>(sql: string, params: unknown[] = []): Promise<T | undefined> {
  return (await query<T>(sql, params))[0];
}

export async function insert(sql: string, params: unknown[] = []): Promise<number> {
  const [result] = await pool.execute(sql, params as never[]);
  return (result as mysql.ResultSetHeader).insertId;
}
