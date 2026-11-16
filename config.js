// Revive Rewards — connection settings.
// Paste these two values from Supabase: Project Settings → API (or "Connect" → App Frameworks).
// The key here is the PUBLIC "publishable" / "anon" key. It is safe to put on a public site:
// all data is protected by the database's security rules and staff logins.
// NEVER paste the "secret" or "service_role" key here.
window.REVIVE_CONFIG = {
  supabaseUrl: "https://hfqcvetpiyozrxkvchcf.supabase.co",        // looks like https://abcdefghijk.supabase.co
  supabaseKey: "sb_publishable_7ztXxttricofAIzQpQdnlw_DRXsqgxP"     // starts with sb_publishable_ (or a long eyJ... anon key)
};
