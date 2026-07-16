// =====================================================================
// Valyn Advisory — runtime config
// Empty values => DEMO mode (localStorage, works offline, no backend).
// Fill both values => LIVE mode (Supabase backend, shared across devices).
// Get them in Supabase Studio → Project Settings → API.
// Safe to commit: the anon key is a public client key protected by RLS.
// =====================================================================
window.VALYN_CONFIG = {
  supabaseUrl: "",        // e.g. "https://xxxxxxxx.supabase.co"
  supabaseAnonKey: "",    // e.g. "eyJhbGciOi..."
  org: "Auto Nejma"       // client organisation this deployment serves
};
