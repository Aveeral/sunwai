import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { CheckCircle2, Circle, CircleAlert, Eye, Lock, Sparkles, UserRound } from "lucide-react";
import { api, ApiError } from "../api/client";
import type { Candidate, MyComplaint, Preview, PreviewPerson } from "../api/types";
import {
  Button, ErrorNote, Field, PageHeader, Panel, PriorityMark, StatusBadge, cx, inputClass,
} from "../components/ui";
import { fieldLabel } from "../lib/format";

const EXAMPLES = [
  "BH-3 washroom mein paani nahi aa raha since yesterday",
  "The projector in our classroom has not worked for a week",
  "Ram sir from DBMS keeps sending me inappropriate messages at night",
  "Wi-Fi in the library keeps disconnecting",
];

interface PersonChoice {
  personId: number | null; statedRole: PreviewPerson["stated_role"]; description: string;
  pickedName?: string;   // set when the person was chosen from the name search
}

export default function FileComplaint() {
  const [text, setText] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [analysing, setAnalysing] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const [details, setDetails] = useState<Record<string, string>>({});
  const [people, setPeople] = useState<PersonChoice[]>([]);
  const [visibility, setVisibility] = useState<"Public" | "Confidential" | "Anonymous">("Public");
  const [consent, setConsent] = useState(true);
  const [showRedacted, setShowRedacted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [filed, setFiled] = useState<{ complaint_id: number; result: string; complaint: MyComplaint } | null>(null);
  const lastSent = useRef("");

  // Analyse as the student types (after a pause), like the design doc's live checklist.
  useEffect(() => {
    const t = text.trim();
    if (t.length < 20 || t === lastSent.current) return;
    const timer = setTimeout(() => void analyse(t), 1200);
    return () => clearTimeout(timer);
  }, [text]);

  async function analyse(t: string) {
    lastSent.current = t;
    setAnalysing(true); setError(null);
    try {
      const p = await api<Preview>("/triage/preview", { body: { description: t } });
      setPreview(p);
      setPeople(p.people.map((x) => ({
        personId: null, statedRole: x.stated_role, description: x.name ?? x.description ?? "",
      })));
      if (p.sensitive) setVisibility((v) => (v === "Public" ? "Confidential" : v));
      else if (!p.anonymous_allowed) setVisibility((v) => (v === "Anonymous" ? "Public" : v));
    } catch (e) { setError(e as ApiError); }
    finally { setAnalysing(false); }
  }

  const missing = useMemo(() => preview?.checklist.filter(
    (c) => c.mandatory && !c.value && !details[c.field]?.trim()
      && !(c.field === "respondent_role" && people.length > 0)) ?? [], [preview, details, people]);

  async function submit() {
    if (!preview) return;
    setSubmitting(true); setError(null);
    try {
      const r = await api<{ complaint_id: number; result: string; complaint: MyComplaint }>("/complaints", {
        body: {
          analysis_id: preview.analysis_id, visibility, contact_consent: consent, details,
          people: preview.people.map((p, i) => ({
            person_id: people[i]?.personId ?? null,
            party_role: p.party_role,
            stated_role: people[i]?.statedRole ?? p.stated_role,
            description: people[i]?.personId ? null : (people[i]?.description || null),
          })),
        },
      });
      setFiled(r);
    } catch (e) {
      const err = e as ApiError;
      if (err.status === 400 && err.message.includes("expired")) { lastSent.current = ""; void analyse(text.trim()); }
      setError(err);
    } finally { setSubmitting(false); }
  }

  if (filed) return <Filed r={filed} />;

  return (
    <>
      <PageHeader title="File a complaint"
        subtitle="Describe the problem in your own words, in English or Hinglish. Sunwai works out where it should go and asks only for what's missing." />

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        {/* ------------------------------------------------ left: the text */}
        <div className="space-y-4">
          <Panel>
            <label htmlFor="complaint-text" className="mb-2 block text-sm font-medium text-ink">What happened?</label>
            <textarea id="complaint-text" value={text} onChange={(e) => setText(e.target.value)} rows={9}
              maxLength={4000} className={cx(inputClass, "resize-y text-[15px] leading-relaxed")}
              placeholder="For example: the tap on the 2nd floor of BH-3 has been leaking since Monday" />
            <div className="mt-2 flex items-center justify-between text-xs text-ink-soft">
              <span>{analysing ? "Reading your complaint…" : text.trim().length < 20 ? "Keep writing; Sunwai reads it as you type." : preview ? "Updated as you type." : ""}</span>
              <Button variant="secondary" className="px-2.5 py-1 text-xs" disabled={text.trim().length < 10}
                busy={analysing} onClick={() => void analyse(text.trim())}>
                <Sparkles className="h-3.5 w-3.5" /> Check now
              </Button>
            </div>
            {!text && (
              <div className="mt-4 border-t border-line pt-3">
                <p className="mb-2 text-xs text-ink-soft">Try one of these:</p>
                <div className="flex flex-wrap gap-2">
                  {EXAMPLES.map((e) => (
                    <button key={e} onClick={() => setText(e)}
                      className="rounded-full border border-line px-3 py-1 text-xs text-ink-soft hover:border-seal hover:text-seal">
                      {e}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </Panel>

          {preview && (
            <Panel title="Who can see it">
              <fieldset className="space-y-2">
                <legend className="sr-only">Visibility</legend>
                {([
                  ["Public", "The handling office sees your name and the complaint.", !preview.sensitive],
                  ["Confidential", "Only the assigned office or committee can open it, and every opening is logged.", true],
                  ["Anonymous", "Your name is never shown to anyone handling it. You can still track it here.", preview.anonymous_allowed],
                ] as const).map(([v, help, allowed]) => (
                  <label key={v} className={cx("flex gap-3 rounded-md border px-3 py-2.5",
                    visibility === v ? "border-seal bg-seal-soft/50" : "border-line", !allowed && "opacity-50")}>
                    <input type="radio" name="vis" value={v} checked={visibility === v} disabled={!allowed}
                      onChange={() => setVisibility(v)} className="mt-1 accent-seal" />
                    <span>
                      <span className="block text-sm font-medium text-ink">{v}</span>
                      <span className="block text-xs text-ink-soft">
                        {!allowed && v === "Public" ? "Not available: sensitive complaints are always confidential." :
                          !allowed ? "Not available for this kind of complaint." : help}
                      </span>
                    </span>
                  </label>
                ))}
              </fieldset>
              {preview.sensitive && visibility !== "Anonymous" && (
                <label className="mt-3 flex items-start gap-2 text-sm text-ink">
                  <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)} className="mt-1 accent-seal" />
                  The committee may see my name and contact me about this.
                </label>
              )}
            </Panel>
          )}
        </div>

        {/* ------------------------------------------------ right: the analysis */}
        <div className="space-y-4">
          <ErrorNote error={error} />
          {!preview && !analysing && (
            <div className="rounded-lg border border-dashed border-line px-6 py-12 text-center text-sm text-ink-soft">
              As you write, this side shows what kind of complaint it is, who will handle it,
              and anything that's still missing.
            </div>
          )}
          {analysing && !preview && (
            <div className="rounded-lg border border-line bg-white px-6 py-12 text-center text-sm text-ink-soft">Reading your complaint…</div>
          )}

          {preview && (
            <div className={cx("space-y-4 transition-opacity", analysing && "opacity-60")}>
              <Panel>
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="text-xs text-ink-soft">Looks like</p>
                    <p className="text-lg font-semibold text-ink">{preview.category.name}</p>
                  </div>
                  <PriorityMark priority={preview.priority} />
                </div>
                <p className="mt-3 text-sm text-ink">
                  Goes to <strong className="font-semibold">{preview.route_hint}</strong>
                  {preview.category.sla_hours && preview.auto_accepted &&
                    <span className="text-ink-soft">, who has {preview.category.sla_hours >= 48
                      ? `${Math.round(preview.category.sla_hours / 24)} days` : `${preview.category.sla_hours} hours`} to act.</span>}
                </p>
                {preview.sensitive && (
                  <p className="mt-3 flex items-start gap-2 rounded-md bg-veil-soft px-3 py-2 text-sm text-veil">
                    <Lock className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
                    Sensitive complaint. It stays confidential, and nobody from the respondent's department is on the panel that hears it.
                  </p>
                )}
                <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-line pt-3 text-xs text-ink-soft">
                  <span>AI confidence {Math.round(preview.confidence * 100)}%{!preview.auto_accepted && ", so a triage officer will confirm the category"}</span>
                  <span>Read by {preview.engine.startsWith("offline") ? "the offline classifier" : preview.engine}</span>
                  <button onClick={() => setShowRedacted((s) => !s)} className="inline-flex items-center gap-1 text-seal hover:underline">
                    <Eye className="h-3.5 w-3.5" /> {showRedacted ? "Hide" : "What the AI saw"}
                  </button>
                </div>
                {showRedacted && (
                  <p className="mt-2 rounded-md bg-paper px-3 py-2 font-mono text-[13px] text-ink">
                    {preview.redacted_text}
                    <span className="mt-1 block font-sans text-xs text-ink-soft">Names, phone numbers and e-mails are removed before the text leaves the server.</span>
                  </p>
                )}
              </Panel>

              <Panel title="Details the office needs"
                aside={<span className={cx("text-xs", missing.length ? "text-medium" : "text-seal")}>
                  {missing.length ? `${missing.length} missing` : "Complete"}</span>}>
                <ul className="space-y-3">
                  {preview.checklist.filter((c) => !c.field.startsWith("respondent")).map((c) => {
                    const typed = details[c.field] ?? "";
                    const done = !!(c.value || typed.trim());
                    return (
                      <li key={c.field} className="flex gap-3">
                        {done ? <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-seal" aria-label="Present" />
                          : c.mandatory ? <CircleAlert className="mt-0.5 h-4 w-4 shrink-0 text-medium" aria-label="Missing" />
                          : <Circle className="mt-0.5 h-4 w-4 shrink-0 text-line" aria-label="Optional" />}
                        <div className="min-w-0 flex-1">
                          <div className="flex flex-wrap items-baseline gap-x-2">
                            <span className="text-sm font-medium text-ink">{fieldLabel(c.field)}</span>
                            {!c.mandatory && <span className="text-xs text-ink-faint">optional</span>}
                            {c.value && !typed && <span className="text-xs text-ink-faint">
                              {c.source === "Profile" ? "from your profile" : "found in your text"}</span>}
                          </div>
                          <input value={typed} onChange={(e) => setDetails((d) => ({ ...d, [c.field]: e.target.value }))}
                            placeholder={c.value ?? c.question} aria-label={c.question}
                            className={cx(inputClass, "mt-1 py-1.5", c.value && "placeholder:text-ink")} />
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </Panel>

              {(preview.people.length > 0 || preview.checklist.some((c) => c.field === "respondent_role")) && (
                <Panel title="The people involved">
                  {preview.people.length === 0 && (
                    <NotSure onAdd={(role) => {
                      setPreview({ ...preview, people: [{ ref: null, party_role: "Respondent", stated_role: role, description: null, name: null, candidates: [] }] });
                      setPeople([{ personId: null, statedRole: role, description: "" }]);
                    }} />
                  )}
                  <div className="space-y-5">
                    {preview.people.map((p, i) => (
                      <PersonPicker key={i} person={p} choice={people[i]}
                        onChange={(c) => setPeople((all) => all.map((x, j) => (j === i ? c : x)))} />
                    ))}
                  </div>
                </Panel>
              )}

              <div className="flex flex-wrap items-center justify-end gap-3">
                {missing.length > 0 && (
                  <span className="text-xs text-ink-soft">
                    You can file now; Sunwai will ask for the missing {missing.length === 1 ? "detail" : "details"} afterwards.
                  </span>
                )}
                <Button onClick={submit} busy={submitting} disabled={analysing}>File complaint</Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

const ROLES: PreviewPerson["stated_role"][] = ["Student", "Faculty", "Staff", "Unknown"];

function NotSure({ onAdd }: { onAdd: (role: PreviewPerson["stated_role"]) => void }) {
  return (
    <div className="mb-2">
      <p className="text-sm text-ink">Is the person a student, faculty member or staff?</p>
      <div className="mt-2 flex flex-wrap gap-2">
        {ROLES.map((r) => (
          <Button key={r} variant="secondary" className="py-1 text-xs" onClick={() => onAdd(r)}>
            {r === "Unknown" ? "Not sure" : r}
          </Button>
        ))}
      </div>
    </div>
  );
}

function PersonPicker({ person, choice, onChange }: {
  person: PreviewPerson; choice: PersonChoice | undefined; onChange: (c: PersonChoice) => void;
}) {
  const c = choice ?? { personId: null, statedRole: person.stated_role, description: "" };
  const label = person.name ? `“${person.name}”` : person.description ?? "The person";
  return (
    <fieldset>
      <legend className="flex items-center gap-2 text-sm font-medium text-ink">
        <UserRound className="h-4 w-4 text-ink-soft" aria-hidden />
        {label} <span className="font-normal text-ink-soft">({person.party_role === "Respondent" ? "the complaint is about them" : "witness"})</span>
      </legend>
      {person.candidates.length > 0 && (
        <div className="mt-2 space-y-1.5">
          <p className="text-xs text-ink-soft">Did you mean:</p>
          {person.candidates.map((k) => (
            <label key={k.person_id} className={cx("flex cursor-pointer items-center gap-3 rounded-md border px-3 py-2",
              c.personId === k.person_id ? "border-seal bg-seal-soft/50" : "border-line hover:border-ink-faint")}>
              <input type="radio" name={`p-${person.ref}`} checked={c.personId === k.person_id}
                onChange={() => onChange({ ...c, personId: k.person_id, statedRole: k.person_type as PersonChoice["statedRole"] })}
                className="accent-seal" />
              <span className="min-w-0">
                <span className="block text-sm text-ink">{k.full_name}</span>
                <span className="block text-xs text-ink-soft">
                  {k.connection === "Other" ? `${k.person_type}, ${k.department}` : k.connection}
                </span>
              </span>
            </label>
          ))}
          <label className={cx("flex cursor-pointer items-center gap-3 rounded-md border px-3 py-2",
            c.personId === null ? "border-seal bg-seal-soft/50" : "border-line hover:border-ink-faint")}>
            <input type="radio" name={`p-${person.ref}`} checked={c.personId === null}
              onChange={() => onChange({ ...c, personId: null })} className="accent-seal" />
            <span className="text-sm text-ink">Someone else, or I'm not sure</span>
          </label>
        </div>
      )}
      {c.personId !== null && c.pickedName && (
        <p className="mt-2 flex items-center justify-between rounded-md border border-seal bg-seal-soft/50 px-3 py-2 text-sm text-ink">
          <span>Selected: <strong className="font-medium">{c.pickedName}</strong></span>
          <button type="button" onClick={() => onChange({ ...c, personId: null, pickedName: undefined })}
            className="text-xs text-seal hover:underline">Change</button>
        </p>
      )}
      {c.personId === null && (
        <PeopleSearch role={c.statedRole} initial={person.name ?? ""}
          onPick={(k) => onChange({ ...c, personId: k.person_id, pickedName: k.full_name,
            statedRole: k.person_type as PersonChoice["statedRole"] })} />
      )}
      {c.personId === null && (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <Field label="They are a">
            <select value={c.statedRole} onChange={(e) => onChange({ ...c, statedRole: e.target.value as PersonChoice["statedRole"] })}
              className={inputClass}>
              {ROLES.map((r) => <option key={r} value={r}>{r === "Unknown" ? "Not sure" : r}</option>)}
            </select>
          </Field>
          <Field label="Describe them (optional)">
            <input value={c.description} onChange={(e) => onChange({ ...c, description: e.target.value })}
              placeholder="e.g. a senior from BH-1" className={inputClass} />
          </Field>
        </div>
      )}
    </fieldset>
  );
}

/** Search the college directory by name (find_person_candidates in the
 *  database), for when the suggestions above are not the right person. */
function PeopleSearch({ role, initial, onPick }: {
  role: PreviewPerson["stated_role"]; initial: string; onPick: (k: Candidate) => void;
}) {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<Candidate[] | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    const term = q.trim();
    if (term.length < 2) { setResults(null); return; }
    const timer = setTimeout(async () => {
      try {
        setResults(await api<Candidate[]>(`/people/search?q=${encodeURIComponent(term)}&role=${role}`));
        setError(null);
      } catch (e) { setError(e as ApiError); }
    }, 300);
    return () => clearTimeout(timer);
  }, [q, role]);

  return (
    <div className="mt-3">
      <Field label="Search by name" hint={role !== "Unknown" ? `Only ${role.toLowerCase()} members are shown.` : undefined}>
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder={initial ? `e.g. ${initial}` : "Type at least 2 letters"}
          className={inputClass} aria-describedby="people-results" />
      </Field>
      <div id="people-results" aria-live="polite">
        {results && results.length === 0 && <p className="mt-2 text-xs text-ink-soft">Nobody by that name. Describe them below instead.</p>}
        {results && results.length > 0 && (
          <ul className="mt-2 divide-y divide-line overflow-hidden rounded-md border border-line">
            {results.map((k) => (
              <li key={k.person_id}>
                <button type="button" onClick={() => onPick(k)}
                  className="flex w-full flex-col px-3 py-2 text-left hover:bg-paper focus-visible:bg-paper focus-visible:outline-none">
                  <span className="text-sm text-ink">{k.full_name}</span>
                  <span className="text-xs text-ink-soft">{k.connection === "Other" ? `${k.person_type}, ${k.department}` : k.connection}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
        <ErrorNote error={error} />
      </div>
    </div>
  );
}

function Filed({ r }: { r: { complaint_id: number; result: string; complaint: MyComplaint } }) {
  const c = r.complaint;
  const message: Record<string, string> = {
    Assigned: `It has been sent to ${c.handled_by ?? "the right office"}.`,
    NeedsInfo: "A few details are still missing. Answer the questions on the complaint page and it will be routed straight away.",
    AwaitingTriage: "A triage officer will confirm the category first, then it will be routed.",
  };
  return (
    <div className="mx-auto max-w-xl py-10">
      <CheckCircle2 className="h-10 w-10 text-seal" aria-hidden />
      <h1 className="mt-4 text-2xl font-semibold text-ink">Complaint #{r.complaint_id} filed</h1>
      <p className="mt-2 text-ink-soft">{message[r.result] ?? `Status: ${r.result}.`}</p>
      <dl className="mt-6 grid grid-cols-2 gap-4 rounded-lg border border-line bg-white p-5 text-sm">
        <div><dt className="text-ink-soft">Category</dt><dd className="mt-0.5 font-medium text-ink">{c.category ?? "To be confirmed"}</dd></div>
        <div><dt className="text-ink-soft">Status</dt><dd className="mt-1"><StatusBadge status={c.status} /></dd></div>
        <div><dt className="text-ink-soft">Priority</dt><dd className="mt-1"><PriorityMark priority={c.priority} /></dd></div>
        <div><dt className="text-ink-soft">Handled by</dt><dd className="mt-0.5 font-medium text-ink">{c.handled_by ?? "–"}</dd></div>
      </dl>
      <div className="mt-6 flex gap-3">
        <Link to={`/c/${r.complaint_id}`}><Button>Open complaint</Button></Link>
        <Link to="/complaints"><Button variant="secondary">My complaints</Button></Link>
      </div>
    </div>
  );
}
