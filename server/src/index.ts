import express from "express";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { router } from "./routes.js";
import { llmMode, avoidLine } from "./llm.js";
import { rateLimit } from "./rateLimit.js";

const app = express();
// Render 같은 호스팅은 앞단 프록시를 거치므로, 실제 접속 IP를 쓰려면 필요
app.set("trust proxy", 1);
app.use(express.json());
app.get("/api/health", (_req, res) => {
  res.json({ ok: true, llm: llmMode });
});
// AI를 부르는 심문(증거 제시·자유 질문)만 제한 (기본: 분당 10번, 하루 200번). 기본 질문은 AI를 쓰지 않아 제한 없음
// 한도에 걸리면 오류 대신 인물이 대화를 피하는 말을 돌려준다 (저장하지 않고 횟수도 쓰지 않음)
app.use(
  "/api/plays/:id/interrogate",
  rateLimit({
    perMinute: Number(process.env.RATE_PER_MINUTE ?? 10),
    perDay: Number(process.env.RATE_PER_DAY ?? 200),
    onLimit: (_req, res) => {
      res.json({ answer: avoidLine(), question: "", busy: true, notice: "조금 이따가 다시 질문해 보세요." });
    },
  }),
);
// 진상 공개 뒤 AI에게 묻기도 같은 한도를 쓴다
app.use(
  "/api/plays/:id/ask",
  rateLimit({
    perMinute: Number(process.env.RATE_PER_MINUTE ?? 10),
    perDay: Number(process.env.RATE_PER_DAY ?? 200),
  }),
);
app.use("/api", router);

// 배포할 때는 이 서버가 빌드된 화면(client/dist)도 함께 보낸다
const clientDist = fileURLToPath(new URL("../../client/dist", import.meta.url));
if (existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get(/^(?!\/api).*/, (_req, res) => res.sendFile(`${clientDist}/index.html`));
}

const port = Number(process.env.PORT ?? 3001);
app.listen(port, () => {
  console.log(`오늘의 사건 서버: http://localhost:${port} (LLM: ${llmMode})`);
});
