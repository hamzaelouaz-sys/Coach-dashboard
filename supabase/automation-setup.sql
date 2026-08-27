-- ═══════════════════════════════════════════════════════════════════════════
-- AUTOMATISERING — daglig vejnings-påmindelse + bødekasse
-- Hører til Edge Function:  supabase/functions/daily-reminder/index.ts
--
-- Kør HELE denne fil i Supabase → SQL Editor. Erstat <CRON_SECRET> nederst med
-- den streng du satte via `supabase secrets set CRON_SECRET=...`.
-- (Samme SQL ligger også bag 🔧 SQL-knappen i coach-dashboardet.)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Global konfiguration — styrer den daglige påmindelse fra ⚙️ Automatik-knappen
CREATE TABLE IF NOT EXISTS app_config (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "app_config_read" ON app_config;
CREATE POLICY "app_config_read" ON app_config FOR SELECT USING (true);
DROP POLICY IF EXISTS "app_config_coach" ON app_config;
CREATE POLICY "app_config_coach" ON app_config FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');
INSERT INTO app_config (key, value) VALUES
  ('daily_reminder', '{"enabled": false, "title": "Dagens vejning", "body": "Husk at logge din vægt i appen 💪"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 2. Bødekasse pr. klient — slås til/fra pr. klient under klientens Profil-fane
CREATE TABLE IF NOT EXISTS fine_box (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled    BOOLEAN NOT NULL DEFAULT false,
  daily_rate INTEGER NOT NULL DEFAULT 20,
  start_date DATE NOT NULL DEFAULT ((now() AT TIME ZONE 'Europe/Copenhagen')::date),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE fine_box ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fine_box_read" ON fine_box;
CREATE POLICY "fine_box_read" ON fine_box FOR SELECT
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');
DROP POLICY IF EXISTS "fine_box_coach" ON fine_box;
CREATE POLICY "fine_box_coach" ON fine_box FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');

-- 3. Bøde-posteringer — én pr. dag klienten ikke vejede sig. Klienten kan SE sine egne,
--    kun coachen kan oprette/eftergive/markere betalt.
CREATE TABLE IF NOT EXISTS fine_entries (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date       DATE NOT NULL,
  amount     INTEGER NOT NULL,
  waived     BOOLEAN NOT NULL DEFAULT false,
  paid       BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, date)
);
ALTER TABLE fine_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fine_entries_read" ON fine_entries;
CREATE POLICY "fine_entries_read" ON fine_entries FOR SELECT
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');
DROP POLICY IF EXISTS "fine_entries_coach" ON fine_entries;
CREATE POLICY "fine_entries_coach" ON fine_entries FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');

-- 4. Cron — kald daily-reminder hver time. Funktionen afgør selv (dansk tid) om der
--    skal sendes påmindelse (kl. 08) eller tælles bøder (kl. 03). DST-sikkert.
--    Deploy funktionen først:  supabase functions deploy daily-reminder --no-verify-jwt
--    Sæt hemmeligheden:        supabase secrets set CRON_SECRET=<din-streng>
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'daily-reminder-hourly';
SELECT cron.schedule('daily-reminder-hourly', '0 * * * *', $CRON$
  SELECT net.http_post(
    url     := 'https://rtcayuwapitueckgprzc.supabase.co/functions/v1/daily-reminder',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer <CRON_SECRET>'),
    body    := '{}'::jsonb
  );
$CRON$);
