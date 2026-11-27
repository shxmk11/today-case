import type { Request, Response, NextFunction } from "express";

/**
 * 아주 단순한 IP별 요청 수 제한 (메모리 보관, 서버 한 대 기준).
 * 공개 링크에서 한 사람이 AI 무료 한도를 다 써버리지 않게 막는다.
 */
export function rateLimit({ perMinute, perDay, onLimit }: {
  perMinute: number;
  perDay: number;
  /** 한도에 걸렸을 때 직접 답하기 (없으면 429 오류) */
  onLimit?: (req: Request, res: Response) => void;
}) {
  const hits = new Map<string, number[]>();
  const DAY = 24 * 60 * 60 * 1000;

  return (req: Request, res: Response, next: NextFunction) => {
    const ip = req.ip ?? "unknown";
    const now = Date.now();
    const list = (hits.get(ip) ?? []).filter((t) => now - t < DAY);
    const lastMinute = list.filter((t) => now - t < 60_000).length;

    if (lastMinute >= perMinute || list.length >= perDay) {
      hits.set(ip, list);
      if (onLimit) {
        onLimit(req, res);
        return;
      }
      res.status(429).json({
        error: lastMinute >= perMinute
          ? "질문이 너무 빨라요. 1분쯤 뒤에 다시 물어보세요."
          : "오늘 질문 횟수를 다 썼어요. 내일 다시 와주세요.",
      });
      return;
    }
    list.push(now);
    hits.set(ip, list);
    next();
  };
}
