import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Database, Loader2, Lock } from "lucide-react";
import type { ApiError } from "../api/client";
import type { Priority, Status } from "../api/types";
import { STATUS_LABELS } from "../lib/format";

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(" ");
export { cx };

// ---------------------------------------------------------------- buttons
type Variant = "primary" | "secondary" | "ghost" | "danger";
export function Button({ variant = "primary", busy, className, children, ...rest }:
  ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; busy?: boolean }) {
  const styles: Record<Variant, string> = {
    primary: "bg-seal text-white hover:bg-seal-dark disabled:bg-ink-faint",
    secondary: "bg-white text-ink border border-line hover:border-ink-faint disabled:text-ink-faint",
    ghost: "text-ink-soft hover:text-ink hover:bg-white/60",
    danger: "bg-white text-high border border-high/40 hover:bg-high-soft",
  };
  return (
    <button
      {...rest}
      disabled={rest.disabled || busy}
      className={cx("inline-flex items-center justify-center gap-2 rounded-md px-3.5 py-2 text-sm font-medium",
        "transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-seal",
        "disabled:cursor-not-allowed", styles[variant], className)}
    >
      {busy && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
      {children}
    </button>
  );
}

// ---------------------------------------------------------------- badges
const STATUS_TONE: Record<Status, string> = {
  Filed: "bg-low-soft text-low",
  Triaged: "bg-low-soft text-low",
  NeedsInfo: "bg-medium-soft text-medium",
  Assigned: "bg-seal-soft text-seal",
  InProgress: "bg-seal-soft text-seal",
  Escalated: "bg-high-soft text-high",
  Resolved: "bg-white text-seal border border-seal/40",
  Rejected: "bg-white text-ink-soft border border-line",
  Closed: "bg-white text-ink-soft border border-line",
  Appealed: "bg-veil-soft text-veil",
};
export function StatusBadge({ status }: { status: Status }) {
  return <span className={cx("inline-flex items-center whitespace-nowrap rounded px-2 py-0.5 text-xs font-medium", STATUS_TONE[status])}>
    {STATUS_LABELS[status] ?? status}
  </span>;
}

const PRIORITY_TONE: Record<Priority, string> = {
  High: "text-high", Medium: "text-medium", Low: "text-low",
};
/** Priority as three bars: filled bars = level. Readable without colour. */
export function PriorityMark({ priority }: { priority: Priority | null }) {
  if (!priority) return <span className="text-xs text-ink-faint">–</span>;
  const n = priority === "High" ? 3 : priority === "Medium" ? 2 : 1;
  return (
    <span className={cx("inline-flex items-center gap-1.5 text-xs font-medium", PRIORITY_TONE[priority])}>
      <span className="flex items-end gap-[2px]" aria-hidden>
        {[1, 2, 3].map((i) => (
          <span key={i} className={cx("w-[3px] rounded-sm", i <= n ? "bg-current" : "bg-line")}
            style={{ height: 4 + i * 3 }} />
        ))}
      </span>
      {priority}
    </span>
  );
}

export function DeadlineText({ state, due }: { state: string | null; due: string | null }) {
  if (!due || !state) return <span className="text-ink-faint">–</span>;
  const tone = state === "Overdue" ? "text-high font-medium" : state === "DueSoon" ? "text-medium" : "text-ink-soft";
  const labels: Record<string, string> = {
    Overdue: "Overdue", DueSoon: "Due soon", OnTrack: "On track", Paused: "Paused (waiting for reply)",
    Done: "Done", NotRouted: "Not routed yet",
  };
  const label = labels[state] ?? state;
  return <span className={tone}>{label}</span>;
}

export function ConfidentialTag({ visibility }: { visibility: string }) {
  if (visibility === "Public") return null;
  return (
    <span className="inline-flex items-center gap-1 rounded bg-veil-soft px-2 py-0.5 text-xs font-medium text-veil">
      <Lock className="h-3 w-3" aria-hidden /> {visibility}
    </span>
  );
}

// ---------------------------------------------------------------- layout bits
export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-[1.65rem] font-semibold leading-tight tracking-[-0.01em] text-ink">{title}</h1>
        {subtitle && <p className="mt-1 max-w-2xl text-sm text-ink-soft">{subtitle}</p>}
      </div>
      {actions && <div className="flex gap-2">{actions}</div>}
    </header>
  );
}

export function Panel({ title, aside, children, className }: { title?: ReactNode; aside?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={cx("rounded-lg border border-line bg-white", className)}>
      {title && (
        <div className="flex items-center justify-between gap-3 border-b border-line px-5 py-3">
          <h2 className="text-sm font-semibold text-ink">{title}</h2>
          {aside}
        </div>
      )}
      <div className="px-5 py-4">{children}</div>
    </section>
  );
}

export function Spinner({ label = "Loading" }: { label?: string }) {
  return (
    <div className="flex items-center gap-2 py-10 text-sm text-ink-soft" role="status">
      <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> {label}…
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="py-8 text-center text-sm text-ink-soft">{children}</p>;
}

/** Errors. When PostgreSQL refused something, say so: that is the security model at work. */
export function ErrorNote({ error }: { error: ApiError | null | undefined }) {
  if (!error) return null;
  return (
    <div role="alert" className={cx("rounded-md border px-4 py-3 text-sm",
      error.fromDatabase ? "border-veil/30 bg-veil-soft text-ink" : "border-high/30 bg-high-soft text-ink")}>
      {error.fromDatabase && (
        <div className="mb-1 flex items-center gap-1.5 text-xs font-semibold text-veil">
          <Database className="h-3.5 w-3.5" aria-hidden /> PostgreSQL refused this
        </div>
      )}
      <span className={error.fromDatabase ? "font-mono text-[13px]" : ""}>{error.message}</span>
    </div>
  );
}

/** Shown where a section exists but this role has no GRANT to read it. */
export function HiddenByDb({ what }: { what: string }) {
  return (
    <p className="flex items-center gap-2 text-sm text-veil">
      <Lock className="h-3.5 w-3.5" aria-hidden /> {what} is hidden from your role by the database.
    </p>
  );
}

export function Field({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-ink">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-ink-soft">{hint}</span>}
    </label>
  );
}

export const inputClass =
  "w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink placeholder:text-ink-faint " +
  "focus:border-seal focus:outline-none focus:ring-2 focus:ring-seal/20";

export function Stars({ value, onChange }: { value: number; onChange?: (v: number) => void }) {
  return (
    <div className="flex gap-1" role={onChange ? "radiogroup" : undefined} aria-label="Rating">
      {[1, 2, 3, 4, 5].map((i) => (
        <button key={i} type="button" disabled={!onChange} onClick={() => onChange?.(i)}
          role={onChange ? "radio" : undefined} aria-checked={onChange ? i === value : undefined}
          aria-label={`${i} out of 5`}
          className={cx("text-xl leading-none", i <= value ? "text-medium" : "text-line", onChange && "hover:scale-110")}>
          ★
        </button>
      ))}
    </div>
  );
}
