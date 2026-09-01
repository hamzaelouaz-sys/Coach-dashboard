// ai-generate: kører ét Claude-kald på coachens vegne til AI-kost-/træningsgeneratoren i dashboardet.
//
// Hvorfor en Edge Function: Anthropic-API-nøglen lå tidligere i coachens browser (localStorage +
// anthropic-dangerous-direct-browser-access). Nu ligger den KUN som en Supabase secret, og kun
// coach-JWT'et kan kalde funktionen.
//
// Deploy (fra Coach-dashboard-repoets rodmappe):
//   supabase functions deploy ai-generate
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY sættes automatisk.)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const COACH_EMAIL = "hamzaelouaz@gmail.com";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const SYSTEM =
  "Du er Hamza El – dansk online coach. Returner altid præcis det JSON-format der beskrives. Ingen forklaringer, ingen markdown, kun valid JSON.";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });

  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
  const { data: { user }, error: authErr } = await supabase.auth.getUser(jwt);
  if (authErr || !user || user.email?.toLowerCase() !== COACH_EMAIL) {
    return new Response(JSON.stringify({ error: "Kun coach må bruge AI-generatoren" }), { status: 403, headers: CORS });
  }

  if (!ANTHROPIC_API_KEY) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY er ikke sat i Supabase secrets" }), { status: 500, headers: CORS });
  }

  let body: { prompt?: string; max_tokens?: number };
  try { body = await req.json(); } catch { body = {}; }
  const prompt = (body.prompt || "").trim();
  const maxTokens = Math.min(Math.max(body.max_tokens || 4096, 256), 8000);
  if (!prompt) {
    return new Response(JSON.stringify({ error: "prompt påkrævet" }), { status: 400, headers: CORS });
  }

  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-sonnet-5",
        max_tokens: maxTokens,
        system: SYSTEM,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      return new Response(JSON.stringify({ error: err?.error?.message || `Anthropic HTTP ${res.status}` }), { status: 502, headers: CORS });
    }

    const data = await res.json();
    const text = data?.content?.[0]?.text ?? "";
    return new Response(JSON.stringify({ text }), { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 500, headers: CORS });
  }
});
