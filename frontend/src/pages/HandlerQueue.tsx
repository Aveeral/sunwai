import { api } from "../api/client";
import type { QueueRow } from "../api/types";
import { ComplaintTable } from "../components/ComplaintTable";
import { DeadlineText, ErrorNote, PageHeader, PriorityMark, Spinner, StatusBadge } from "../components/ui";
import { relative } from "../lib/format";
import { useClock } from "../lib/clock";
import { useAsync } from "../lib/useAsync";

/** Open complaints assigned to me (v_handler_queue): overdue first, then priority. */
export default function HandlerQueue() {
  const clock = useClock();
  const { data, error, loading } = useAsync(() => api<QueueRow[]>("/handler/queue"), [clock.version]);
  const overdue = data?.filter((r) => r.deadline_state === "Overdue").length ?? 0;
  return (
    <>
      <PageHeader title="My queue"
        subtitle={data ? `${data.length} open ${data.length === 1 ? "complaint" : "complaints"}${overdue ? `, ${overdue} overdue` : ""}. Overdue ones escalate to your superior automatically.` : undefined} />
      <ErrorNote error={error} />
      {loading && !data ? <Spinner /> : data && (
        <ComplaintTable rows={data} empty="Nothing waiting for you."
          columns={[
            { header: "Complaint", className: "w-[38%]", cell: (r) => (
              <div>
                <div className="font-medium text-ink">{r.category}</div>
                <div className="mt-0.5 line-clamp-2 text-xs text-ink-soft">{r.ai_summary}</div>
              </div>) },
            { header: "Where", cell: (r) => <span className="text-ink-soft">{r.location_text ?? r.unit ?? "–"}</span> },
            { header: "Priority", cell: (r) => <PriorityMark priority={r.priority} /> },
            { header: "Status", cell: (r) => <StatusBadge status={r.status} /> },
            { header: "Deadline", cell: (r) => (
              <div><DeadlineText state={r.deadline_state} due={r.due_at} />
                <div className="text-xs text-ink-faint">{relative(r.due_at, clock.now)}</div></div>) },
          ]} />
      )}
    </>
  );
}
