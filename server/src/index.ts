import express from "express";
import { router } from "./routes.js";
import { llmMode } from "./llm.js";

const app = express();
app.use(express.json());
app.get("/api/health", (_req, res) => {
  res.json({ ok: true, llm: llmMode });
});
app.use("/api", router);

const port = Number(process.env.PORT ?? 3001);
app.listen(port, () => {
  console.log(`오늘의 사건 서버: http://localhost:${port} (LLM: ${llmMode})`);
});
