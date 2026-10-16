import type { ReactNode } from "react";
import {
  CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import { api } from "../api/client";
import type { Analytics } from "../api/types";
import { ErrorNote, PageHeader, Panel, Spinner, cx } from "../components/ui";
import { fmtDate } from "../lib/format";
import { useClock } from "../lib/clock";
import { useAsync } from "../lib/useAsync";

// Every chart is a single series in the one accent colour; comparisons across
// categories are bars sorted by value, details are in plain tables.
const SEAL = "#24584B";
const AXIS = { fontSize: 12, fill: "#7A8396" };
const TOOLTIP = { contentStyle: { borderRadius: 6, border: "1px solid #DFE2E8", fontSize: 13 }, cursor: { fill: "#F4F5F7" } };

/** Administrator dashboard: the analytics views (aggregates only; sensitive
 *  complaints are counted but never listed). */
export default function Dashboard() {
  const clock = useClock();
  const { data, error, loading } = useAsync(() => api<Analytics>("/analytics"), [clock.version]);
  if (loading && !data) return <Spinner />;
  if (error) return <ErrorNote error={error} />;
  const a = data!;

  // total complaints per week (all domains)
  const weeks = Object.values(a.weekly_trend.reduce<Record<string, { week: string; complaints: number }>>((acc, r) => {
    acc[r.week] ??= { week: r.week, complaints: 0 };
    acc[r.week].complaints += Number(r.complaints);
    return acc;
  }, {})).sort((x, y) => x.week.localeCompare(y.week));
  const hotspots = a.hotspots.map((h) => ({ ...h, label: `${h.unit} (${h.domain})` })).slice(0, 8);
  const maxHot = Math.max(1, ...hotspots.map((h) => Number(h.complaints)));

  return (
    <>
      <PageHeader title="Dashboard"
        subtitle="Computed live by the analytics views. Sensitive complaints are included in the counts but can never be opened from this role." />

      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-line bg-line sm:grid-cols-5">
        <Stat label="Complaints" value={a.summary.total_complaints} />
        <Stat label="Open now" value={a.summary.open_complaints} />
        <Stat label="Escalated now" value={a.summary.escalated_now} tone={a.summary.escalated_now ? "text-high" : undefined} />
        <Stat label="Average time to resolve" value={a.summary.avg_hours_to_resolve !== null ? `${Math.round(Number(a.summary.avg_hours_to_resolve))} h` : "–"} />
        <Stat label="Average rating" value={a.summary.avg_rating !== null ? `${Number(a.summary.avg_rating).toFixed(1)} / 5` : "–"} />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <Panel title="Complaints per week" aside={<Source v="v_weekly_trend" />}>
          <div className="h-56">
            <ResponsiveContainer>
              <LineChart data={weeks} margin={{ top: 8, right: 8, left: -20, bottom: 0 }}>
                <CartesianGrid stroke="#EEF0F3" vertical={false} />
                <XAxis dataKey="week" tickFormatter={fmtDate} tick={AXIS} axisLine={false} tickLine={false} />
                <YAxis allowDecimals={false} tick={AXIS} axisLine={false} tickLine={false} />
                <Tooltip {...TOOLTIP} labelFormatter={(w) => `Week of ${fmtDate(String(w))}`} />
                <Line type="monotone" dataKey="complaints" name="Complaints" stroke={SEAL} strokeWidth={2} dot={{ r: 4, fill: SEAL }} activeDot={{ r: 6 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Panel>

        <Panel title="Hotspots: places with repeat complaints" aside={<Source v="v_hotspots" />}>
          {/* Long place names read better as an HTML bar list than as chart axis labels. */}
          <ul className="space-y-2.5">
            {hotspots.map((h) => (
              <li key={h.label} className="grid grid-cols-[minmax(0,11rem)_minmax(0,1fr)_2rem] items-center gap-3 text-sm"
                title={`${h.complaints} complaints, ${h.last_30_days} in the last 30 days`}>
                <span className="truncate text-ink">{h.unit} <span className="text-ink-faint">{h.domain}</span></span>
                <span className="h-2.5 overflow-hidden rounded-r bg-paper" aria-hidden>
                  <span className="block h-full rounded-r" style={{ width: `${(100 * h.complaints) / maxHot}%`, background: SEAL }} />
                </span>
                <span className="text-right tabular-nums text-ink-soft">{h.complaints}</span>
              </li>
            ))}
          </ul>
        </Panel>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <Panel title="Offices: how fast they resolve" aside={<Source v="v_resolution_by_office" />}>
          <Table head={["Rank", "Office", "Complaints", "Resolved", "Avg hours", "Escalated"]}
            rows={[...a.by_office].sort((x, y) => x.speed_rank - y.speed_rank).map((o) => [
              o.avg_hours_to_resolve === null ? "–" : `#${o.speed_rank}`, o.office, o.complaints, o.resolved,
              o.avg_hours_to_resolve ?? "–", o.escalated ? <span className="text-high">{o.escalated}</span> : 0,
            ])} />
        </Panel>

        <Panel title="AI accuracy by category" aside={<Source v="v_ai_accuracy" />}>
          <Table head={["Final category", "Triaged", "AI right", "Accuracy", "Checked by a person"]}
            rows={a.ai_accuracy.map((r) => [r.final_category, r.triaged, r.ai_correct, <Meter key="m" pct={Number(r.accuracy_pct)} />, r.human_reviewed])} />
        </Panel>

        <Panel title="Deadline breaches by area" aside={<Source v="v_sla_breaches" />}>
          <Table head={["Area", "Complaints", "Breached", "Escalated share"]}
            rows={a.sla_breaches.map((r) => [r.domain, r.total, r.breached, <Meter key="m" pct={Number(r.breach_pct)} bad />])} />
        </Panel>

        <Panel title="Categories needing most follow-up questions" aside={<Source v="v_clarification_stats" />}>
          <Table head={["Category", "Complaints", "Needed questions", "Share"]}
            rows={a.clarifications.map((r) => [r.category, r.complaints, r.needed_clarification, <Meter key="m" pct={Number(r.pct)} />])} />
        </Panel>
      </div>
    </>
  );
}

function Stat({ label, value, tone }: { label: string; value: ReactNode; tone?: string }) {
  return (
    <div className="bg-white px-5 py-4">
      <div className="text-xs text-ink-soft">{label}</div>
      <div className={cx("mt-1 text-2xl font-semibold tabular-nums text-ink", tone)}>{value}</div>
    </div>
  );
}

function Source({ v }: { v: string }) {
  return <code className="text-2xs text-ink-faint">{v}</code>;
}

/** A small percentage bar with the number next to it (never colour alone). */
function Meter({ pct, bad }: { pct: number; bad?: boolean }) {
  return (
    <span className="flex items-center gap-2">
      <span className="h-1.5 w-16 overflow-hidden rounded-full bg-paper" aria-hidden>
        <span className={cx("block h-full rounded-full", bad ? "bg-high" : "bg-seal")} style={{ width: `${Math.min(100, pct)}%` }} />
      </span>
      <span className="tabular-nums">{pct}%</span>
    </span>
  );
}

function Table({ head, rows }: { head: string[]; rows: ReactNode[][] }) {
  if (rows.length === 0) return <p className="text-sm text-ink-soft">No data yet.</p>;
  return (
    <div className="-mx-5 overflow-x-auto px-5">
      <table className="w-full text-sm">
        <thead><tr className="text-left text-xs text-ink-soft">{head.map((h) => <th key={h} className="pb-2 pr-3 font-medium">{h}</th>)}</tr></thead>
        <tbody className="divide-y divide-line">
          {rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j} className={cx("py-2 pr-3", j === 0 || j === 1 ? "text-ink" : "tabular-nums text-ink-soft")}>{c}</td>)}</tr>)}
        </tbody>
      </table>
    </div>
  );
}
