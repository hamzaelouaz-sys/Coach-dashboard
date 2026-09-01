// delete-client: sletter en klient PERMANENT og fuldstændigt. Kun coach-JWT'et kan kalde den.
//
// Hvorfor en Edge Function: sletning fra browseren brugte anon-nøglen og ramte kun 5 tabeller.
// Klientens login (auth-bruger), styrkelog, træningscompletions, kropsmål, kostefterlevelse,
// bøder, push-abonnementer og fotos blev liggende — og klienten kunne logge ind igen og få en ny
// pending-profil. Her bruges service role + auth.admin.deleteUser (FK ON DELETE CASCADE tager
// resten hvor det er sat op; de øvrige tabeller ryddes eksplicit for en sikkerheds skyld).
//
// Deploy (fra Coach-dashboard-repoets rodmappe):
//   supabase functions deploy delete-client
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY sættes automatisk.)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const COACH_EMAIL = "hamzaelouaz@gmail.com";
const BUCKET = "progress-photos";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Alle tabeller med en user_id-kolonne der peger på klienten
const USER_TABLES = [
  "intake_forms", "client_data", "weight_log", "checkins", "messages",
  "workout_completions", "strength_logs", "body_measurements", "diet_adherence",
  "fine_entries", "fine_box", "push_subscriptions",
];

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
  const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
  if (authErr || !user || user.email?.toLowerCase() !== COACH_EMAIL) {
    return new Response(JSON.stringify({ error: "Kun coach må slette klienter" }), { status: 403, headers: CORS });
  }

  let body: { user_id?: string };
  try { body = await req.json(); } catch { body = {}; }
  const uid = body.user_id;
  if (!uid) {
    return new Response(JSON.stringify({ error: "user_id påkrævet" }), { status: 400, headers: CORS });
  }

  // Aldrig muligt at slette coachen selv
  if (uid === user.id) {
    return new Response(JSON.stringify({ error: "Kan ikke slette coach-kontoen" }), { status: 400, headers: CORS });
  }

  const errors: string[] = [];

  // 1. Fotos i Storage (mappen hedder klientens uid)
  try {
    const { data: files } = await supabase.storage.from(BUCKET).list(uid);
    if (files?.length) {
      const paths = files.map((f) => `${uid}/${f.name}`);
      const { error } = await supabase.storage.from(BUCKET).remove(paths);
      if (error) errors.push(`storage: ${error.message}`);
    }
  } catch (e) {
    errors.push(`storage: ${(e as Error).message}`);
  }

  // 2. Data-tabeller
  for (const table of USER_TABLES) {
    const { error } = await supabase.from(table).delete().eq("user_id", uid);
    if (error && !/does not exist|schema cache/i.test(error.message)) {
      errors.push(`${table}: ${error.message}`);
    }
  }

  // 3. Profil (id ER auth-bruger-id'et)
  {
    const { error } = await supabase.from("profiles").delete().eq("id", uid);
    if (error) errors.push(`profiles: ${error.message}`);
  }

  // 4. Selve login'et — så klienten ikke bare kan logge ind igen
  {
    const { error } = await supabase.auth.admin.deleteUser(uid);
    if (error) errors.push(`auth: ${error.message}`);
  }

  if (errors.length) {
    return new Response(JSON.stringify({ error: errors.join(" | ") }), { status: 500, headers: CORS });
  }
  return new Response(JSON.stringify({ ok: true }), { headers: { ...CORS, "Content-Type": "application/json" } });
});
