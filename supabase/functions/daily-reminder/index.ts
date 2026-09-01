// daily-reminder: AUTOMATISK dagligt job. Kaldes hver time af et pg_cron-job i Supabase.
// Funktionen afgør selv ud fra dansk tid (Europe/Copenhagen, DST-sikkert) hvad der skal ske:
//
//   kl. 03  → bøde-optælling for gårsdagen (bødekasse-featuren, kun for klienter coachen har slået til)
//   kl. 08  → daglig vejnings-påmindelse (web push) til ALLE klienter med aktiv notifikation
//
// Beskyttet med en delt hemmelighed (CRON_SECRET) i Authorization-headeren — ingen coach-JWT her,
// da kaldet kommer fra databasen, ikke fra en browser.
//
// Deploy (kør fra Coach-dashboard-repoets rodmappe):
//   supabase functions deploy daily-reminder --no-verify-jwt
//   supabase secrets set CRON_SECRET=<lang tilfældig streng>
// (VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY er allerede sat for send-push og genbruges her.
//  SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY sættes automatisk af Supabase.)
//
// Manuel test uden at vente på uret:
//   curl -X POST 'https://<ref>.supabase.co/functions/v1/daily-reminder?force=reminder' -H 'Authorization: Bearer <CRON_SECRET>'
//   curl -X POST 'https://<ref>.supabase.co/functions/v1/daily-reminder?force=fines'    -H 'Authorization: Bearer <CRON_SECRET>'

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
webpush.setVapidDetails("mailto:hamzaelouaz@gmail.com", VAPID_PUBLIC, VAPID_PRIVATE);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // service role — bypasser RLS
);

// Dags dato + klokketime i dansk tid. Intl håndterer sommer-/vintertid automatisk,
// så "kl. 08 dansk" rammer korrekt hele året uden flere cron-linjer.
function danishNow(): { date: string; hour: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Copenhagen",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hour12: false,
  }).formatToParts(new Date());
  const get = (t: string) => parts.find((p) => p.type === t)!.value;
  return { date: `${get("year")}-${get("month")}-${get("day")}`, hour: parseInt(get("hour"), 10) % 24 };
}

// Gårsdagens dato (YYYY-MM-DD) ud fra en given dato-streng.
function prevDay(dateStr: string): string {
  const d = new Date(dateStr + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");

  const auth = (req.headers.get("Authorization") || "").replace("Bearer ", "");
  if (!CRON_SECRET || auth !== CRON_SECRET) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  const force = new URL(req.url).searchParams.get("force"); // "reminder" | "fines" | null
  const { date: today, hour } = danishNow();
  const out: Record<string, unknown> = { today, hour };

  if (force === "fines" || hour === 3) {
    out.fines = await tallyFines(prevDay(today));
  }
  if (force === "reminder" || hour === 8) {
    out.reminder = await sendDailyReminder();
  }

  return new Response(JSON.stringify(out), { headers: { "Content-Type": "application/json" } });
});

// ── Bøde-optælling: for hver klient med aktiv bødekasse, hvis de IKKE loggede en
// vægt på den pågældende dag, oprettes én bøde-postering. UNIQUE(user_id, date) i
// databasen gør det idempotent — jobbet kan køre flere gange uden dobbeltbøder.
async function tallyFines(day: string) {
  const { data: boxes } = await supabase
    .from("fine_box").select("user_id, daily_rate, start_date").eq("enabled", true);
  if (!boxes?.length) return { day, checked: 0, fined: 0 };

  let fined = 0;
  for (const box of boxes) {
    if (box.start_date && box.start_date > day) continue; // bødekassen var ikke aktiv endnu

    const { data: prof } = await supabase
      .from("profiles").select("status").eq("id", box.user_id).limit(1);
    if (prof?.[0]?.status !== "active") continue; // kun aktive klienter bødes

    const { data: w } = await supabase
      .from("weight_log").select("id").eq("user_id", box.user_id).eq("date", day).limit(1);
    if (w?.length) continue; // vejede sig — ingen bøde

    const { error } = await supabase.from("fine_entries").insert({
      user_id: box.user_id, date: day, amount: box.daily_rate ?? 20,
    });
    if (!error) fined++;
  }
  return { day, checked: boxes.length, fined };
}

// ── Daglig vejnings-påmindelse til alle klienter med aktiv push. Titel/tekst og
// til/fra styres fra coach-dashboardet via app_config-rækken "daily_reminder".
async function sendDailyReminder() {
  const { data: cfg } = await supabase
    .from("app_config").select("value").eq("key", "daily_reminder").limit(1);
  const c = (cfg?.[0]?.value ?? {}) as { enabled?: boolean; title?: string; body?: string };
  if (!c.enabled) return { skipped: "disabled" };

  const title = c.title || "Dagens vejning";
  const body = c.body || "Husk at logge din vægt i appen 💪";

  // Kun aktive klienter — en der stadig afventer godkendelse skal ikke få daglige påmindelser.
  // profiles.id ER auth-bruger-id'et (se resten af koden), så det matcher push_subscriptions.user_id.
  const { data: activeProfiles } = await supabase
    .from("profiles").select("id").eq("status", "active");
  const activeIds = new Set((activeProfiles || []).map((p: { id: string }) => p.id));

  const { data: allSubs } = await supabase.from("push_subscriptions").select("*");
  const subs = (allSubs || []).filter((s: { user_id: string }) => activeIds.has(s.user_id));
  const results = await Promise.allSettled(
    (subs || []).map((s) =>
      webpush.sendNotification(
        { endpoint: s.endpoint, keys: s.keys },
        JSON.stringify({ title, body, url: "/app/" }),
      )
    ),
  );

  // Ryd udløbne/tilbagekaldte subscriptions (410/404)
  await Promise.all(results.map((r, i) => {
    if (r.status === "rejected" && [404, 410].includes((r.reason as { statusCode?: number })?.statusCode ?? 0)) {
      return supabase.from("push_subscriptions").delete().eq("id", subs![i].id);
    }
  }));

  return { sent: results.filter((r) => r.status === "fulfilled").length, total: results.length };
}
