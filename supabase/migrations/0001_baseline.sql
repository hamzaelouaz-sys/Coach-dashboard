-- ═══════════════════════════════════════════════════════════════════════════
-- 0001_baseline.sql — hele skemaet + RLS for Det Skarpe Liv
--
-- Denne fil erstatter den gamle "🔧 SQL"-knap i coach-dashboardet og
-- supabase/automation-setup.sql. Alt er idempotent (IF NOT EXISTS / DROP POLICY
-- IF EXISTS), så den kan køres igen uden skade.
--
-- Kør i Supabase → SQL Editor, ELLER via CLI:  supabase db push
-- ═══════════════════════════════════════════════════════════════════════════

-- Sikrer at client_data kun har én række per bruger (kræves af upsert)
ALTER TABLE client_data DROP CONSTRAINT IF EXISTS client_data_user_id_key;
ALTER TABLE client_data ADD CONSTRAINT client_data_user_id_key UNIQUE (user_id);

-- ── profiles ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "profiles_access" ON profiles;
CREATE POLICY "profiles_access" ON profiles FOR ALL
  USING (auth.uid() = id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = id OR auth.email() = 'hamzaelouaz@gmail.com');

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'ingen_abonnement'
  CHECK (payment_status IN ('ingen_abonnement','aktiv','forfalden','stoppet'));
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS next_payment_date DATE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS monthly_price NUMERIC(8,2);

-- ── intake_forms ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "intake_forms_access" ON intake_forms;
CREATE POLICY "intake_forms_access" ON intake_forms FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── client_data ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "client_data_access" ON client_data;
CREATE POLICY "client_data_access" ON client_data FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── weight_log ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "weight_log_access" ON weight_log;
CREATE POLICY "weight_log_access" ON weight_log FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');
ALTER TABLE weight_log ADD COLUMN IF NOT EXISTS steps INTEGER;
ALTER TABLE weight_log ADD COLUMN IF NOT EXISTS sleep_hours NUMERIC(3,1);

-- ── checkins ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "checkins_access" ON checkins;
CREATE POLICY "checkins_access" ON checkins FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── workout_completions ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workout_completions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  week_number INTEGER NOT NULL,
  year INTEGER NOT NULL,
  day_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE workout_completions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "wc_access" ON workout_completions;
CREATE POLICY "wc_access" ON workout_completions FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── strength_logs ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS strength_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  exercise_name TEXT NOT NULL,
  day_name TEXT,
  week_number INTEGER NOT NULL,
  year INTEGER NOT NULL,
  set_number INTEGER NOT NULL,
  weight_kg NUMERIC(6,2),
  reps INTEGER,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE strength_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sl_access" ON strength_logs;
CREATE POLICY "sl_access" ON strength_logs FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');
ALTER TABLE strength_logs ADD COLUMN IF NOT EXISTS rpe SMALLINT
  CHECK (rpe IS NULL OR (rpe >= 1 AND rpe <= 10));

-- ── body_measurements ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS body_measurements (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  waist NUMERIC(5,1), hips NUMERIC(5,1), chest NUMERIC(5,1),
  left_arm NUMERIC(5,1), right_arm NUMERIC(5,1),
  left_thigh NUMERIC(5,1), right_thigh NUMERIC(5,1),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bm_access" ON body_measurements;
CREATE POLICY "bm_access" ON body_measurements FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── messages ─────────────────────────────────────────────────────────────
ALTER TABLE messages ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "messages_access" ON messages;
CREATE POLICY "messages_access" ON messages FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (
    (auth.uid() = user_id AND sender = 'client')
    OR (auth.email() = 'hamzaelouaz@gmail.com' AND sender = 'coach')
  );

-- ── diet_adherence ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS diet_adherence (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  week_number INTEGER NOT NULL,
  year INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('ja','delvist','nej')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, date)
);
ALTER TABLE diet_adherence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "da_access" ON diet_adherence;
CREATE POLICY "da_access" ON diet_adherence FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── banker (kun coach) ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS supplement_bank (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL, dose TEXT, timing TEXT, note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'food_bank') THEN
    EXECUTE 'ALTER TABLE food_bank ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "food_bank_access" ON food_bank';
    EXECUTE 'CREATE POLICY "food_bank_access" ON food_bank FOR ALL USING (auth.email() = ''hamzaelouaz@gmail.com'') WITH CHECK (auth.email() = ''hamzaelouaz@gmail.com'')';
  END IF;
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'exercise_bank') THEN
    EXECUTE 'ALTER TABLE exercise_bank ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "exercise_bank_access" ON exercise_bank';
    EXECUTE 'CREATE POLICY "exercise_bank_access" ON exercise_bank FOR ALL USING (auth.email() = ''hamzaelouaz@gmail.com'') WITH CHECK (auth.email() = ''hamzaelouaz@gmail.com'')';
  END IF;
END $$;
ALTER TABLE supplement_bank ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "supplement_bank_access" ON supplement_bank;
CREATE POLICY "supplement_bank_access" ON supplement_bank FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');

-- ── leads (kun coach) ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS leads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL, contact TEXT,
  status TEXT NOT NULL DEFAULT 'ny' CHECK (status IN ('ny','kontaktet','interesseret','afvist','konverteret')),
  kilde TEXT, note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "leads_access" ON leads;
CREATE POLICY "leads_access" ON leads FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');

-- ── push_subscriptions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  keys JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, endpoint)
);
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ps_access" ON push_subscriptions;
CREATE POLICY "ps_access" ON push_subscriptions FOR ALL
  USING (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.uid() = user_id OR auth.email() = 'hamzaelouaz@gmail.com');

-- ── Storage: progress-photos (privat bucket, signerede URLs) ──────────────
INSERT INTO storage.buckets (id, name, public) VALUES ('progress-photos', 'progress-photos', false)
  ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "photo_upload" ON storage.objects;
CREATE POLICY "photo_upload" ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'progress-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text   -- kun i sin egen mappe
  );
DROP POLICY IF EXISTS "photo_view" ON storage.objects;
CREATE POLICY "photo_view" ON storage.objects FOR SELECT
  USING (
    bucket_id = 'progress-photos'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR auth.email() = 'hamzaelouaz@gmail.com')
  );
DROP POLICY IF EXISTS "photo_delete" ON storage.objects;
CREATE POLICY "photo_delete" ON storage.objects FOR DELETE
  USING (
    bucket_id = 'progress-photos'
    AND ((storage.foldername(name))[1] = auth.uid()::text OR auth.email() = 'hamzaelouaz@gmail.com')
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTOMATISERING — daglig vejnings-påmindelse + bødekasse (daily-reminder)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS app_config (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
-- Kun indloggede brugere må læse konfigurationen (ikke anonyme besøgende)
DROP POLICY IF EXISTS "app_config_read" ON app_config;
CREATE POLICY "app_config_read" ON app_config FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "app_config_coach" ON app_config;
CREATE POLICY "app_config_coach" ON app_config FOR ALL
  USING (auth.email() = 'hamzaelouaz@gmail.com')
  WITH CHECK (auth.email() = 'hamzaelouaz@gmail.com');
INSERT INTO app_config (key, value) VALUES
  ('daily_reminder', '{"enabled": false, "title": "Dagens vejning", "body": "Husk at logge din vægt i appen 💪"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

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

-- ── Ydelses-indexer (mod full table scans efterhånden som datamængden vokser) ──
CREATE INDEX IF NOT EXISTS idx_strength_logs_user_created   ON strength_logs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_weight_log_user_date         ON weight_log (user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user_read           ON messages (user_id, read);
CREATE INDEX IF NOT EXISTS idx_messages_sender_read         ON messages (sender, read);
CREATE INDEX IF NOT EXISTS idx_wc_user_year_week            ON workout_completions (user_id, year, week_number);
CREATE INDEX IF NOT EXISTS idx_checkins_user_created        ON checkins (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_diet_adherence_user_date     ON diet_adherence (user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_body_measurements_user_date  ON body_measurements (user_id, date DESC);

-- ── Cron: kald daily-reminder hver time ──────────────────────────────────
--   Deploy funktionen først:  supabase functions deploy daily-reminder --no-verify-jwt
--   Sæt hemmeligheden:        supabase secrets set CRON_SECRET=<din-streng>
--   Erstat <CRON_SECRET> nedenfor med SAMME streng, og kør dette afsnit i SQL Editor.
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
