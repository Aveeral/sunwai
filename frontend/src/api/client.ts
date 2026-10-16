// Thin wrapper around fetch. Every error from the backend has {detail, source};
// when source is "postgresql" the message is PostgreSQL's own words, and the
// UI shows it as such (that is the point of the project).

const BASE = (import.meta.env.VITE_API_URL ?? "").replace(/\/$/, "");
const TOKEN_KEY = "sunwai.token";

export class ApiError extends Error {
  status: number;
  fromDatabase: boolean;
  constructor(status: number, message: string, fromDatabase: boolean) {
    super(message);
    this.status = status;
    this.fromDatabase = fromDatabase;
  }
}

export function getToken(): string | null {
  try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
}
export function setToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch { /* private mode: token lives only in memory for this tab */ }
}

export async function api<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = {};
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (init.body !== undefined) headers["Content-Type"] = "application/json";

  let res: Response;
  try {
    res = await fetch(`${BASE}/api${path}`, {
      method: init.method ?? (init.body !== undefined ? "POST" : "GET"),
      headers,
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
    });
  } catch {
    throw new ApiError(0, "Can't reach the Sunwai server. Check that the backend is running.", false);
  }
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    let msg = "Something went wrong.";
    if (typeof data?.detail === "string") msg = data.detail;
    else if (Array.isArray(data?.detail)) msg = data.detail.map((d: { msg: string }) => d.msg).join("; ");
    if (res.status === 401) setToken(null);
    throw new ApiError(res.status, msg, data?.source === "postgresql");
  }
  return data as T;
}
