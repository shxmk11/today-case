import { useState } from "react";
import CaseSelect from "./components/CaseSelect";
import Game from "./components/Game";
import Result from "./components/Result";
import type { AccuseResult } from "./types";

type Screen = { name: "select" } | { name: "game"; playId: number } | { name: "result"; result: AccuseResult; title: string };

export default function App() {
  const [screen, setScreen] = useState<Screen>({ name: "select" });

  return (
    <div className="app">
      <header className="topbar">
        <button className="logo" onClick={() => setScreen({ name: "select" })}>
          오늘의 사건<span className="logo-dot">.</span>
        </button>
      </header>
      {screen.name === "select" && <CaseSelect onStart={(playId) => setScreen({ name: "game", playId })} />}
      {screen.name === "game" && (
        <Game playId={screen.playId} onFinish={(result, title) => setScreen({ name: "result", result, title })} />
      )}
      {screen.name === "result" && (
        <Result result={screen.result} title={screen.title} onHome={() => setScreen({ name: "select" })} />
      )}
    </div>
  );
}
