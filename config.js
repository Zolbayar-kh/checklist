/*
  Supabase тохиргоо.
  Supabase → Project Settings → API (эсвэл "Data API" / "API Keys") хэсгээс:
   - Project URL      → SUPABASE_URL
   - Publishable key (sb_publishable_...) эсвэл anon public key → SUPABASE_ANON_KEY
  Энэ "anon" түлхүүрийг нийтэд ил байлгахад болно: хүн бүр зөвхөн өөрийнхөө
  өгөгдлийг харах эрхтэй (supabase.sql дахь RLS дүрэм).
  "service_role" түлхүүрийг ЭНД ХЭЗЭЭ Ч БҮҮ ОРУУЛ.
*/
window.APP_CONFIG = {
  SUPABASE_URL: "https://ywiwvssodziuxmpssdnt.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_p3Ox3rA1VQNK7EAMiMGH2w_AbXgDI_2"
};
