import { Link } from "react-router-dom";
import { api } from "../api/client";
import type { MyComplaint } from "../api/types";
import { ComplaintTable } from "../components/ComplaintTable";
import { Button, ConfidentialTag, DeadlineText, ErrorNote, PageHeader, PriorityMark, Spinner, StatusBadge } from "../components/ui";
import { fmtDate } from "../lib/format";
import { useAsync } from "../lib/useAsync";

export default function MyComplaints() {
  const { data, error, loading } = useAsync(() => api<MyComplaint[]>("/complaints/mine"));
  const waiting = data?.filter((c) => c.open_questions > 0) ?? [];
  return (
    <>
      <PageHeader title="My complaints" subtitle="Everything you have filed, newest first."
        actions={<Link to="/file"><Button>File a complaint</Button></Link>} />
      <ErrorNote error={error} />
      {waiting.length > 0 && (
        <div className="mb-4 rounded-lg border border-medium/30 bg-medium-soft px-4 py-3 text-sm text-ink">
          {waiting.length === 1 ? "One complaint is" : `${waiting.length} complaints are`} waiting for your reply:{" "}
          {waiting.map((w, i) => (
            <span key={w.complaint_id}>{i > 0 && ", "}<Link to={`/c/${w.complaint_id}`} className="font-medium text-seal underline">#{w.complaint_id}</Link></span>
          ))}
        </div>
      )}
      {loading ? <Spinner /> : data && (
        <ComplaintTable rows={data} empty={<>Nothing filed yet. <Link to="/file" className="text-seal underline">File your first complaint</Link>.</>}
          columns={[
            { header: "Complaint", className: "w-[40%]", cell: (c) => (
              <div>
                <div className="font-medium text-ink">{c.category ?? "Waiting for triage"}</div>
                <div className="mt-0.5 line-clamp-1 text-xs text-ink-soft">{c.description}</div>
                <div className="mt-1"><ConfidentialTag visibility={c.visibility} /></div>
              </div>) },
            { header: "Status", cell: (c) => <StatusBadge status={c.status} /> },
            { header: "Priority", cell: (c) => <PriorityMark priority={c.priority} /> },
            { header: "With", cell: (c) => <span className="text-ink-soft">{c.handled_by ?? "–"}</span> },
            { header: "Deadline", cell: (c) => <DeadlineText state={c.deadline_state} due={c.due_at} /> },
            { header: "Filed", cell: (c) => <span className="text-ink-soft">{fmtDate(c.filed_at)}</span> },
          ]} />
      )}
    </>
  );
}
