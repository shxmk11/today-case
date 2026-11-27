import { useState, type FormEvent } from "react";
import { api } from "../api";
import type { Me } from "../types";

/* 로그인 / 가입 창. 로그인은 선택: 하면 어느 기기에서든 이어 할 수 있고, 게스트로 하던 기록은 계정으로 옮겨진다 */
export default function LoginModal({ onClose, onDone }: { onClose: () => void; onDone: (me: Me) => void }) {
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [id, setId] = useState("");
  const [password, setPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      onDone(mode === "login" ? await api.login(id, password) : await api.signup(id, password, nickname));
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <div className="modal-back" onClick={onClose}>
      <form className="modal login" onClick={(e) => e.stopPropagation()} onSubmit={submit}>
        <p className="lbl">{mode === "login" ? "로그인" : "가입하기"}</p>
        <h2 className="display">{mode === "login" ? "다시 오셨군요" : "탐정 등록"}</h2>
        <p className="modal-note">
          로그인하지 않아도 이 브라우저에 기록이 남아요. 로그인하면 다른 기기에서도 이어 할 수 있고, 지금까지 한 기록도 계정으로 옮겨져요.
        </p>
        <label className="field-row">
          <small>아이디</small>
          <input value={id} onChange={(e) => setId(e.target.value)} autoComplete="username" maxLength={20} required autoFocus />
        </label>
        <label className="field-row">
          <small>비밀번호</small>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete={mode === "login" ? "current-password" : "new-password"}
            minLength={mode === "signup" ? 6 : undefined}
            maxLength={100}
            required
          />
        </label>
        {mode === "signup" && (
          <label className="field-row">
            <small>닉네임</small>
            <input value={nickname} onChange={(e) => setNickname(e.target.value)} maxLength={30} required />
          </label>
        )}
        {mode === "signup" && <p className="modal-note small">아이디는 영문·숫자·밑줄 4~20자, 비밀번호는 6자 이상이에요.</p>}
        {error && <p className="error">{error}</p>}
        <div className="modal-actions login-actions">
          <button
            type="button"
            className="link"
            onClick={() => {
              setMode(mode === "login" ? "signup" : "login");
              setError("");
            }}
          >
            {mode === "login" ? "처음이에요? 가입하기" : "이미 계정이 있어요"}
          </button>
          <span className="grow" />
          <button type="button" className="pill outline-dark" onClick={onClose}>
            닫기
          </button>
          <button className="pill red" disabled={busy}>
            {busy ? "확인 중…" : mode === "login" ? "로그인" : "가입하고 로그인"}
          </button>
        </div>
      </form>
    </div>
  );
}
