# Edge Functions — Det Skarpe Liv

Deploy fra denne mappes rod (`Coach-dashboard/`):

```bash
supabase functions deploy send-push
supabase functions deploy daily-reminder --no-verify-jwt
supabase functions deploy delete-client
supabase functions deploy ai-generate
```

## Secrets (sæt én gang)

```bash
supabase secrets set VAPID_PUBLIC_KEY=...      # også i app/index.html som VAPID_PUBLIC_KEY
supabase secrets set VAPID_PRIVATE_KEY=...
supabase secrets set CRON_SECRET=<lang tilfældig streng>   # skal matche cron-jobbet i migrations/0001
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...          # til ai-generate (AI-plangenerator)
```

`SUPABASE_URL` og `SUPABASE_SERVICE_ROLE_KEY` sættes automatisk af Supabase.

## Database

SQL ligger i `../migrations/`. Kør `supabase db push`, eller kør filerne i
rækkefølge i Supabase → SQL Editor. Erstat `<CRON_SECRET>` i 0001 med den
rigtige streng før cron-afsnittet køres.
