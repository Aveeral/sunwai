import { useState, type ReactNode } from "react";
import { NavLink, useNavigate } from "react-router-dom";
import {
  BarChart3, ClipboardList, Clock3, FileText, Gavel, History, Inbox, LogOut, Menu, PenLine,
  ScrollText, ShieldCheck, Sparkles, Users, X,
} from "lucide-react";
import type { Role } from "../api/types";
import { homeFor, useAuth } from "../lib/auth";
import { useClock } from "../lib/clock";
import { cx } from "./ui";

interface NavItem { to: string; label: string; icon: ReactNode }

function navFor(role: Role): NavItem[] {
  const file: NavItem[] = [
    { to: "/file", label: "File a complaint", icon: <PenLine className="h-4 w-4" /> },
    { to: "/complaints", label: "My complaints", icon: <FileText className="h-4 w-4" /> },
  ];
  const handler: NavItem[] = [
    { to: "/queue", label: "My queue", icon: <Inbox className="h-4 w-4" /> },
    { to: "/history", label: "Handled earlier", icon: <History className="h-4 w-4" /> },
  ];
  switch (role) {
    case "sunwai_student":
      return [...file, { to: "/scripts", label: "Answer scripts", icon: <ScrollText className="h-4 w-4" /> }];
    case "sunwai_handler":
      return [...handler, ...file];
    case "sunwai_icc": case "sunwai_antiragging": case "sunwai_sgrc":
      return [{ to: "/committee", label: "Committee cases", icon: <Users className="h-4 w-4" /> }, ...handler, ...file];
    case "sunwai_triage":
      return [{ to: "/triage", label: "Triage queue", icon: <Sparkles className="h-4 w-4" /> }, ...file];
    case "sunwai_ombudsperson":
      return [{ to: "/appeals", label: "Appeals", icon: <Gavel className="h-4 w-4" /> }, ...file];
    case "sunwai_admin":
      return [
        { to: "/dashboard", label: "Dashboard", icon: <BarChart3 className="h-4 w-4" /> },
        { to: "/all", label: "All complaints", icon: <ClipboardList className="h-4 w-4" /> },
        { to: "/access-log", label: "Access log", icon: <ScrollText className="h-4 w-4" /> },
      ];
  }
}

function DemoClock() {
  const clock = useClock();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const run = async (f: () => Promise<unknown>) => {
    setBusy(true); setNote(null);
    try { await f(); } finally { setBusy(false); }
  };
  return (
    <div className="rounded-md border border-white/10 p-3 text-xs text-white/70">
      <div className="mb-2 flex items-center gap-1.5 font-medium text-white/90">
        <Clock3 className="h-3.5 w-3.5" aria-hidden /> Demo clock
      </div>
      <p className="mb-2">
        {clock.offsetHours === 0 ? "Real time" : `Moved ${Math.round(clock.offsetHours)} h ahead`}
      </p>
      <div className="flex flex-wrap gap-1.5">
        <button disabled={busy} onClick={() => run(() => clock.advance(24))}
          className="rounded border border-white/20 px-2 py-1 hover:bg-white/10">+24 h</button>
        <button disabled={busy} onClick={() => run(async () => {
          const r = await clock.escalate();
          setNote(`${r.escalated} escalated, ${r.closed_stale} closed`);
        })} className="rounded border border-white/20 px-2 py-1 hover:bg-white/10">Run escalation</button>
        {clock.offsetHours > 0 && (
          <button disabled={busy} onClick={() => run(clock.reset)}
            className="rounded px-2 py-1 text-white/60 hover:text-white">Reset</button>
        )}
      </div>
      {note && <p className="mt-2 text-white/90" role="status">{note}</p>}
    </div>
  );
}

export default function Layout({ children }: { children: ReactNode }) {
  const { me, logout, switchRole } = useAuth();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  if (!me) return null;
  const items = navFor(me.role);

  const sidebar = (
    <div className="flex h-full flex-col gap-6 bg-ink px-4 py-5 text-white">
      <div className="flex items-center gap-2.5 px-2">
        <img src="/favicon.svg" alt="" className="h-7 w-7" />
        <div>
          <div className="text-[15px] font-semibold leading-none">Sunwai</div>
          <div className="mt-1 text-2xs text-white/60">NSUT grievance redressal</div>
        </div>
      </div>

      <nav className="flex flex-col gap-0.5" aria-label="Main">
        {items.map((i) => (
          <NavLink key={i.to} to={i.to} onClick={() => setOpen(false)}
            className={({ isActive }) => cx("flex items-center gap-2.5 rounded-md px-2.5 py-2 text-sm",
              isActive ? "bg-white/10 font-medium text-white" : "text-white/70 hover:bg-white/5 hover:text-white")}>
            {i.icon}{i.label}
          </NavLink>
        ))}
        <div className="my-2 border-t border-white/10" />
        <NavLink to="/security" onClick={() => setOpen(false)}
          className={({ isActive }) => cx("flex items-center gap-2.5 rounded-md px-2.5 py-2 text-sm",
            isActive ? "bg-white/10 font-medium text-white" : "text-white/70 hover:bg-white/5 hover:text-white")}>
          <ShieldCheck className="h-4 w-4" /> Security demo
        </NavLink>
      </nav>

      <div className="mt-auto flex flex-col gap-3">
        <DemoClock />
        <div className="rounded-md bg-white/5 p-3">
          <div className="text-sm font-medium">{me.name}</div>
          <div className="mt-0.5 text-xs text-white/60">{me.posts ?? me.unit}</div>
          {me.roles.length > 1 ? (
            <label className="mt-2 block text-xs text-white/60">
              Acting as
              <select value={me.role}
                onChange={async (e) => { const r = e.target.value as Role; await switchRole(r); navigate(homeFor(r)); }}
                className="mt-1 w-full rounded border border-white/20 bg-ink px-2 py-1 text-xs text-white">
                {me.roles.map((r) => <option key={r} value={r}>{me.role_labels[r]}</option>)}
              </select>
            </label>
          ) : (
            <div className="mt-2 text-xs text-white/60">Acting as {me.role_label}</div>
          )}
          <div className="mt-1 text-2xs text-white/40">Database role: {me.role}</div>
        </div>
        <button onClick={() => { logout(); navigate("/"); }}
          className="flex items-center gap-2 px-2.5 text-sm text-white/60 hover:text-white">
          <LogOut className="h-4 w-4" /> Switch person
        </button>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-paper lg:flex">
      <aside className="sticky top-0 hidden h-screen w-64 shrink-0 lg:block">{sidebar}</aside>

      <div className="flex items-center justify-between bg-ink px-4 py-3 text-white lg:hidden">
        <span className="flex items-center gap-2 font-semibold"><img src="/favicon.svg" alt="" className="h-6 w-6" /> Sunwai</span>
        <button onClick={() => setOpen(true)} aria-label="Open menu"><Menu className="h-5 w-5" /></button>
      </div>
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div className="absolute inset-0 bg-ink/40" onClick={() => setOpen(false)} />
          <div className="absolute inset-y-0 left-0 w-72">
            <button onClick={() => setOpen(false)} aria-label="Close menu"
              className="absolute right-3 top-4 z-10 text-white/70"><X className="h-5 w-5" /></button>
            {sidebar}
          </div>
        </div>
      )}

      <main className="min-w-0 flex-1 px-4 py-6 sm:px-8 lg:py-10">
        <div className="mx-auto max-w-6xl">{children}</div>
      </main>
    </div>
  );
}
