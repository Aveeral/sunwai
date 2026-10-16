import { useState } from "react";
import { Check, Database, Play, X } from "lucide-react";
import { api, ApiError } from "../api/client";
import type { Attempt, AttemptResult } from "../api/types";
import { Button, ErrorNote, PageHeader, Spinner, cx } from "../components/ui";
import { useAuth } from "../lib/auth";
import { useAsync } from "../lib/useAsync";

/** Runs fixed queries as the logged-in database role and shows PostgreSQL's
 *  answer. Nothing is kept: every attempt is rolled back on the server. */
export default function SecurityDemo() {
  const { me } = useAuth();
  const attempts = useAsync(() => api<Attempt[]>("/demo/attempts"));
  const [results, setResults] = useState<Record<string, AttemptResult>>({});
  const [running, setRunning] = useState<string | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  const run = async (action: string) => {
    setRunning(action); setError(null);
    try {
      const r = await api<AttemptResult>("/demo/try-access", { body: { action } });
      setResults((x) => ({ ...x, [action]: r }));
    } catch (e) { setError(e as ApiError); }
    finally { setRunning(null); }
  };
  const runAll = async () => { for (const a of attempts.data ?? []) await run(a.action); };

  return (
    <>
      <PageHeader title="Security demo"
        subtitle={<>Each button runs one fixed SQL statement as <strong className="text-ink">{me?.name}</strong> with the database role <code className="rounded bg-white px-1 text-[13px]">{me?.role}</code>. The answer comes straight from PostgreSQL, and nothing is saved. Switch person or role and run them again.</>}
        actions={<Button variant="secondary" onClick={runAll} busy={running !== null}><Play className="h-4 w-4" /> Run all</Button>} />
      <ErrorNote error={error ?? attempts.error} />
      {attempts.loading ? <Spinner /> : (
        <div className="overflow-hidden rounded-lg border border-line bg-white">
          <ul className="divide-y divide-line">
            {attempts.data?.map((a) => {
              const r = results[a.action];
              const stale = r && r.role !== me?.role;
              return (
                <li key={a.action} className="grid gap-3 px-5 py-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] md:items-start">
                  <div className="min-w-0">
                    <div className="flex items-center justify-between gap-3">
                      <p className="text-sm font-medium text-ink">{a.label}</p>
                      <Button variant="secondary" className="px-2.5 py-1 text-xs" busy={running === a.action} onClick={() => run(a.action)}>Try it</Button>
                    </div>
                    <pre className="mt-2 overflow-x-auto whitespace-pre-wrap rounded bg-paper px-3 py-2 font-mono text-[12.5px] leading-relaxed text-ink-soft">{a.sql}</pre>
                  </div>
                  <div className={cx("min-h-[3.5rem] rounded-md px-4 py-3 text-sm", !r ? "border border-dashed border-line text-ink-faint"
                    : r.allowed ? "bg-seal-soft" : "bg-veil-soft", stale && "opacity-50")}>
                    {!r ? "Not run yet." : (
                      <>
                        <p className={cx("flex items-center gap-1.5 text-xs font-semibold", r.allowed ? "text-seal" : "text-veil")}>
                          {r.allowed ? <Check className="h-3.5 w-3.5" /> : <X className="h-3.5 w-3.5" />}
                          {r.allowed ? "Allowed" : "Refused"} for {r.role}{stale && " (an earlier role)"}
                        </p>
                        {r.allowed
                          ? <p className="mt-1 text-ink">{describeRows(r)}</p>
                          : <p className="mt-1 flex items-start gap-1.5 font-mono text-[13px] text-ink">
                              <Database className="mt-0.5 h-3.5 w-3.5 shrink-0 text-veil" aria-hidden />{r.error}</p>}
                      </>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        </div>
      )}
      <p className="mt-4 max-w-3xl text-sm text-ink-soft">
        Three layers are at work: <strong className="text-ink">GRANT/REVOKE</strong> decides which tables, views and columns a role may touch;
        <strong className="text-ink"> row-level security</strong> decides which rows it sees (a student counting all complaints gets only their own);
        and <strong className="text-ink">triggers</strong> make history append-only even for the table's owner.
      </p>
    </>
  );
}

function describeRows(r: AttemptResult): string {
  const row = r.rows?.[0];
  if (row && "rows_visible" in row) return `Allowed, but row-level security shows only ${row.rows_visible} complaints.`;
  if (row && "log_rows" in row) return `${row.log_rows} rows in the audit log.`;
  if (r.rows) return `Returned ${r.rows.length} rows: row-level security keeps only the ones your role may see.`;
  return `${r.rowcount ?? 0} rows affected (rolled back).`;
}
