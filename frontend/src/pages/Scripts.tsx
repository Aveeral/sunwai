import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Plus, Trash2 } from "lucide-react";
import { api, ApiError } from "../api/client";
import type { Script } from "../api/types";
import { Button, Empty, ErrorNote, PageHeader, Panel, Spinner, inputClass } from "../components/ui";
import { fmtDate } from "../lib/format";
import { useAsync } from "../lib/useAsync";

/** Exam module: my evaluated answer scripts, and question-wise re-evaluation requests. */
export default function Scripts() {
  const { data, error, loading } = useAsync(() => api<Script[]>("/scripts/mine"));
  const [open, setOpen] = useState<number | null>(null);
  return (
    <>
      <PageHeader title="Answer scripts"
        subtitle="Disagree with how a question was marked? Request a re-evaluation. An independent reviewer from the department checks it, never the teacher who marked it, and every mark change is logged permanently." />
      <ErrorNote error={error} />
      {loading ? <Spinner /> : data?.length === 0 ? <Panel><Empty>No evaluated scripts yet.</Empty></Panel> : (
        <div className="space-y-3">
          {data?.map((s) => (
            <Panel key={s.script_id}>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="font-medium text-ink">{s.course_code} {s.title}</p>
                  <p className="text-sm text-ink-soft">{s.exam_type === "MidSem" ? "Mid-semester" : "End-semester"} exam, {fmtDate(s.exam_date)}</p>
                </div>
                <div className="flex items-center gap-4">
                  <p className="text-right"><span className="text-xl font-semibold tabular-nums text-ink">{s.total_marks !== null ? Number(s.total_marks) : "–"}</span>
                    <span className="text-sm text-ink-soft"> / {s.max_marks}</span></p>
                  {s.reevaluation_id
                    ? <Link to={`/c/${s.reevaluation_id}`}><Button variant="secondary">View re-evaluation</Button></Link>
                    : <Button variant="secondary" onClick={() => setOpen(open === s.script_id ? null : s.script_id)}>Request re-evaluation</Button>}
                </div>
              </div>
              {open === s.script_id && <ReevaluationForm script={s} />}
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}

interface Row { question_no: string; marks_awarded: string; marks_claimed: string; reason: string }
const blank: Row = { question_no: "", marks_awarded: "", marks_claimed: "", reason: "" };

function ReevaluationForm({ script }: { script: Script }) {
  const navigate = useNavigate();
  const [rows, setRows] = useState<Row[]>([{ ...blank }]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const set = (i: number, k: keyof Row, v: string) => setRows((r) => r.map((x, j) => (j === i ? { ...x, [k]: v } : x)));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setError(null);
    try {
      const r = await api<{ complaint_id: number }>("/reevaluations", { body: {
        script_id: script.script_id,
        disputes: rows.map((x) => ({ question_no: Number(x.question_no), marks_awarded: Number(x.marks_awarded),
          marks_claimed: Number(x.marks_claimed), reason: x.reason })) } });
      navigate(`/c/${r.complaint_id}`);
    } catch (err) { setError(err as ApiError); }
    finally { setBusy(false); }
  };

  return (
    <form onSubmit={submit} className="mt-4 space-y-3 border-t border-line pt-4">
      <p className="text-sm font-medium text-ink">Which questions?</p>
      {rows.map((r, i) => (
        <div key={i} className="grid grid-cols-[4rem_5rem_5rem_minmax(0,1fr)_auto] items-end gap-2">
          <label className="text-xs text-ink-soft">Q no.<input required type="number" min="1" value={r.question_no} onChange={(e) => set(i, "question_no", e.target.value)} className={inputClass} /></label>
          <label className="text-xs text-ink-soft">Given<input required type="number" step="0.5" min="0" value={r.marks_awarded} onChange={(e) => set(i, "marks_awarded", e.target.value)} className={inputClass} /></label>
          <label className="text-xs text-ink-soft">Expected<input required type="number" step="0.5" min="0" value={r.marks_claimed} onChange={(e) => set(i, "marks_claimed", e.target.value)} className={inputClass} /></label>
          <label className="text-xs text-ink-soft">Why<input required minLength={3} value={r.reason} onChange={(e) => set(i, "reason", e.target.value)} placeholder="e.g. step marks not given" className={inputClass} /></label>
          <button type="button" aria-label="Remove question" disabled={rows.length === 1}
            onClick={() => setRows((x) => x.filter((_, j) => j !== i))} className="mb-2 text-ink-faint hover:text-high disabled:opacity-30">
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      ))}
      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="ghost" onClick={() => setRows((r) => [...r, { ...blank }])}><Plus className="h-4 w-4" /> Add a question</Button>
        <Button type="submit" busy={busy}>Send request</Button>
      </div>
      <ErrorNote error={error} />
    </form>
  );
}
