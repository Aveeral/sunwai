import { api } from "../api/client";
import type { Priority, Status } from "../api/types";
import { ComplaintTable } from "../components/ComplaintTable";
import { ErrorNote, PageHeader, PriorityMark, Spinner, Stars, StatusBadge } from "../components/ui";
import { OUTCOME_LABELS, fmtDate } from "../lib/format";
import { useAsync } from "../lib/useAsync";

interface Row {
  complaint_id: number; category: string; status: Status; priority: Priority; filed_at: string;
  resolved_at: string | null; resolution_outcome: string | null; feedback_rating: number | null; assigned_person: string | null;
}

export default function HandlerHistory() {
  const { data, error, loading } = useAsync(() => api<Row[]>("/handler/history"));
  return (
    <>
      <PageHeader title="Handled earlier" subtitle="Complaints you resolved, or that moved on from you (escalated or reassigned)." />
      <ErrorNote error={error} />
      {loading ? <Spinner /> : data && (
        <ComplaintTable rows={data} empty="Nothing here yet."
          columns={[
            { header: "Complaint", cell: (r) => <span className="font-medium text-ink">{r.category}</span> },
            { header: "Status", cell: (r) => <StatusBadge status={r.status} /> },
            { header: "Priority", cell: (r) => <PriorityMark priority={r.priority} /> },
            { header: "Outcome", cell: (r) => <span className="text-ink-soft">{r.resolution_outcome ? OUTCOME_LABELS[r.resolution_outcome] : `Now with ${r.assigned_person ?? "–"}`}</span> },
            { header: "Rating", cell: (r) => r.feedback_rating ? <Stars value={r.feedback_rating} /> : <span className="text-ink-faint">–</span> },
            { header: "Filed", cell: (r) => <span className="text-ink-soft">{fmtDate(r.filed_at)}</span> },
          ]} />
      )}
    </>
  );
}
