import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronRight } from "lucide-react";
import { api, ApiError } from "../api/client";
import type { DemoGroup, DemoPerson } from "../api/types";
import { ErrorNote, Spinner } from "../components/ui";
import { homeFor, useAuth } from "../lib/auth";
import { useAsync } from "../lib/useAsync";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const groups = useAsync(() => api<DemoGroup[]>("/demo-users"));
  const [busy, setBusy] = useState<number | null>(null);
  const [error, setError] = useState<ApiError | null>(null);

  const choose = async (p: DemoPerson) => {
    setBusy(p.person_id); setError(null);
    try { await login(p.person_id, p.role); navigate(homeFor(p.role)); }
    catch (e) { setError(e as ApiError); }
    finally { setBusy(null); }
  };

  return (
    <div className="min-h-screen bg-paper lg:grid lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
      <section className="bg-ink px-6 py-10 text-white sm:px-12 lg:sticky lg:top-0 lg:h-screen lg:py-16">
        <div className="flex h-full max-w-md flex-col">
          <div className="flex items-center gap-3">
            <img src="/favicon.svg" alt="" className="h-9 w-9" />
            <span className="text-lg font-semibold">Sunwai</span>
          </div>
          <h1 className="mt-12 text-[2.1rem] font-semibold leading-[1.15] tracking-[-0.015em] sm:text-[2.5rem]">
            Every complaint at NSUT, heard by the right person.
          </h1>
          <p className="mt-5 text-[15px] leading-relaxed text-white/75">
            Write a complaint in English or Hinglish. An AI reads it; the database decides who handles it,
            keeps anyone with a conflict of interest away, and escalates it if nobody acts in time.
          </p>
          <dl className="mt-10 grid grid-cols-3 gap-4 border-t border-white/15 pt-6 text-sm">
            <div><dt className="text-white/60">Tables</dt><dd className="mt-1 text-2xl font-semibold">28</dd></div>
            <div><dt className="text-white/60">Database roles</dt><dd className="mt-1 text-2xl font-semibold">8</dd></div>
            <div><dt className="text-white/60">Committees</dt><dd className="mt-1 text-2xl font-semibold">4</dd></div>
          </dl>
          <p className="mt-auto pt-10 text-xs text-white/50">
            DBMS lab project, CSDS Section I. Aveeral Jain, Kavya Gautam, Chetan Sameer and Piyush Aggarwal.
          </p>
        </div>
      </section>

      <section className="px-4 py-10 sm:px-10 lg:py-16">
        <div className="mx-auto max-w-2xl">
          <h2 className="text-xl font-semibold text-ink">Log in as</h2>
          <p className="mt-1 text-sm text-ink-soft">
            A demo login: pick a person. Each one gets the database role their position in the college gives them.
          </p>
          <div className="mt-4"><ErrorNote error={error ?? groups.error} /></div>
          {groups.loading && <Spinner />}
          {groups.data?.map((g) => (
            <div key={g.title} className="mt-8">
              <h3 className="mb-2 text-sm font-semibold text-ink-soft">{g.title}</h3>
              <ul className="divide-y divide-line overflow-hidden rounded-lg border border-line bg-white">
                {g.people.map((p) => (
                  <li key={`${p.person_id}-${p.role}`}>
                    <button onClick={() => choose(p)} disabled={busy !== null}
                      className="group flex w-full items-center gap-4 px-4 py-3 text-left hover:bg-paper focus-visible:bg-paper focus-visible:outline-none">
                      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-seal-soft text-sm font-semibold text-seal">
                        {p.name.replace("Dr. ", "").split(" ").map((w) => w[0]).slice(0, 2).join("")}
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm font-medium text-ink">
                          {p.name}
                          <span className="ml-2 text-xs font-normal text-ink-faint">{p.role_label}</span>
                        </span>
                        <span className="block truncate text-xs text-ink-soft">{p.blurb}</span>
                      </span>
                      {busy === p.person_id
                        ? <span className="text-xs text-ink-soft">Logging in…</span>
                        : <ChevronRight className="h-4 w-4 text-ink-faint group-hover:text-ink" aria-hidden />}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
