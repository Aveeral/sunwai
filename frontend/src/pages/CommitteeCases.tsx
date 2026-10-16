import { api } from "../api/client";
import type { CommitteeRow } from "../api/types";
import { ComplaintTable } from "../components/ComplaintTable";
import { DeadlineText, ErrorNote, PageHeader, PriorityMark, Spinner, StatusBadge } from "../components/ui";
import { fmtDate } from "../lib/format";
import { useAuth } from "../lib/auth";
import { useClock } from "../lib/clock";
import { useAsync } from "../lib/useAsync";

const VIEW: Record<string, string> = {
  sunwai_icc: "v_icc_cases", sunwai_antiragging: "v_antiragging_cases", sunwai_sgrc: "v_sgrc_cases",
};

/** The committee's own cases. Each committee role can read only its own view. */
export default function CommitteeCases() {
  const { me } = useAuth();
  const clock = useClock();
  const { data, error, loading } = useAsync(() => api<CommitteeRow[]>("/committee/cases"), [clock.version]);
  const name = data?.[0]?.committee ?? me?.role_label;
  return (
    <>
      <PageHeader title={name ? `${name} cases` : "Committee cases"}
        subtitle={<>Read from the view <code className="rounded bg-white px-1 text-[13px]">{VIEW[me?.role ?? ""] ?? "v_committee_cases"}</code>, which only your committee's role is granted.</>} />
      <ErrorNote error={error} />
      {loading && !data ? <Spinner /> : data && (
        <ComplaintTable rows={data} empty="No cases before the committee."
          columns={[
            { header: "Case", className: "w-[36%]", cell: (r) => (
              <div><div className="font-medium text-ink">{r.category}</div>
                <div className="mt-0.5 line-clamp-2 text-xs text-ink-soft">{r.ai_summary}</div></div>) },
            { header: "Status", cell: (r) => <StatusBadge status={r.status} /> },
            { header: "Priority", cell: (r) => <PriorityMark priority={r.priority} /> },
            { header: "Recused", cell: (r) => <span className="text-xs text-ink-soft">{r.recused_members ?? "None"}</span> },
            { header: "Deadline", cell: (r) => <DeadlineText state={r.deadline_state} due={r.due_at} /> },
            { header: "Filed", cell: (r) => <span className="text-ink-soft">{fmtDate(r.filed_at)}</span> },
          ]} />
      )}
    </>
  );
}
