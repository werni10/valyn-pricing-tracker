// =====================================================================
// Valyn Advisory — runtime config
// Empty values => DEMO mode (localStorage, works offline, no backend).
// Fill both values => LIVE mode (Supabase backend, shared across devices).
// Get them in Supabase Studio → Project Settings → API.
// Safe to commit: the anon key is a public client key protected by RLS.
// =====================================================================
window.VALYN_CONFIG = {
  supabaseUrl: "https://uhayryaabydwgpsjdvfu.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoYXlyeWFhYnlkd2dwc2pkdmZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQxNTI2OTgsImV4cCI6MjA5OTcyODY5OH0.dnyXjQ-9YDUDYf2MfscThBBWqRhKJn4HQgWnpdlk8ZQ",
  org: "Auto Nejma"       // client organisation this deployment serves
};
