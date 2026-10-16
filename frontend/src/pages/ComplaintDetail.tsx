import { useState, type ReactNode } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Lock, ShieldOff } from "lucide-react";
import { api, ApiError } from "../api/client";
import type { ComplaintPage, Hidden } from "../api/types";
import {
  Button, ConfidentialTag, DeadlineText, ErrorNote, Field, HiddenByDb, Panel, PriorityMark,
  Spinner, Stars, StatusBadge, cx, inputClass,
} from "../components/ui";
import { CONFLICT_LABELS, OUTCOME_LABELS, fieldLabel, fmtDateTime, relative } from "../lib/format";
import { useAuth } from "../lib/auth";
import { useClock } from "../lib/clock";
import { useAsync } from "../lib/useAsync";
import Timeline from "../components/Timeline";

const isHidden = (x: unknown): x is Hidden => x === "hidden";

export default function ComplaintDetail() {
  const { id } = useParams();
  const clock = useClock();
  const page = useAsync(() => api<ComplaintPage>(`/complaints/${id}`), [id, clock.version]);

  if (page.loading && !page.data) return <Spinner />;
  if (page.error) {
    return (
      <div className="max-w-xl">
        <BackLink />
        <div className="mt-4"><ErrorNote error={page.error} /></div>
        {page.error.status === 403 && (
          <p className="mt-3 text-sm text-ink-soft">
            Row-level security decided you may not open complaint #{id}. Nothing about it was sent to your browser.
          </p>
        )}
      </div>
    );
  }
  const p = page.data!;
  const c = p.complaint;

  return (
    <>
      <BackLink />
      <header className="mb-6 mt-3">
        <div className="flex flex-wrap items-center gap-2">
          <StatusBadge status={c.status} />
          <PriorityMark priority={c.priority} />
          <ConfidentialTag visibility={c.visibility} />
          {c.sensitivity === "Sensitive" && <span className="text-xs text-veil">Sensitive category</span>}
        </div>
        <h1 className="mt-2 text-[1.65rem] font-semibold leading-tight text-ink">
          <span className="text-ink-faint">#{c.complaint_id}</span> {c.category ?? "Waiting for triage"}
        </h1>
        <p className="mt-1 text-sm text-ink-soft">
          Filed {fmtDateTime(c.filed_at)}{c.unit && `, ${c.unit}`}
          {c.reopened_from && <>, reopened from <Link className="text-seal underline" to={`/c/${c.reopened_from}`}>#{c.reopened_from}</Link></>}
          {p.reopened_as && <>, reopened as <Link className="text-seal underline" to={`/c/${p.reopened_as}`}>#{p.reopened_as}</Link></>}
        </p>
        {p.access_logged && (
          <p className="mt-2 inline-flex items-center gap-1.5 text-xs text-veil">
            <Lock className="h-3.5 w-3.5" aria-hidden /> Your opening of this confidential complaint was recorded in the access log.
          </p>
        )}
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div className="space-y-6">
          <Panel title="Complaint">
            <p className="whitespace-pre-line text-[15px] leading-relaxed text-ink">{c.description}</p>
            {c.ai_summary && <p className="mt-3 border-t border-line pt-3 text-sm text-ink-soft">Summary: {c.ai_summary}</p>}
            {c.resolution_outcome && (
              <div className="mt-4 rounded-md bg-paper px-4 py-3 text-sm">
                <span className="font-medium text-ink">{OUTCOME_LABELS[c.resolution_outcome] ?? c.resolution_outcome}.</span>{" "}
                <span className="text-ink-soft">{c.resolution_note}</span>
                {c.feedback_rating && <div className="mt-2"><Stars value={c.feedback_rating} /></div>}
              </div>
            )}
          </Panel>

          <Actions page={p} reload={page.reload} />

          {!isHidden(p.disputes) && p.disputes.length > 0 && <Disputes page={p} reload={page.reload} />}

          <Panel title="Timeline">
            {isHidden(p.timeline) ? <HiddenByDb what="The history" /> : <Timeline items={p.timeline} />}
          </Panel>
        </div>

        <div className="space-y-6">
          <Panel title="Routing">
            <dl className="space-y-3 text-sm">
              <Row label="Handled by">{c.assigned_committee ?? c.assigned_person ?? "Not routed yet"}</Row>
              <Row label="Deadline">
                {c.due_at ? <><DeadlineText state={c.deadline_state} due={c.due_at} />
                  {c.deadline_state !== "Done" && <span className="text-ink-soft"> ({relative(c.due_at, clock.now)})</span>}</> : "–"}
              </Row>
              {c.routing_reason && <Row label="Why">{c.routing_reason}</Row>}
            </dl>
            {isHidden(p.exclusions) ? null : p.exclusions.length > 0 && (
              <div className="mt-4 border-t border-line pt-3">
                <p className="mb-2 flex items-center gap-1.5 text-sm font-medium text-ink">
                  <ShieldOff className="h-4 w-4 text-ink-soft" aria-hidden /> Kept away (conflict of interest)
                </p>
                <ul className="space-y-1.5 text-sm">
                  {p.exclusions.map((e, i) => (
                    <li key={i}><span className="font-medium text-ink">{e.person}</span>{" "}
                      <span className="text-ink-soft">{CONFLICT_LABELS[e.reason_code] ?? e.reason}</span></li>
                  ))}
                </ul>
              </div>
            )}
            {!isHidden(p.routing) && p.routing.length > 1 && (
              <details className="mt-4 border-t border-line pt-3 text-sm">
                <summary className="cursor-pointer text-ink-soft">All {p.routing.length} routing decisions</summary>
                <ol className="mt-2 space-y-2">
                  {p.routing.map((r) => (
                    <li key={r.decision_id}>
                      <span className="font-medium text-ink">{r.decision_type}</span>{" "}
                      <span className="text-ink-soft">to {r.committee ?? r.assigned_person}, {fmtDateTime(r.decided_at)}</span>
                    </li>
                  ))}
                </ol>
              </details>
            )}
          </Panel>

          <Panel title="Details">
            {isHidden(p.details) ? <HiddenByDb what="The details" /> : p.details.length === 0
              ? <p className="text-sm text-ink-soft">None recorded.</p> : (
              <dl className="space-y-2.5 text-sm">
                {p.details.map((d) => (
                  <Row key={d.field_name} label={fieldLabel(d.field_name)}>
                    {d.value} <span className="text-xs text-ink-faint">
                      {d.source === "Profile" ? "from profile" : d.source === "AI" ? "found by AI" : d.source === "User" ? "given by complainant" : ""}</span>
                  </Row>
                ))}
              </dl>
            )}
          </Panel>

          <Panel title="People">
            <div className="space-y-3 text-sm">
              <div>
                <p className="text-xs text-ink-soft">Filed by</p>
                {isHidden(p.identity) ? <HiddenByDb what="The complainant's identity" />
                  : p.identity ? <p className="text-ink">{p.identity.name}{!p.identity.contact_consent && <span className="text-ink-soft"> (does not want to be contacted)</span>}</p>
                  : <p className="flex items-center gap-1.5 text-veil"><Lock className="h-3.5 w-3.5" /> Withheld: anonymous or confidential.</p>}
              </div>
              {isHidden(p.parties) ? <HiddenByDb what="The people named" /> : p.parties.map((x) => (
                <div key={x.party_no}>
                  <p className="text-xs text-ink-soft">{x.party_role === "Respondent" ? "Complaint is about" : "Witness"}</p>
                  <p className="text-ink">{x.name ?? x.description ?? "Not named"} <span className="text-ink-soft">({x.stated_role === "Unknown" ? "role not known" : x.stated_role})</span></p>
                </div>
              ))}
            </div>
          </Panel>

          {!isHidden(p.ai) && p.ai && (
            <Panel title="AI triage">
              <dl className="space-y-2.5 text-sm">
                <Row label="Suggested">{p.ai.suggested_category ?? "No category"}</Row>
                <Row label="Confidence">{Math.round(p.ai.confidence * 100)}%</Row>
                <Row label="Urgency">{p.ai.urgency}</Row>
                {p.ai.reviewed_by && <Row label="Checked by">{p.ai.reviewed_by}</Row>}
              </dl>
            </Panel>
          )}

          {!isHidden(p.appeals) && p.appeals.length > 0 && (
            <Panel title="Appeal">
              {p.appeals.map((a) => (
                <div key={a.appeal_id} className="text-sm">
                  <p className="text-ink">{a.grounds}</p>
                  <p className="mt-1 text-ink-soft">Heard by {a.heard_by}. {a.status === "Pending" ? "Waiting for a decision." : `${a.status}: ${a.outcome}`}</p>
                </div>
              ))}
            </Panel>
          )}
        </div>
      </div>
    </>
  );
}

function BackLink() {
  return (
    <button onClick={() => history.back()} className="inline-flex items-center gap-1.5 text-sm text-ink-soft hover:text-ink">
      <ArrowLeft className="h-4 w-4" aria-hidden /> Back
    </button>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[7.5rem_minmax(0,1fr)] gap-3">
      <dt className="text-ink-soft">{label}</dt><dd className="text-ink">{children}</dd>
    </div>
  );
}

/** Runs an action and reloads the page; shows PostgreSQL's message on failure. */
function useAction(reload: () => Promise<void>) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const run = async (f: () => Promise<unknown>) => {
    setBusy(true); setError(null);
    try { await f(); await reload(); return true; }
    catch (e) { setError(e as ApiError); return false; }
    finally { setBusy(false); }
  };
  return { busy, error, run };
}

// ------------------------------------------------------------------ actions
function Actions({ page, reload }: { page: ComplaintPage; reload: () => Promise<void> }) {
  const { me } = useAuth();
  const c = page.complaint;
  const { busy, error, run } = useAction(reload);
  const [answer, setAnswer] = useState<Record<number, string>>({});
  const [note, setNote] = useState("");
  const [outcome, setOutcome] = useState("Fixed");
  const [question, setQuestion] = useState("");
  const [rating, setRating] = useState(0);
  const [reason, setReason] = useState("");
  const [mode, setMode] = useState<"none" | "resolve" | "ask" | "reopen" | "appeal">("none");

  const openQuestions = Array.isArray(page.clarifications) ? page.clarifications.filter((q) => !q.answer) : [];
  const isReevaluation = Array.isArray(page.disputes) && page.disputes.length > 0;
  const canHandle = (page.me.is_handler || page.me.is_committee) && me?.role !== "sunwai_student";
  const sections: ReactNode[] = [];

  // ---- complainant: answer questions
  if (page.me.is_complainant && openQuestions.length > 0) {
    sections.push(
      <div key="answers" className="space-y-4">
        <p className="text-sm text-ink">
          {openQuestions.length === 1 ? "One question needs" : `${openQuestions.length} questions need`} your answer.
          The deadline is paused until you reply.
        </p>
        {openQuestions.map((q) => (
          <form key={q.seq_no} className="flex flex-col gap-2 sm:flex-row sm:items-end"
            onSubmit={(e) => { e.preventDefault(); void run(() => api(`/complaints/${c.complaint_id}/answers`, { body: { seq_no: q.seq_no, answer: answer[q.seq_no] ?? "" } })); }}>
            <Field label={q.question} hint={q.asked_by === "Handler" ? "Asked by the office handling it" : undefined}>
              <input required value={answer[q.seq_no] ?? ""} onChange={(e) => setAnswer((a) => ({ ...a, [q.seq_no]: e.target.value }))} className={inputClass} />
            </Field>
            <Button type="submit" busy={busy}>Send answer</Button>
          </form>
        ))}
      </div>);
  }

  // ---- complainant: rate / reopen / appeal
  if (page.me.is_complainant && c.status === "Resolved") {
    sections.push(
      <div key="rate">
        <p className="mb-2 text-sm text-ink">Was it sorted out? Rate it to close the complaint.</p>
        <div className="flex flex-wrap items-center gap-3">
          <Stars value={rating} onChange={setRating} />
          <Button disabled={!rating} busy={busy} onClick={() => run(() => api(`/complaints/${c.complaint_id}/rate`, { body: { rating } }))}>Rate and close</Button>
        </div>
      </div>);
  }
  if (page.me.is_complainant && ["Resolved", "Closed", "Rejected"].includes(c.status) && !page.reopened_as) {
    sections.push(
      <div key="more" className="flex flex-wrap gap-2">
        {c.status !== "Rejected" && <Button variant="secondary" onClick={() => setMode("reopen")}>Problem is back: reopen</Button>}
        {(c.status === "Resolved" || c.status === "Rejected") && <Button variant="secondary" onClick={() => setMode("appeal")}>Appeal to the Ombudsperson</Button>}
      </div>);
  }

  // ---- handler / committee
  if (canHandle && !isReevaluation && ["Assigned", "Escalated", "InProgress"].includes(c.status)) {
    sections.push(
      <div key="handle" className="flex flex-wrap gap-2">
        {c.status !== "InProgress" && (
          <Button busy={busy} onClick={() => run(() => api(`/complaints/${c.complaint_id}/status`, { method: "PATCH", body: { status: "InProgress", note: "Work started" } }))}>Start working on it</Button>
        )}
        {c.status === "InProgress" && <Button onClick={() => setMode("resolve")}>Mark resolved</Button>}
        <Button variant="secondary" onClick={() => setMode("ask")}>Ask the complainant</Button>
      </div>);
  }

  if (mode === "resolve") {
    sections.push(
      <form key="resolve-form" className="space-y-3 border-t border-line pt-4" onSubmit={(e) => {
        e.preventDefault();
        void run(() => api(`/complaints/${c.complaint_id}/status`, { method: "PATCH",
          body: { status: outcome === "Reject" ? "Rejected" : "Resolved", resolution_outcome: outcome === "Reject" ? "Dismissed" : outcome, resolution_note: note } }))
          .then((ok) => ok && setMode("none"));
      }}>
        <Field label="Outcome">
          <select value={outcome} onChange={(e) => setOutcome(e.target.value)} className={inputClass}>
            <option value="Fixed">Fixed</option>
            <option value="ActionTaken">Action taken</option>
            <option value="Upheld">Complaint upheld</option>
            <option value="Dismissed">Dismissed (resolved, nothing to do)</option>
            <option value="Reject">Reject the complaint</option>
          </select>
        </Field>
        <Field label="What was done" hint="The complainant sees this.">
          <textarea required value={note} onChange={(e) => setNote(e.target.value)} rows={3} className={inputClass} />
        </Field>
        <div className="flex gap-2"><Button type="submit" busy={busy}>Save</Button><Button type="button" variant="ghost" onClick={() => setMode("none")}>Cancel</Button></div>
      </form>);
  }
  if (mode === "ask") {
    sections.push(
      <form key="ask-form" className="space-y-3 border-t border-line pt-4" onSubmit={(e) => {
        e.preventDefault();
        void run(() => api(`/complaints/${c.complaint_id}/request-info`, { body: { text: question } })).then((ok) => { if (ok) { setMode("none"); setQuestion(""); } });
      }}>
        <Field label="Your question" hint="The deadline pauses until the complainant replies.">
          <input required minLength={3} value={question} onChange={(e) => setQuestion(e.target.value)} className={inputClass} />
        </Field>
        <div className="flex gap-2"><Button type="submit" busy={busy}>Send question</Button><Button type="button" variant="ghost" onClick={() => setMode("none")}>Cancel</Button></div>
      </form>);
  }
  if (mode === "reopen" || mode === "appeal") {
    sections.push(
      <form key="reason-form" className="space-y-3 border-t border-line pt-4" onSubmit={(e) => {
        e.preventDefault();
        void run(() => api(`/complaints/${c.complaint_id}/${mode}`, { body: { text: reason } })).then((ok) => { if (ok) { setMode("none"); setReason(""); } });
      }}>
        <Field label={mode === "reopen" ? "What's wrong again?" : "Why do you disagree with the decision?"}
          hint={mode === "reopen" ? "A complaint can be reopened once, within 7 days of being resolved." : "The Ombudsperson will review the decision."}>
          <textarea required minLength={3} value={reason} onChange={(e) => setReason(e.target.value)} rows={3} className={inputClass} />
        </Field>
        <div className="flex gap-2">
          <Button type="submit" busy={busy}>{mode === "reopen" ? "Reopen complaint" : "File appeal"}</Button>
          <Button type="button" variant="ghost" onClick={() => setMode("none")}>Cancel</Button>
        </div>
      </form>);
  }

  if (me?.role === "sunwai_triage" && c.status === "Filed") {
    sections.push(<p key="triage" className="text-sm text-ink">Confirm the category in the <Link className="text-seal underline" to="/triage">triage queue</Link>.</p>);
  }

  if (sections.length === 0 && !error) return null;
  return (
    <Panel title="What you can do">
      <div className="space-y-4">
        {sections}
        <ErrorNote error={error} />
      </div>
    </Panel>
  );
}

// ------------------------------------------------------------------ re-evaluation
function Disputes({ page, reload }: { page: ComplaintPage; reload: () => Promise<void> }) {
  const disputes = Array.isArray(page.disputes) ? page.disputes : [];
  const changes = Array.isArray(page.marks_changes) ? page.marks_changes : [];
  const canDecide = page.me.is_handler && !["Resolved", "Closed"].includes(page.complaint.status);
  const { busy, error, run } = useAction(reload);
  const [revised, setRevised] = useState<Record<number, string>>({});

  return (
    <Panel title="Questions disputed" aside={<span className="text-xs text-ink-soft">Reviewer is never the original evaluator</span>}>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead><tr className="text-left text-xs text-ink-soft">
            <th className="pb-2 font-medium">Q</th><th className="pb-2 font-medium">Given</th><th className="pb-2 font-medium">Claimed</th>
            <th className="pb-2 font-medium">Reason</th><th className="pb-2 font-medium">Decision</th>
          </tr></thead>
          <tbody className="divide-y divide-line">
            {disputes.map((d) => (
              <tr key={d.question_no} className="align-top">
                <td className="py-2 pr-4 font-medium text-ink">{d.question_no}</td>
                <td className="py-2 pr-4 tabular-nums">{Number(d.marks_awarded)}</td>
                <td className="py-2 pr-4 tabular-nums">{Number(d.marks_claimed)}</td>
                <td className="py-2 pr-4 text-ink-soft">{d.student_reason}</td>
                <td className="py-2">
                  {d.reviewer_decision ? (
                    <span className={cx(d.reviewer_decision === "Rejected" ? "text-ink-soft" : "font-medium text-seal")}>
                      {d.reviewer_decision} → {Number(d.revised_marks)}
                    </span>
                  ) : canDecide ? (
                    <div className="flex flex-wrap items-center gap-1.5">
                      <input aria-label={`New marks for question ${d.question_no}`} type="number" step="0.5" min="0"
                        value={revised[d.question_no] ?? ""} onChange={(e) => setRevised((r) => ({ ...r, [d.question_no]: e.target.value }))}
                        placeholder={String(Number(d.marks_claimed))} className={cx(inputClass, "w-20 py-1")} />
                      <Button className="px-2 py-1 text-xs" busy={busy} onClick={() => {
                        const v = Number(revised[d.question_no] || d.marks_claimed);
                        void run(() => api(`/reevaluations/${page.complaint.complaint_id}/decide`, { body: {
                          question_no: d.question_no, decision: v >= Number(d.marks_claimed) ? "Accepted" : "Partial", revised_marks: v } }));
                      }}>Change marks</Button>
                      <Button variant="secondary" className="px-2 py-1 text-xs" busy={busy} onClick={() =>
                        run(() => api(`/reevaluations/${page.complaint.complaint_id}/decide`, { body: { question_no: d.question_no, decision: "Rejected" } }))}>Keep marks</Button>
                    </div>
                  ) : <span className="text-ink-faint">Waiting</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ErrorNote error={error} />
      {changes.length > 0 && (
        <div className="mt-4 border-t border-line pt-3 text-sm">
          <p className="mb-1 font-medium text-ink">Mark-change log <span className="font-normal text-ink-soft">(permanent; nobody can edit it)</span></p>
          {changes.map((m, i) => (
            <p key={i} className="text-ink-soft">Q{m.question_no}: {Number(m.old_marks)} → {Number(m.new_marks)} by {m.changed_by}, {fmtDateTime(m.changed_at)}</p>
          ))}
        </div>
      )}
    </Panel>
  );
}
