import type { ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { cx } from "./ui";

export interface Column<T> { header: string; cell: (row: T) => ReactNode; className?: string }

/** A table whose rows open the complaint. Rows are links for keyboard users too. */
export function ComplaintTable<T extends { complaint_id: number }>({ rows, columns, empty }: {
  rows: T[]; columns: Column<T>[]; empty: ReactNode;
}) {
  const navigate = useNavigate();
  if (rows.length === 0) return <p className="rounded-lg border border-line bg-white py-12 text-center text-sm text-ink-soft">{empty}</p>;
  return (
    <div className="overflow-x-auto rounded-lg border border-line bg-white">
      <table className="w-full min-w-[640px] text-sm">
        <thead>
          <tr className="border-b border-line text-left text-xs text-ink-soft">
            <th className="px-4 py-2.5 font-medium">#</th>
            {columns.map((c) => <th key={c.header} className={cx("px-4 py-2.5 font-medium", c.className)}>{c.header}</th>)}
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {rows.map((r) => (
            <tr key={r.complaint_id} tabIndex={0} role="link"
              onClick={() => navigate(`/c/${r.complaint_id}`)}
              onKeyDown={(e) => { if (e.key === "Enter") navigate(`/c/${r.complaint_id}`); }}
              className="cursor-pointer align-top hover:bg-paper focus-visible:bg-paper focus-visible:outline-none">
              <td className="px-4 py-3 tabular-nums text-ink-faint">{r.complaint_id}</td>
              {columns.map((c) => <td key={c.header} className={cx("px-4 py-3", c.className)}>{c.cell(r)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
