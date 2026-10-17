# Putting Sunwai online

Three free services, one for each part:

| Part | Service | What you get |
|---|---|---|
| Database | **Neon** (neon.tech) | PostgreSQL in the cloud |
| Backend | **Render** (render.com) | `https://sunwai-api-xxxx.onrender.com` |
| Website | **Vercel** (vercel.com) | `https://sunwai-xxxx.vercel.app`: the link you share |

Sign up for all three with your GitHub account. Do the steps in order; each step needs the address the previous one gave you.

## 1. Database on Neon (about 5 minutes)

1. On neon.tech, click **New project**. Name it `sunwai`, pick region **AWS Asia Pacific (Singapore)**, and keep the default Postgres version.
2. On the project dashboard, click **Connect**. Copy the connection string (it starts with `postgresql://neondb_owner:...` and ends with `?sslmode=require`).
3. On your Mac, in the Sunwai folder:
   ```bash
   bash scripts/deploy_db.sh "PASTE-THE-NEON-STRING-HERE"
   ```
   Keep the quotes. It builds all 28 tables and the demo data, then prints a line starting with `postgresql://sunwai_app:...`. **Copy that line**; it is the backend's `DATABASE_URL`. Don't share it.

The owner string from Neon can do anything to the database; only you use it, from your Mac. The backend gets the `sunwai_app` one, which has no privileges of its own, exactly like locally.

## 2. Backend on Render (about 10 minutes)

1. On render.com: **New** → **Blueprint** → choose the `Aveeral/sunwai` repository (Blueprint path: `render.yaml`). Render reads it and proposes one web service, `sunwai-api`, in the **Singapore** region, next to the database. (A service's region can't be changed later; to move it, delete the Blueprint and its service and create it again.)
2. It asks for three values:
   - `DATABASE_URL`: the `sunwai_app` line from step 1.
   - `OPENAI_API_KEY`: your OpenAI key. It is stored on Render only, never in GitHub.
   - `CORS_ORIGINS`: type `https://example.com` for now; you'll fix it in step 4.
3. Click **Apply**. The first build takes 3–5 minutes.
4. When it says **Live**, open `https://<your-service>.onrender.com/api/health`. You should see `"database":"ok"` and `"llm":"gpt-4o-mini"`. Copy the service address (without `/api/health`).

## 3. Website on Vercel (about 5 minutes)

1. On vercel.com: **Add New** → **Project** → import `Aveeral/sunwai`.
2. Set **Root Directory** to `frontend`. Vercel detects Vite by itself.
3. Under **Environment Variables** add `VITE_API_URL` = your Render address from step 2 (e.g. `https://sunwai-api-xxxx.onrender.com`, no slash at the end).
4. Click **Deploy**. Copy the address it gives you (e.g. `https://sunwai-xxxx.vercel.app`).

## 4. Connect them

On Render → `sunwai-api` → **Environment**, change `CORS_ORIGINS` to your Vercel address, then **Save** (Render restarts the service). This tells the backend that requests from your website are allowed.

Open the Vercel link, log in as Aarav and file a complaint. Done.

## Before the viva

- **Wake the server.** The free Render plan sleeps after 15 minutes without visitors, and the first request takes about 30 seconds. Open the link a minute before you present; the login screen shows "Waking up the server" while it starts.
- **Fresh demo data.** Run `bash scripts/deploy_db.sh` (no string needed after the first time). It rebuilds everything and keeps the same `sunwai_app` password, which it remembers in `.deploy.env` (not committed), so Render needs no change.
- **Reset the demo clock** in the sidebar if someone moved it.
- **Updates.** Every `git push` redeploys the backend (Render) and the website (Vercel) automatically. Database changes need `deploy_db.sh` again.

## If something goes wrong

| What you see | Cause and fix |
|---|---|
| Website says "Can't reach the Sunwai server" for more than a minute | Render service is down or `VITE_API_URL` is wrong. Check `/api/health` on Render, and the variable on Vercel (then redeploy on Vercel). |
| Browser console shows a CORS error | `CORS_ORIGINS` on Render doesn't exactly match the Vercel address (https, no trailing slash). |
| Deploy fails with `permission denied to set role "sunwai_admin"` | `DATABASE_URL` holds the Neon **owner** string, or a hand-edited one. Use the exact `sunwai_app` line that `deploy_db.sh` printed (its password is 48 hex characters). |
| `/api/health` fails with a password error | `DATABASE_URL` on Render is old; run `deploy_db.sh` and paste the new line. |
| `engine` says `offline (LLM unavailable)` | `OPENAI_API_KEY` on Render is missing or wrong, or the OpenAI account has no credit. The app still works with the offline classifier. |
| `zsh: no matches found` when running `deploy_db.sh` | The Neon string must be inside double quotes: `bash scripts/deploy_db.sh "postgresql://..."`. |
| `deploy_db.sh` says `psql: command not found` | Open a new Terminal window, or run `export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"`. |

## Viva notes

- *How is the deployed database secured?* Exactly as locally: the backend logs in as `sunwai_app`, which has no privileges and switches to the user's role for each request. The owner login is never given to the backend.
- *Where are the secrets?* In `.env` on our Macs and in Render's environment settings. GitHub has none: `.env` is in `.gitignore`, and `render.yaml` marks secrets `sync: false`.
- *Why three services?* Each does one job: Neon is managed PostgreSQL, Render runs Python, Vercel serves static files from a CDN. All three have free plans and deploy automatically from GitHub.
