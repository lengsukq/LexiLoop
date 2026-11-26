import { useEffect, useRef, useState } from "react";
import { CheckCircle2, Volume2, XCircle } from "lucide-react";
import { playCachedTts } from "@/lib/tts-client";
import { Button } from "@/components/ui";
import type { GameItem } from "./types";

interface DragState {
  startX: number;
  startY: number;
  startId: string;
  startZone: "pool" | "built";
  active: boolean;
}

export function WordBuilder({ item, revealed, onSolved, onMistake, onReveal, onConfirmRevealed }: {
  item: GameItem;
  revealed: boolean;
  onSolved: () => void;
  onMistake: () => void;
  onReveal: () => void;
  onConfirmRevealed: () => void;
}) {
  const [builtLetterIds, setBuiltLetterIds] = useState<string[]>([]);
  const [wrongChoice, setWrongChoice] = useState<string | null>(null);
  const dragStateRef = useRef<DragState | null>(null);
  const suppressClickRef = useRef(false);

  function applyTile(id: string, zone: string) {
    if (zone === "pool") setBuiltLetterIds((ids) => ids.includes(id) ? ids : [...ids, id]);
    else setBuiltLetterIds((ids) => ids.filter((value) => value !== id));
  }

  function handleTilePointerDown(event: React.PointerEvent, id: string, zone: "pool" | "built") {
    if (revealed) return;
    suppressClickRef.current = false;
    dragStateRef.current = { startX: event.clientX, startY: event.clientY, startId: id, startZone: zone, active: false };
  }

  function handleTileClick(id: string, zone: "pool" | "built") {
    if (suppressClickRef.current) {
      suppressClickRef.current = false;
      return;
    }
    if (revealed) return;
    applyTile(id, zone);
  }

  function handleDragMove(event: React.PointerEvent | PointerEvent) {
    const state = dragStateRef.current;
    if (!state || revealed) return;
    if (!state.active) {
      if (Math.hypot(event.clientX - state.startX, event.clientY - state.startY) < 10) return;
      state.active = true;
      suppressClickRef.current = true;
      applyTile(state.startId, state.startZone);
    }
    const element = document.elementFromPoint(event.clientX, event.clientY);
    const tile = element instanceof Element ? element.closest("[data-letter-id]") : null;
    if (!tile) return;
    const id = tile.getAttribute("data-letter-id") ?? "";
    const zone = tile.getAttribute("data-letter-zone") ?? "";
    if (id) applyTile(id, zone);
  }

  const dragMoveRef = useRef(handleDragMove);
  useEffect(() => {
    dragMoveRef.current = handleDragMove;
  });

  useEffect(() => {
    const onMove = (event: PointerEvent) => dragMoveRef.current(event);
    const endDrag = () => { dragStateRef.current = null; };
    window.addEventListener("pointermove", onMove, true);
    window.addEventListener("pointerup", endDrag, true);
    window.addEventListener("pointercancel", endDrag, true);
    return () => {
      window.removeEventListener("pointermove", onMove, true);
      window.removeEventListener("pointerup", endDrag, true);
      window.removeEventListener("pointercancel", endDrag, true);
    };
  }, []);

  function submitWord() {
    if (revealed) return;
    const answer = builtLetterIds.map((id) => item.letters.find((letter) => letter.id === id)?.value ?? "").join("");
    if (answer.toLocaleLowerCase() === item.term.toLocaleLowerCase()) {
      onSolved();
      return;
    }
    onMistake();
    setWrongChoice("__word__");
    window.setTimeout(() => {
      setWrongChoice(null);
      setBuiltLetterIds([]);
    }, 440);
  }

  const builtLetters = builtLetterIds
    .map((id) => item.letters.find((letter) => letter.id === id))
    .filter(Boolean) as Array<{ id: string; value: string }>;

  return (
    <div className="text-center">
      <p className="text-[13px] text-quaternary-label">根据释义拼出英文</p>
      <h1 className="mx-auto mt-3 max-w-xl text-xl font-bold leading-relaxed sm:text-2xl">{item.definition}</h1>
      <button type="button" onClick={() => void playCachedTts(item.term, "US")} className="ios-press mx-auto mt-4 grid size-12 place-items-center rounded-full bg-warning/12 text-warning shadow-[0_6px_20px_rgba(255,149,0,0.12)]">
        <Volume2 className="size-5" />
      </button>
      {revealed ? (
        <div className="animate-scale-in mx-auto mt-5 max-w-xl">
          <div className="rounded-[18px] border-2 border-warning/40 bg-warning/[0.06] px-4 py-6">
            <p className="text-[13px] font-medium text-warning">正确答案 · 计时已暂停</p>
            <div className="mt-4 flex flex-wrap justify-center gap-1.5">
              {item.term.split("").map((char, charIndex) => (
                <span key={`${char}-${charIndex}`} className="grid size-12 place-items-center rounded-[14px] bg-gradient-to-br from-warning to-[#ff6961] text-lg font-bold uppercase text-white shadow-md">{char}</span>
              ))}
            </div>
            <p className="mt-4 text-sm leading-relaxed text-quaternary-label">记住它的拼写，然后继续下一题。该词已记入错词，之后会优先复习。</p>
          </div>
          <Button size="lg" className="mt-5 w-full sm:w-auto" onClick={onConfirmRevealed}><CheckCircle2 className="size-5" />记住了，继续</Button>
        </div>
      ) : (
        <>
          <div className="touch-none select-none">
            <div className={`mx-auto mt-5 flex min-h-16 max-w-xl flex-wrap items-center justify-center gap-2 rounded-[18px] border-2 border-dashed px-4 py-3 ${wrongChoice === "__word__" ? "border-danger bg-danger/[0.06]" : "border-accent/20 bg-accent/[0.04]"}`}>
              {builtLetters.length ? builtLetters.map((letter) => (
                <button key={letter.id} type="button" data-letter-id={letter.id} data-letter-zone="built" onPointerDown={(event) => handleTilePointerDown(event, letter.id, "built")} onClick={() => handleTileClick(letter.id, "built")} className="ios-press touch-none grid size-11 place-items-center rounded-[12px] bg-accent text-lg font-bold uppercase text-white shadow-md">{letter.value}</button>
              )) : <span className="text-sm text-tertiary-label">点按或滑动字母拼写</span>}
            </div>
            <div className="mx-auto mt-6 flex max-w-xl flex-wrap justify-center gap-2">
              {item.letters.map((letter) => {
                const used = builtLetterIds.includes(letter.id);
                return (
                  <button key={letter.id} type="button" aria-disabled={used} data-letter-id={letter.id} data-letter-zone="pool" onPointerDown={(event) => handleTilePointerDown(event, letter.id, "pool")} onClick={() => handleTileClick(letter.id, "pool")} className={`ios-press touch-none grid size-12 place-items-center rounded-[14px] border border-black/[0.06] bg-white/70 text-lg font-bold uppercase shadow-sm dark:border-white/[0.08] dark:bg-white/[0.06] ${used ? "opacity-20" : ""}`}>{letter.value}</button>
                );
              })}
            </div>
          </div>
          <div className="mx-auto mt-7 grid max-w-md grid-cols-[auto_auto_1fr] gap-2">
            <Button variant="outline" onClick={() => setBuiltLetterIds([])} disabled={!builtLetterIds.length}>清空</Button>
            <Button variant="outline" onClick={onReveal} className="text-danger"><XCircle className="size-4" />不认识</Button>
            <Button onClick={submitWord} disabled={builtLetterIds.length !== item.letters.length}><CheckCircle2 className="size-4" />提交答案</Button>
          </div>
        </>
      )}
    </div>
  );
}
