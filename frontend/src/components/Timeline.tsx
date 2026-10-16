import { fmtDateTime } from "../lib/format";
import { cx } from "./ui";

type Item = { at: string; kind: string; title: string; detail: string | null };

const DOT: Record<string, string> = { Status: "bg-seal", Routing: "bg-ink", Question: "bg-medium" };
const pretty = (t: string) => t.replace(" -> ", " → ").replace("NeedsInfo", "Needs info").replace("InProgress", "In progress");

/** The complaint's history from v_complaint_timeline (status changes, routing, questions). */
export default function Timeline({ items }: { items: Item[] }) {
  if (items.length === 0) return <p className="text-sm text-ink-soft">No history yet.</p>;
  return (
    <ol className="relative space-y-4 border-l border-line pl-5">
      {items.map((t, i) => (
        <li key={i} className="relative">
          <span className={cx("absolute -left-[25px] top-1.5 h-2.5 w-2.5 rounded-full ring-4 ring-white", DOT[t.kind] ?? "bg-ink-faint")} aria-hidden />
          <div className="flex flex-wrap items-baseline justify-between gap-x-3">
            <p className="text-sm font-medium text-ink">
              {t.kind === "Question" ? "Question: " : ""}{pretty(t.title)}
            </p>
            <time className="text-xs text-ink-faint">{fmtDateTime(t.at)}</time>
          </div>
          {t.detail && <p className="mt-0.5 text-sm text-ink-soft">{t.detail}</p>}
        </li>
      ))}
    </ol>
  );
}
