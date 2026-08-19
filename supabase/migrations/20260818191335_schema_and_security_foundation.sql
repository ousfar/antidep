-- ============================================================================
-- Antidep migrasjon 001 — schema- og sikkerhetsfundament
--
-- Formål: etablere de logiske schemaene, den eksplisitte Data API-grensen og
-- rollevokabularet som resten av kunnskapsbasen bygges på.
--
-- Styrende dokumenter:
--   docs/DATABASE_ARCHITECTURE.md
--     §5  eksponering er opt-in
--     §6  schemainndeling
--     §7.3 tidsbegreper
--     §8  identifikatorer
--     §45-§50 roller, RLS, least privilege og privilegerte funksjoner
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §16 applikasjonsroller i første tekniske implementasjon
--     §18 innholdet i denne migrasjonen
--     §47 offentlig lesing
--
-- Avgrensning: migrasjonen oppretter ingen tabeller, ingen views, ingen
-- funksjoner og ingen data. Katalogtabeller kommer i migrasjon 002,
-- Source/EvidenceItem i 003, Claims i 004, review og proveniens i 005,
-- publisering i 006, api-views i 007, audit.events i 008 og ingest-schemaet
-- i 009 (MVP_IMPLEMENTATION_PLAN.md §19-§26).
--
-- Konvensjoner som gjelder fra og med denne migrasjonen, og som håndheves
-- maskinelt i supabase/tests/030_conventions_test.sql:
--   1. Kanoniske objekter har én databasegenerert UUID som primærnøkkel:
--        id uuid primary key default gen_random_uuid()
--      Eksterne identifikatorer (DOI, PMID, ATC, FEST-ID, varenummer) og
--      naturlige nøkler lagres som egne felter eller identifikatorrelasjoner med
--      unike constraints, aldri som intern primærnøkkel
--      (DATABASE_ARCHITECTURE.md §8).
--   2. Alle tidspunkter er timestamptz. timestamp without time zone brukes
--      ikke. Registreringstidspunkt heter created_at og settes av databasen med
--      default now(). Tidsbegreper med ulik betydning holdes adskilt i egne
--      kolonner: created_at, recorded_at, valid_from/valid_to, published_at,
--      review_due_at (DATABASE_ARCHITECTURE.md §7.3).
--   3. Alle tabeller i catalog, knowledge, workflow, provenance og audit
--      opprettes med RLS aktivert og uten grants til anon/authenticated.
--      Manglende eksplisitt grant er ønsket standardtilstand
--      (DATABASE_ARCHITECTURE.md §5, §48).
--   4. Views i api opprettes med security_invoker. Funksjoner er SECURITY
--      INVOKER som normalvalg; en SECURITY DEFINER-funksjon skal ha
--      search_path = '' med schemakvalifiserte objektnavn og ikke være kjørbar
--      for PUBLIC (DATABASE_ARCHITECTURE.md §42, §50).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Plattformforutsetninger og extensions
--
-- UUID-konvensjonen bygger på pg_catalog.gen_random_uuid(), som er en del av
-- PostgreSQL-kjernen fra og med versjon 13. Antidep kjører PostgreSQL 17
-- (supabase/config.toml). Ingen ny extension er derfor nødvendig for identitet
-- eller tidsstempler i dette steget, og ingen innføres «for sikkerhets skyld».
-- Extensions legges til i den migrasjonen som faktisk trenger dem, for eksempel
-- pg_trgm/citext for søk eller btree_gist for temporale exclusion constraints.
--
-- Forutsetningen kontrolleres eksplisitt slik at en database uten
-- gen_random_uuid() feiler under migrering, ikke i klinisk produksjonskode.
-- ----------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('pg_catalog.gen_random_uuid()') is null then
    raise exception
      'Antidep krever pg_catalog.gen_random_uuid() (PostgreSQL 13 eller nyere)';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. Logiske schemaer (DATABASE_ARCHITECTURE.md §6)
--
-- public brukes ikke som lagringsplass for Antidep-objekter.
-- ----------------------------------------------------------------------------
create schema catalog;
create schema knowledge;
create schema workflow;
create schema provenance;
create schema audit;
create schema api;

comment on schema catalog is
  'Virkestoffer, produkter, klassifikasjoner, kliniske begreper og andre strukturelle domeneobjekter. Ikke eksponert i Data API.';
comment on schema knowledge is
  'Claims, revisjoner, kilder, evidens, vurderinger, interaksjoner, anbefalinger og kliniske regler. Kanonisk klinisk kunnskap. Ikke eksponert i Data API.';
comment on schema workflow is
  'Arbeidsflytstatus: evidensarbeidsenheter, verifikasjon, review-køer og rollemedlemskap. Ikke eksponert i Data API.';
comment on schema provenance is
  'Aktører, pipeline- og modellversjoner og sporbarhetsrelasjoner. Ikke eksponert i Data API.';
comment on schema audit is
  'Append-only hendelseslogg. Ikke eksponert i Data API.';
comment on schema api is
  'Kontraktslag mot klientene: bevisst eksponerte views og RPC-er over publiserte data. Eneste schema Antidep eksponerer i Data API. Hvert objekt krever egen grant.';

-- ----------------------------------------------------------------------------
-- 3. Eksplisitte revokes før grants (DATABASE_ARCHITECTURE.md §5, §48, §49)
--
-- Nye schemaer gir i utgangspunktet ingen privilegier til PUBLIC eller til
-- Data API-rollene, men Antidep skal ikke stole på plattformens standardverdier.
-- Grensen skrives derfor eksplisitt, slik at den er lesbar i migrasjonen og
-- testbar etterpå.
-- ----------------------------------------------------------------------------
revoke all privileges on schema catalog, knowledge, workflow, provenance, audit, api
  from public;

revoke all privileges on schema catalog, knowledge, workflow, provenance, audit, api
  from anon, authenticated, service_role;

-- Klientrollene får kun bruke kontraktslaget. usage på schemaet gir ingen
-- tilgang til objekter: hvert view og hver funksjon i api må få egen grant i
-- migrasjonen som oppretter det (DATABASE_ARCHITECTURE.md §44).
grant usage on schema api to anon, authenticated;

-- service_role er ikke applikasjonens universalnøkkel og får derfor ingen
-- tilgang her. Serverside- og agentidentiteter får smale, eksplisitte grants
-- når en konkret operasjon krever det (DATABASE_ARCHITECTURE.md §49,
-- MVP_IMPLEMENTATION_PLAN.md §48-§49).

-- ----------------------------------------------------------------------------
-- 4. Rollevokabular (MVP_IMPLEMENTATION_PLAN.md §16,
--    DATABASE_ARCHITECTURE.md §45-§47)
--
-- Rollene er et kontrollert vokabular og håndheves deklarativt som enum
-- (DATABASE_ARCHITECTURE.md §57, §72). Selve medlemskapsmodellen
-- (workflow.user_roles med scope og gyldighetsperiode) hører til migrasjon 005,
-- sammen med review-tabellene som trenger den.
-- ----------------------------------------------------------------------------
create type workflow.app_role as enum ('editor', 'reviewer', 'publisher', 'admin');

comment on type workflow.app_role is
  'Applikasjonsroller i første tekniske implementasjon: editor (utkast/revisjonsforslag), reviewer (faglig verifikasjon), publisher (kontrollert publisering) og admin (bruker- og systemforvaltning). public_reader dekkes av Data API-rollene anon/authenticated mot api-schemaet. agent_worker får egne least privilege-identiteter når evidenspipelinen krever det. clinical_lead og evidence_lead er foreløpig governance-ansvar uten egne tekniske tillatelser.';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- også for typer (DATABASE_ARCHITECTURE.md §5).
revoke usage on type workflow.app_role from public;
