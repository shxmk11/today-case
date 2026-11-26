import { useState } from "react";
import CaseSelect from "./components/CaseSelect";
import Game from "./components/Game";
import Result from "./components/Result";
import { api } from "./api";
import type { AccuseResult } from "./types";

type Screen = { name: "select" } | { name: "game"; playId: number } | { name: "result"; result: AccuseResult; title: string };

export default function App() {
  const [screen, setScreen] = useState<Screen>({ name: "select" });
  const home = () => setScreen({ name: "select" });

  async function retry(caseId: number) {
    const { playId } = await api.startPlay(caseId);
    setScreen({ name: "game", playId });
  }

  return (
    <div className="app">
      {screen.name === "select" && <CaseSelect onHome={home} onStart={(playId) => setScreen({ name: "game", playId })} />}
      {screen.name === "game" && (
        <Game
          key={screen.playId}
          playId={screen.playId}
          onHome={home}
          onFinish={(result, title) => setScreen({ name: "result", result, title })}
        />
      )}
      {screen.name === "result" && (
        <Result result={screen.result} title={screen.title} onHome={home} onRetry={() => retry(screen.result.caseId)} />
      )}
    </div>
  );
}
