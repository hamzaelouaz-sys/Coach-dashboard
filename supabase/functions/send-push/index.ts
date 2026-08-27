// send-push: sender én web push-notifikation til én klient, udelukkende trigget manuelt af
// coachen fra coach-dashboardet ("🔔 Send påmindelse"). Ingen automatik/planlægning.
//
// Deploy (kør fra Coach-dashboard-repoets rodmappe):
//   supabase functions deploy send-push
//   supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=...
// (SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY sættes automatisk af Supabase for enhver Edge Function.)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
webpush.setVapidDetails("mailto:hamzaelouaz@gmail.com", VAPID_PUBLIC, VAPID_PRIVATE);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")! // service role — bypasser RLS, nødvendigt for at læse enhver klients subscriptions
);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  // Kun coachen selv må trigge et push — tjek det faktiske JWT fra kaldet, ikke bare at det er en gyldig bruger.
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
  const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
  if (authErr || !user || user.email?.toLowerCase() !== "hamzaelouaz@gmail.com") {
    return new Response(JSON.stringify({ error: "Kun coach må sende push" }), { status: 403, headers: CORS });
  }

  const { user_id, title, body, url } = await req.json();
  if (!user_id || !title) {
    return new Response(JSON.stringify({ error: "user_id og title påkrævet" }), { status: 400, headers: CORS });
  }

  const { data: subs } = await supabase.from("push_subscriptions").select("*").eq("user_id", user_id);
  const results = await Promise.allSettled(
    (subs || []).map((s) => webpush.sendNotification({ endpoint: s.endpoint, keys: s.keys }, JSON.stringify({ title, body, url })))
  );

  // Fjern subscriptions der er udløbet/tilbagekaldt (410/404), så vi ikke bliver ved med at forsøge
  await Promise.all(results.map((r, i) => {
    if (r.status === "rejected" && [404, 410].includes((r.reason as { statusCode?: number })?.statusCode ?? 0)) {
      return supabase.from("push_subscriptions").delete().eq("id", subs![i].id);
    }
  }));

  return new Response(
    JSON.stringify({ sent: results.filter((r) => r.status === "fulfilled").length, total: results.length }),
    { headers: { ...CORS, "Content-Type": "application/json" } }
  );
});
