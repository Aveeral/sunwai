import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { api } from "../api/client";

/** The demo clock. The database's app_now() can be moved forward to show
 *  deadlines passing and escalation. The UI uses the same "now" for
 *  "3 h overdue" texts, so everything stays consistent. */
interface Clock {
  offsetHours: number;
  now: number;
  version: number;           // bumps whenever time moves or escalation runs (pages reload on it)
  advance: (hours: number) => Promise<void>;
  reset: () => Promise<void>;
  escalate: () => Promise<{ escalated: number; closed_stale: number }>;
}
const ClockContext = createContext<Clock | null>(null);

export function ClockProvider({ children }: { children: ReactNode }) {
  const [offsetHours, setOffset] = useState(0);
  const [version, setVersion] = useState(0);
  const [tick, setTick] = useState(Date.now());

  useEffect(() => {
    api<{ offset_hours: number }>("/demo/clock").then((r) => setOffset(r.offset_hours)).catch(() => {});
    const t = setInterval(() => setTick(Date.now()), 60_000);
    return () => clearInterval(t);
  }, []);

  const advance = useCallback(async (hours: number) => {
    const r = await api<{ offset_hours: number }>("/demo/clock", { body: { advance_hours: hours } });
    setOffset(r.offset_hours); setVersion((v) => v + 1);
  }, []);
  const reset = useCallback(async () => {
    const r = await api<{ offset_hours: number }>("/demo/clock", { body: { offset_hours: 0 } });
    setOffset(r.offset_hours); setVersion((v) => v + 1);
  }, []);
  const escalate = useCallback(async () => {
    const r = await api<{ escalated: number; closed_stale: number }>("/demo/escalate", { method: "POST" });
    setVersion((v) => v + 1);
    return r;
  }, []);

  return (
    <ClockContext.Provider value={{ offsetHours, now: tick + offsetHours * 36e5, version, advance, reset, escalate }}>
      {children}
    </ClockContext.Provider>
  );
}

export function useClock(): Clock {
  const ctx = useContext(ClockContext);
  if (!ctx) throw new Error("useClock outside ClockProvider");
  return ctx;
}
