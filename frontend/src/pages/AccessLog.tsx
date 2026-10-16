import { Link } from "react-router-dom";
import { api } from "../api/client";
import { Empty, ErrorNote, PageHeader, Panel, Spinner } from "../components/ui";
import { fmtDateTime } from "../lib/format";
import { useAsync } from "../lib/useAsync";

interface Row { log_id: number; complaint_id: number; accessed_by: string | null; db_role: string; action: string; accessed_at: string }

/** Who opened which confidential complaint. Append-only: no role can edit or delete it. */
export default function AccessLog() {
  const { data, error, loading } = useAsync(() => api<Row[]>("/admin/access-log"));
  return (
    <>
      <PageHeader title="Access log"
        subtitle="Every opening of a confidential or sensitive complaint, recorded by the database. Rows can be added but never changed or deleted, not even by the administrator." />
      <ErrorNote error={error} />
      {loading ? <Spinner /> : (
        <Panel>
          {data?.length === 0 ? <Empty>No confidential complaint has been opened yet.</Empty> : (
            <div className="-mx-5 overflow-x-auto px-5">
              <table className="w-full text-sm">
                <thead><tr className="text-left text-xs text-ink-soft">
                  <th className="pb-2 font-medium">When</th><th className="pb-2 font-medium">Who</th>
                  <th className="pb-2 font-medium">Database role</th><th className="pb-2 font-medium">Complaint</th>
                </tr></thead>
                <tbody className="divide-y divide-line">
                  {data?.map((r) => (
                    <tr key={r.log_id}>
                      <td className="py-2 text-ink-soft">{fmtDateTime(r.accessed_at)}</td>
                      <td className="py-2 text-ink">{r.accessed_by ?? "System"}</td>
                      <td className="py-2"><code className="text-[13px] text-ink-soft">{r.db_role}</code></td>
                      <td className="py-2"><span className="text-ink-soft">#{r.complaint_id}</span>{" "}
                        <span className="text-xs text-ink-faint">(content hidden from you)</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Panel>
      )}
      <p className="mt-3 text-xs text-ink-soft">Tip: log in as the ICC chair, open the harassment case, then come back here.</p>
      <Link to="/security" className="text-xs text-seal underline">Try deleting this log in the security demo</Link>
    </>
  );
}
