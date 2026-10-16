import { useState } from "react";
import { Link } from "react-router-dom";
import { api, ApiError } from "../api/client";
import type { Category, TriageRow } from "../api/types";
import { Button, ConfidentialTag, Empty, ErrorNote, PageHeader, Panel, Spinner, inputClass } from "../components/ui";
import { fmtDateTime } from "../lib/format";
import { useAsync } from "../lib/useAsync";

/** Complaints the AI wasn't sure about (confidence < 0.70 or General/Other).
 *  The officer confirms or corrects the category; the database then routes it. */
export default function TriageQueue() {
  const queue = useAsync(() => api<TriageRow[]>("/triage/queue"));
  const cats = useAsync(() => api<Category[]>("/categories"));
  return (
    <>
      <PageHeader title="Triage queue"
        subtitle="Complaints the AI could not place with confidence. Your choice is stored next to the AI's guess, which is how the dashboard measures AI accuracy." />
      <ErrorNote error={queue.error} />
      {queue.loading && !queue.data ? <Spinner /> : queue.data?.length === 0 ? <Panel><Empty>The queue is empty.</Empty></Panel> : (
        <div className="space-y-4">
          {queue.data?.map((r) => (
            <TriageCard key={r.complaint_id} row={r} categories={cats.data ?? []} onDone={queue.reload} />
          ))}
        </div>
      )}
    </>
  );
}

function TriageCard({ row, categories, onDone }: { row: TriageRow; categories: Category[]; onDone: () => Promise<void> }) {
  const [cat, setCat] = useState<number | "">(row.suggested_category_id && row.suggested_category_id !== 15 ? row.suggested_category_id : "");
  const [priority, setPriority] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [result, setResult] = useState<string | null>(null);

  const confirm = async () => {
    setBusy(true); setError(null);
    try {
      const r = await api<{ result: string }>(`/triage/${row.complaint_id}/confirm`, { body: { category_id: cat, priority: priority || null } });
      setResult(r.result);
      setTimeout(() => void onDone(), 1200);
    } catch (e) { setError(e as ApiError); }
    finally { setBusy(false); }
  };

  return (
    <Panel>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 text-xs text-ink-soft">
            <Link to={`/c/${row.complaint_id}`} className="font-medium text-seal hover:underline">#{row.complaint_id}</Link>
            <span>{fmtDateTime(row.filed_at)}</span><ConfidentialTag visibility={row.visibility} />
          </div>
          <p className="mt-2 text-[15px] text-ink">{row.description}</p>
          <p className="mt-2 text-sm text-ink-soft">
            AI guess: <span className="text-ink">{row.ai_suggested_category ?? "none"}</span>
            {row.confidence !== null && <> at {Math.round(row.confidence * 100)}% confidence</>}
            {row.urgency && <>, urgency {row.urgency}</>}
          </p>
        </div>
      </div>
      {result ? (
        <p className="mt-4 text-sm font-medium text-seal" role="status">Confirmed. Result: {result === "Assigned" ? "routed" : result}.</p>
      ) : (
        <div className="mt-4 flex flex-wrap items-end gap-2 border-t border-line pt-4">
          <label className="min-w-[14rem] flex-1">
            <span className="mb-1 block text-xs text-ink-soft">Category</span>
            <select value={cat} onChange={(e) => setCat(Number(e.target.value))} className={inputClass}>
              <option value="" disabled>Choose a category</option>
              {categories.filter((c) => c.category_id !== 15).map((c) => <option key={c.category_id} value={c.category_id}>{c.name}</option>)}
            </select>
          </label>
          <label>
            <span className="mb-1 block text-xs text-ink-soft">Priority</span>
            <select value={priority} onChange={(e) => setPriority(e.target.value)} className={inputClass}>
              <option value="">Automatic</option><option>Low</option><option>Medium</option><option>High</option>
            </select>
          </label>
          <Button onClick={confirm} busy={busy} disabled={cat === ""}>Confirm and route</Button>
        </div>
      )}
      <div className="mt-3"><ErrorNote error={error} /></div>
    </Panel>
  );
}
