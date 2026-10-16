import { useState } from "react";
import { Link } from "react-router-dom";
import { api, ApiError } from "../api/client";
import type { AppealRow } from "../api/types";
import { Button, Empty, ErrorNote, Field, PageHeader, Panel, Spinner, cx, inputClass } from "../components/ui";
import { OUTCOME_LABELS, fmtDate } from "../lib/format";
import { useAsync } from "../lib/useAsync";

export default function Appeals() {
  const { data, error, loading, reload } = useAsync(() => api<AppealRow[]>("/appeals"));
  const pending = data?.filter((a) => a.status === "Pending") ?? [];
  const decided = data?.filter((a) => a.status !== "Pending") ?? [];
  return (
    <>
      <PageHeader title="Appeals" subtitle="Complainants who disagree with a decision appeal to you. Upholding sends the complaint back to its handler; dismissing closes it." />
      <ErrorNote error={error} />
      {loading && !data ? <Spinner /> : (
        <div className="space-y-4">
          {pending.length === 0 && <Panel><Empty>No appeals waiting.</Empty></Panel>}
          {pending.map((a) => <AppealCard key={a.appeal_id} a={a} onDone={reload} />)}
          {decided.length > 0 && (
            <Panel title="Decided">
              <ul className="divide-y divide-line text-sm">
                {decided.map((a) => (
                  <li key={a.appeal_id} className="py-2.5">
                    <Link to={`/c/${a.complaint_id}`} className="font-medium text-seal hover:underline">#{a.complaint_id}</Link>{" "}
                    <span className="text-ink">{a.category}</span>{" "}
                    <span className={cx("font-medium", a.status === "Upheld" ? "text-seal" : "text-ink-soft")}>{a.status}</span>
                    <span className="text-ink-soft">: {a.outcome}</span>
                  </li>
                ))}
              </ul>
            </Panel>
          )}
        </div>
      )}
    </>
  );
}

function AppealCard({ a, onDone }: { a: AppealRow; onDone: () => Promise<void> }) {
  const [outcome, setOutcome] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const decide = async (status: "Upheld" | "Dismissed") => {
    setBusy(true); setError(null);
    try { await api(`/appeals/${a.appeal_id}/decide`, { body: { status, outcome } }); await onDone(); }
    catch (e) { setError(e as ApiError); }
    finally { setBusy(false); }
  };
  return (
    <Panel title={<>Appeal on <Link to={`/c/${a.complaint_id}`} className="text-seal hover:underline">#{a.complaint_id}</Link>, {a.category}</>}
      aside={<span className="text-xs text-ink-soft">Filed {fmtDate(a.filed_on)}</span>}>
      <dl className="grid gap-3 text-sm sm:grid-cols-2">
        <div><dt className="text-ink-soft">Original decision</dt>
          <dd className="text-ink">{a.resolution_outcome ? OUTCOME_LABELS[a.resolution_outcome] : "–"} by {a.assigned_committee ?? a.assigned_person}</dd>
          <dd className="mt-1 text-ink-soft">{a.resolution_note}</dd></div>
        <div><dt className="text-ink-soft">Grounds for appeal</dt><dd className="text-ink">{a.grounds}</dd></div>
      </dl>
      <div className="mt-4 border-t border-line pt-4">
        <Field label="Your decision and reasons">
          <textarea value={outcome} onChange={(e) => setOutcome(e.target.value)} rows={2} className={inputClass} />
        </Field>
        <div className="mt-3 flex gap-2">
          <Button busy={busy} disabled={outcome.trim().length < 3} onClick={() => decide("Upheld")}>Uphold appeal</Button>
          <Button variant="secondary" busy={busy} disabled={outcome.trim().length < 3} onClick={() => decide("Dismissed")}>Dismiss appeal</Button>
        </div>
        <div className="mt-3"><ErrorNote error={error} /></div>
      </div>
    </Panel>
  );
}
