# Valyn Advisory — Auto Nejma Pricing Tracker

Real transactional-pricing intelligence app for the Moroccan auto market.
Static frontend + Supabase backend (Postgres + Auth + Storage + Row-Level Security).

- **Admin (Valyn)** — uploads the monthly xlsx/csv, broadcasts alerts, manages each account's rights.
- **Client (Auto Nejma)** — receives everything, sees only the modules granted to their account.

The pricing engine (Moroccan luxury tax, CEM, fiscal-vs-commercial discount split, segment index)
runs in the browser and matches the source `.xlsx` cell-for-cell.

---

## Two run modes

| Mode | When | Data |
|------|------|------|
| **Demo** | `config.js` empty | localStorage, single device, seed data. Open `index.html`, no backend. |
| **Live** | `config.js` filled | Supabase, shared across devices, real auth + rights. |

Same code — filling `config.js` flips it to live.

---

## Files

```
index.html        the whole app (markup + styles + engine + UI)
config.js         Supabase URL + anon key (empty = demo)
sql/schema.sql    tables + RLS + storage + seed — run once in Supabase
vercel.json       static hosting config + security headers
```

---

## Go live — step by step

### 1. Create the Supabase project
1. Sign up at https://supabase.com → **New project**. Pick a region close to Morocco (EU West).
2. Wait for it to provision.

### 2. Run the schema
1. Supabase Studio → **SQL Editor** → **New query**.
2. Paste all of `sql/schema.sql` → **Run**.
   Creates tables, RLS policies, the new-user trigger, storage buckets, and seeds the real vehicle data.

### 3. Wire the frontend
1. Studio → **Project Settings → API**. Copy **Project URL** and **anon public** key.
2. Put them in `config.js`:
   ```js
   window.VALYN_CONFIG = {
     supabaseUrl: "https://YOURPROJECT.supabase.co",
     supabaseAnonKey: "eyJhbGci...",
     org: "Auto Nejma"
   };
   ```
   > The anon key is a **public** client key. Security is enforced by RLS, not by hiding it.

### 4. Create the users (auth)
Supabase → **Authentication → Users → Add user** (or **Invite**). For each person set email + password.
On first creation the trigger auto-creates a `profiles` row as **client, inactive, read-only**.

Then promote/activate. Studio → **SQL Editor**:
```sql
-- make yourself the Valyn admin
update public.profiles
set role='admin', active=true, org='Valyn Advisory',
    rights='{"dashboard":true,"tracked":true,"history":true,"compare":true,"priceindex":true,
             "benchmark":true,"reports":true,"simcem":true,"simremise":true,"engine":true,
             "catalog":true,"collection":true,"quality":true,"dataadmin":true,"diffusion":true,"users":true}'::jsonb
where email='you@valyn.ma';

-- activate the Auto Nejma client
update public.profiles set active=true where email='dg@autonejma.ma';
```
After that, manage all rights from the app's **Accès & droits** page (no more SQL).

### 5. Deploy to Vercel
1. Push this folder to a GitHub repo.
2. https://vercel.com → **Add New → Project** → import the repo.
3. Framework preset: **Other** (it's static). Root = this folder. **Deploy**.
4. Add your custom domain in **Project → Settings → Domains**.

> Vercel serves the static files as-is. No build step. `config.js` ships with the site.

### 6. Lock the Supabase auth redirect
Supabase → **Authentication → URL Configuration** → set **Site URL** to your Vercel domain.

---

## Monthly cycle (real, advancing)
The active analytics month (`CURRENT`) is **derived** — it's the latest month with published data. The cycle advances for real:
1. Client prepares its **Sélection analyse M+1** for the month being prepared, checks the engagement, transmits. It locks (client can't re-open server-side).
2. Valyn tracks the month in **Pilotage** (Sélection → Intégration → Calcul → Contrôle → Publication).
3. Valyn **Import données** → picks the target month in the "Mois à publier" selector → drops the file (columns: Marque · Modèle · Motorisation · Finition · Segment · Type · Prix Showroom TTC · Prix remisé TTC CEM · Frais immat · Commentaire) → **Publier**.
4. On publish the month becomes `PUBLISHED`, the **dashboard advances** to it (previous month becomes M-1), and the **next month opens as a new draft** automatically. A month with no data can't be published.
5. **Diffusion & alertes** for any extra message.

## Rights (admin)
**Accès & droits** — one card per account, a toggle per module, active/inactive switch, role. Changes persist to the `profiles` table and take effect on the client's next load.

---

## Proof files (brochures / proformas / photos)
Real upload is wired. **Collecte & preuves** → pick finition + type + visibility → drop a file → it uploads to the private `proofs` storage bucket and shows in **Bibliothèque de preuves** and the finition's history panel. Client-visible files live at `proofs/<org>/…`; Valyn-internal files at `proofs/<org>/_interne/…`, which storage RLS keeps admin-only.

## Notes / hardening TODO
- **Inviting users in live mode** is done from the Supabase dashboard (needs the service role). The in-app "Inviter" button is demo-only. To do it in-app, add a Supabase **Edge Function** using `auth.admin.inviteUserByEmail` with the service-role key (server-side only — never ship that key to the browser).
- **Contact tickets** (client → Valyn) and **notification emails** are in-app only — no email is sent yet. Notification preferences (Paramètres) gate the in-app bell/feed.
- **Multi-client**: schema already scopes by `org`. To serve a second dealer, add their vehicles/broadcasts with a different `org` and set their profiles' `org` to match. RLS isolates them automatically.
- xlsx parsing uses SheetJS from CDN. Offline → use the CSV path.
- **Re-run `sql/schema.sql` after updates** — it's idempotent. Recent additions: `months`, `selections`, `documents` tables; `broadcasts.kind`; tightened RLS for the monthly workflow; `_interne` storage protection.

## Local dev
```bash
cd najma-app
python3 -m http.server 8000
# open http://localhost:8000
```
