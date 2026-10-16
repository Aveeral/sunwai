import { api } from "../api/client";
import type { Priority, Status } from "../api/types";
import { ComplaintTable } from "../components/ComplaintTable";
import { DeadlineText, ErrorNote, PageHeader, PriorityMark, Spinner, StatusBadge } from "../components/ui";
import { fmtDate } from "../lib/format";
import { useClock } from "../lib/clock";
import { useAsync } from "../lib/useAsync";

interface Row {
  complaint_id: number; category: string | null; domain: string | null; status: Status; priority: Priority | null;
  unit: string | null; filed_at: string; assigned_person: string | null; assigned_committee: string | null;
  deadline_state: string | null;
}

export default function AllComplaints() {
  const clock = useClock();
  const { data, error, loading } = useAsync(() => api<Row[]>("/admin/complaints"), [clock.version]);
  return (
    <>
      <PageHeader title="All complaints"
        subtitle="Every complaint the administrator may see. Row-level security removes harassment, ragging, discrimination and faculty-conduct cases from this list entirely." />
      <ErrorNote error={error} />
      {loading && !data ? <Spinner /> : data && (
        <ComplaintTable rows={data} empty="No complaints."
          columns={[
            { header: "Category", cell: (r) => <span className="font-medium text-ink">{r.category ?? "Waiting for triage"}</span> },
            { header: "Where", cell: (r) => <span className="text-ink-soft">{r.unit ?? "–"}</span> },
            { header: "Status", cell: (r) => <StatusBadge status={r.status} /> },
            { header: "Priority", cell: (r) => <PriorityMark priority={r.priority} /> },
            { header: "With", cell: (r) => <span className="text-ink-soft">{r.assigned_committee ?? r.assigned_person ?? "–"}</span> },
            { header: "Deadline", cell: (r) => <DeadlineText state={r.deadline_state} due={r.deadline_state ? "x" : null} /> },
            { header: "Filed", cell: (r) => <span className="text-ink-soft">{fmtDate(r.filed_at)}</span> },
          ]} />
      )}
    </>
  );
}
