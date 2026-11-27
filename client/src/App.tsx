import { useEffect, useState } from "react";
import CaseSelect from "./components/CaseSelect";
import Game from "./components/Game";
import Result from "./components/Result";
import { api } from "./api";
import type { AccuseResult, Me } from "./types";

type Screen = { name: "select" } | { name: "game"; playId: number } | { name: "result"; result: AccuseResult; title: string };

export default function App() {
  const [screen, setScreen] = useState<Screen>({ name: "select" });
  const [me, setMe] = useState<Me | null>(null);
  const [error, setError] = useState("");
  const home = () => setScreen({ name: "select" });

  // 로그인 안 했으면 게스트 세션을 받아 둔다 (게스트 기록은 이 브라우저에만)
  useEffect(() => {
    api.session().then(setMe).catch((e: Error) => setError(e.message));
  }, []);

  async function newPlay(caseId: number) {
    const { playId } = await api.startPlay(caseId);
    setScreen({ name: "game", playId });
  }

  /** 실패한 판은 지목 직전으로 되돌리고, 진행 중인 판은 그대로 연다 */
  async function resume(playId: number) {
    await api.resume(playId);
    setScreen({ name: "game", playId });
  }

  async function showResult(playId: number, title: string) {
    setScreen({ name: "result", result: await api.result(playId), title });
  }

  if (!me) {
    return <div className="app">{error ? <p className="error page">{error}</p> : <p className="loading-center">사건 파일을 여는 중…</p>}</div>;
  }

  return (
    <div className="app">
      {screen.name === "select" && (
        <CaseSelect
          me={me}
          onMe={setMe}
          onHome={home}
          onNew={newPlay}
          onResume={resume}
          onResult={showResult}
        />
      )}
      {screen.name === "game" && (
        <Game
          key={screen.playId}
          playId={screen.playId}
          onHome={home}
          onFinish={(result, title) => setScreen({ name: "result", result, title })}
        />
      )}
      {screen.name === "result" && (
        <Result
          key={`${screen.result.playId}-${screen.result.result}`}
          result={screen.result}
          title={screen.title}
          onHome={home}
          onResume={() => resume(screen.result.playId)}
          onNew={() => newPlay(screen.result.caseId)}
        />
      )}
    </div>
  );
}
