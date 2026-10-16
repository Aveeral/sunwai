import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { api, ApiError, getToken, setToken } from "../api/client";
import type { Me, Role } from "../api/types";

interface AuthState {
  me: Me | null;
  loading: boolean;
  login: (personId: number, role?: Role) => Promise<void>;
  switchRole: (role: Role) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);

  const loadMe = useCallback(async () => {
    if (!getToken()) { setMe(null); setLoading(false); return; }
    try { setMe(await api<Me>("/me")); }
    catch (e) {
      // Only a rejected token logs you out; a network hiccup must not.
      if (e instanceof ApiError && e.status === 401) setToken(null);
      setMe(null);
    }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void loadMe(); }, [loadMe]);

  const login = useCallback(async (personId: number, role?: Role) => {
    const r = await api<{ token: string }>("/login", { body: { person_id: personId, role } });
    setToken(r.token);
    setLoading(true);
    await loadMe();
  }, [loadMe]);

  const switchRole = useCallback(async (role: Role) => {
    if (me) await login(me.person_id, role);
  }, [me, login]);

  const logout = useCallback(() => { setToken(null); setMe(null); }, []);

  return (
    <AuthContext.Provider value={{ me, loading, login, switchRole, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside AuthProvider");
  return ctx;
}

/** Where each role lands after logging in. */
export function homeFor(role: Role): string {
  switch (role) {
    case "sunwai_student": return "/complaints";
    case "sunwai_handler": return "/queue";
    case "sunwai_icc":
    case "sunwai_antiragging":
    case "sunwai_sgrc": return "/committee";
    case "sunwai_triage": return "/triage";
    case "sunwai_ombudsperson": return "/appeals";
    case "sunwai_admin": return "/dashboard";
  }
}
