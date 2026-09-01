-- ═══════════════════════════════════════════════════════════════════════════
-- 0002_consent_and_hardening.sql — 2026-09-01
--
-- 1. GDPR: gemmer tidspunktet for klientens samtykke til behandling af
--    helbredsoplysninger (afgives i opstartsskemaets trin 5).
-- 2. Mindre RLS-oprydning der ikke nåede med i baseline.
-- Idempotent — kan køres igen.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Samtykke-tidsstempel på opstartsskemaet
ALTER TABLE intake_forms ADD COLUMN IF NOT EXISTS consent_at TIMESTAMPTZ;

COMMENT ON COLUMN intake_forms.consent_at IS
  'Tidspunkt hvor klienten gav samtykke til behandling af sine oplysninger, herunder helbredsoplysninger (GDPR art. 9). NULL = samtykke ikke registreret (klient oprettet før 2026-09-01).';

-- 2. leads: tilføj created_by så en fremtidig medcoach ikke ser hinandens leads
--    (ingen effekt nu — Hamza er eneste coach — men gør tabellen fremtidssikker)
ALTER TABLE leads ADD COLUMN IF NOT EXISTS created_by UUID DEFAULT auth.uid();
