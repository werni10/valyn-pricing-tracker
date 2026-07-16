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

## Monthly workflow (admin)
1. Log in as the Valyn admin.
2. **Import données** → drop the month's file (columns: Marque · Modèle · Motorisation · Finition · Segment · Type · Prix Showroom TTC · Prix remisé TTC CEM · Frais immat · Commentaire). A CSV template is downloadable in-app.
3. Review the parsed preview → **Publier**. Rows write to Postgres; the client is auto-notified and their dashboard updates live.
4. **Diffusion & alertes** for any extra message.

## Rights (admin)
**Accès & droits** — one card per account, a toggle per module, active/inactive switch, role. Changes persist to the `profiles` table and take effect on the client's next load.

---

## Notes / hardening TODO
- **Inviting users in live mode** is done from the Supabase dashboard (needs the service role). The in-app "Inviter" button is demo-only. To do it in-app, add a Supabase **Edge Function** using `auth.admin.inviteUserByEmail` with the service-role key (server-side only — never ship that key to the browser).
- **Proof/file storage**: buckets `proofs` and `imports` exist with policies. The upload buttons in **Collecte** are stubbed — wire them to `sb.storage.from('proofs').upload(...)`.
- **Multi-client**: schema already scopes by `org`. To serve a second dealer, add their vehicles/broadcasts with a different `org` and set their profiles' `org` to match. RLS isolates them automatically.
- xlsx parsing uses SheetJS from CDN. Offline → use the CSV path.

## Local dev
```bash
cd najma-app
python3 -m http.server 8000
# open http://localhost:8000
```
