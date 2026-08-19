-- ============================================================================
-- Antidep migrasjon 002 — katalogfundament
--
-- Formål: etablere den stabile identiteten for virkestoff, det kontrollerte
-- begrepsvokabularet og populasjonsmodellen som Claims, evidens og publiserte
-- projeksjoner senere skal peke på, og seede nøyaktig de katalogradene den
-- første golden slicen trenger.
--
-- Styrende dokumenter:
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §9   pilotsett av antidepressiver
--     §11  pilottemaer / ClinicalConcepts
--     §12  første golden slice (sertralin + mirtazapin × vektendring)
--     §19  innholdet i denne migrasjonen
--     §47-§49 tilgang og least privilege
--   docs/DATABASE_ARCHITECTURE.md
--     §7   stabil identitet, §7.3 tidsbegreper
--     §8   identifikatorer
--     §9   catalog.drugs, §11 catalog.clinical_concepts, §12 catalog.populations
--     §37  RESTRICT som hovedregel på fremmednøkler
--     §57-§60 deklarative constraints, cross-row-regler og triggerbruk
--     §73  invarianter
--   docs/KNOWLEDGE_MODEL.md §4, §6, §7 (Drug, ClinicalConcept, Population)
--
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §19-§26):
--   Ingen Source/EvidenceItem (003), ingen Claims (004), ingen review eller
--   proveniens (005), ingen publisering (006), ingen api-views (007), ingen
--   audit.events (008), ingen catalog.drug_products og ingen ingest (009).
--   Ingen RLS-policies: medlemskapsmodellen (workflow.user_roles) kommer i
--   migrasjon 005, og redaksjonell lesetilgang defineres sammen med den.
--   Tabellene er derfor default deny uten unntak i dette steget.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Kontrollerte vokabularer
--
-- Vokabularene er små, lukkede og endres bare gjennom versjonerte migrasjoner.
-- De håndheves derfor som enum, altså på datatypenivå, som er øverste nivå i
-- prioriteringsrekkefølgen i DATABASE_ARCHITECTURE.md §57. Dette er samme valg
-- som workflow.app_role i migrasjon 001, og det åpne spørsmålet om enum kontra
-- oppslagstabell (DATABASE_ARCHITECTURE.md §72) gjelder derfor nå flere typer.
-- Spørsmålet er billigst å avgjøre før kliniske data peker på verdiene.
-- ----------------------------------------------------------------------------

create type catalog.drug_status as enum ('active', 'historical', 'withdrawn');

comment on type catalog.drug_status is
  'Status for et virkestoff i Antidep: active (i klinisk bruk og vedlikeholdt), historical (fortsatt relevant for historikk og eldre kilder, ikke lenger prioritert) og withdrawn (trukket eller utgått). Statusen beskriver Antideps forvaltning av virkestoffet, ikke markedsstatus for et norsk produkt; produktstatus hører til catalog.drug_products i migrasjon 009.';

create type catalog.drug_name_type as enum ('alias', 'trade_name', 'historical_name');

comment on type catalog.drug_name_type is
  'Navnetype i catalog.drug_names: alias (synonym eller språkvariant, for eksempel INN-formen), trade_name (handelsnavn) og historical_name (tidligere brukt navn). Typen gjør at søk kan treffe alternative navn uten at kanonisk identitet endres.';

create type catalog.drug_identifier_system as enum ('atc');

comment on type catalog.drug_identifier_system is
  'Identifikatorsystem for eksterne virkestoffidentifikatorer. Foreløpig bare atc (WHO ATC). Nye systemer, for eksempel FEST-ID, legges til i den migrasjonen som faktisk trenger dem.';

create type catalog.clinical_concept_type as enum (
  'condition',
  'outcome',
  'pharmacokinetic_property',
  'interaction_mechanism'
);

comment on type catalog.clinical_concept_type is
  'Type klinisk begrep: condition (tilstand, diagnose eller indikasjon, for eksempel depressiv lidelse), outcome (klinisk utfall eller endepunkt kunnskap kan sammenlignes på, for eksempel vektendring, seksuell dysfunksjon, sedasjon og seponeringssymptomer), pharmacokinetic_property (for eksempel halveringstid og aktive metabolitter) og interaction_mechanism (for eksempel CYP-hemming). Typene dekker pilottemaene i MVP_IMPLEMENTATION_PLAN.md §11.';

create type catalog.vocabulary_status as enum ('active', 'deprecated');

comment on type catalog.vocabulary_status is
  'Status for en oppføring i et kontrollert vokabular: active (i bruk) eller deprecated (skal ikke brukes i nytt innhold, men beholdes fordi eksisterende innhold og historikk peker på den). Utfasing er en statusendring, ikke en sletting (DATABASE_ARCHITECTURE.md §36).';

create type catalog.population_pregnancy_context as enum (
  'pregnancy',
  'breastfeeding',
  'pregnancy_or_breastfeeding'
);

comment on type catalog.population_pregnancy_context is
  'Graviditets-/ammedimensjonen for en populasjon. NULL betyr at populasjonen ikke er avgrenset på denne dimensjonen, ikke at graviditet er vurdert og funnet irrelevant.';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- (DATABASE_ARCHITECTURE.md §5), på samme måte som for workflow.app_role.
revoke usage on type
  catalog.drug_status,
  catalog.drug_name_type,
  catalog.drug_identifier_system,
  catalog.clinical_concept_type,
  catalog.vocabulary_status,
  catalog.population_pregnancy_context
  from public;

-- ----------------------------------------------------------------------------
-- 2. Felles hjelpefunksjon for radens tidsstempler
--
-- KNOWLEDGE_MODEL.md §4 krever updated_at på Drug. Et tidsstempel kalleren kan
-- glemme å sette — eller sette til hva som helst — er verre enn ingen kolonne,
-- fordi det ser ut som en garanti. Begge kolonnene eies derfor av databasen:
--
--   INSERT: created_at og updated_at settes til now(); en verdi fra kalleren
--           ignoreres. En default alene ville bare gjelde når kolonnen utelates.
--   UPDATE: created_at bevares fra den eksisterende raden, updated_at settes
--           til now().
--
-- created_at betyr «når Antidep opprettet raden» (DATABASE_ARCHITECTURE.md
-- §7.3). Tidspunkter fra den eksterne virkeligheten hører til recorded_at eller
-- valid_from/valid_to, ikke hit, så det finnes ingen legitim grunn for en
-- kaller til å oppgi created_at.
--
-- Dette er en bevisst og snever trigger (DATABASE_ARCHITECTURE.md §60): den
-- skriver to tekniske metadatafelt på egen rad og inneholder ingen klinisk
-- logikk og ingen arbeidsflyt. Funksjonen er SECURITY INVOKER med tomt
-- search_path og uten EXECUTE til PUBLIC.
-- ----------------------------------------------------------------------------
create function catalog.set_row_timestamps()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

comment on function catalog.set_row_timestamps() is
  'Trigger-funksjon som gir databasen eierskap til created_at og updated_at på katalogtabellene, ved INSERT og UPDATE. Teknisk metadata; endrer ingen klinisk verdi.';

revoke execute on function catalog.set_row_timestamps() from public;

-- ----------------------------------------------------------------------------
-- 3. catalog.drugs — stabil identitet for virkestoff
--    (DATABASE_ARCHITECTURE.md §9, KNOWLEDGE_MODEL.md §4)
--
-- Raden representerer virkestoffet, ikke et norsk produkt. Handelsnavn, form,
-- styrke og markedsstatus hører til catalog.drug_products (migrasjon 009) og
-- skal kunne tidsavgrenses; ingenting av det legges på identiteten her.
-- ----------------------------------------------------------------------------
create table catalog.drugs (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  status catalog.drug_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint drugs_canonical_name_trimmed_check
    check (canonical_name = btrim(canonical_name)),
  constraint drugs_canonical_name_not_blank_check
    check (length(canonical_name) between 1 and 200)
);

comment on table catalog.drugs is
  'Stabil identitet for et virkestoff (Drug). Kanonisk navn er norsk bokmål. Aliaser, handelsnavn og historiske navn ligger i catalog.drug_names, eksterne identifikatorer i catalog.drug_identifiers.';
comment on column catalog.drugs.canonical_name is
  'Kanonisk virkestoffnavn på norsk bokmål, for eksempel sertralin. Unikt uavhengig av bokstavstørrelse.';
comment on column catalog.drugs.status is
  'Antideps forvaltningsstatus for virkestoffet. Ikke markedsstatus for et produkt.';
comment on column catalog.drugs.updated_at is
  'Tidspunkt for siste metadataendring på identitetsraden. Settes av catalog.set_updated_at().';

-- Kanonisk navn er en naturlig nøkkel og håndheves som UNIQUE, ikke som
-- primærnøkkel (DATABASE_ARCHITECTURE.md §8): navn kan korrigeres uten at
-- interne relasjoner brytes.
create unique index drugs_canonical_name_key
  on catalog.drugs (lower(canonical_name));

create trigger drugs_set_row_timestamps
  before insert or update on catalog.drugs
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 4. catalog.drug_identifiers — eksterne identifikatorer
--    (DATABASE_ARCHITECTURE.md §8)
--
-- Eksterne identifikatorer er egne relasjoner med unike constraints, aldri
-- intern primærnøkkel: de kan mangle, korrigeres og finnes i flere systemer.
-- Ett virkestoff kan dessuten ha flere koder i samme system — bupropion, som
-- står i utvidelsessettet i MVP_IMPLEMENTATION_PLAN.md §10, har både N06AX12 og
-- N07BA02 — så modellen kan ikke være én kolonne på catalog.drugs.
-- ----------------------------------------------------------------------------
create table catalog.drug_identifiers (
  id uuid primary key default gen_random_uuid(),
  drug_id uuid not null
    references catalog.drugs (id) on update restrict on delete restrict,
  identifier_system catalog.drug_identifier_system not null,
  identifier_value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint drug_identifiers_system_value_key
    unique (identifier_system, identifier_value),
  constraint drug_identifiers_atc_format_check
    check (
      identifier_system <> 'atc'
      or identifier_value ~ '^[A-Z][0-9]{2}[A-Z]{2}[0-9]{2}$'
    )
);

comment on table catalog.drug_identifiers is
  'Eksterne identifikatorer for et virkestoff, for eksempel WHO ATC-kode. Unik per (system, verdi), slik at samme kode ikke kan peke på to virkestoffer.';
comment on column catalog.drug_identifiers.identifier_value is
  'Verdien slik kildesystemet skriver den. ATC-koder valideres deklarativt mot formatet for femte nivå, for eksempel N06AB06.';

create index drug_identifiers_drug_id_idx
  on catalog.drug_identifiers (drug_id);

create trigger drug_identifiers_set_row_timestamps
  before insert or update on catalog.drug_identifiers
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 5. catalog.drug_names — aliaser, handelsnavn og historiske navn
--    (DATABASE_ARCHITECTURE.md §9)
--
-- Formålet er at søk skal treffe alternative navn uten at kanonisk identitet
-- endres. Unikhet gjelder innenfor (virkestoff, navnetype); det er bevisst
-- tillatt at samme navn finnes på to virkestoffer, fordi et tvetydig søketreff
-- skal kunne vises som tvetydig i stedet for å bli avvist ved import.
-- ----------------------------------------------------------------------------
create table catalog.drug_names (
  id uuid primary key default gen_random_uuid(),
  drug_id uuid not null
    references catalog.drugs (id) on update restrict on delete restrict,
  name text not null,
  name_type catalog.drug_name_type not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint drug_names_name_trimmed_check check (name = btrim(name)),
  constraint drug_names_name_not_blank_check check (length(name) between 1 and 200)
);

comment on table catalog.drug_names is
  'Alternative navn på et virkestoff med eksplisitt navnetype. Kanonisk navn ligger på catalog.drugs og gjentas ikke her som identitet.';
comment on column catalog.drug_names.name_type is
  'Navnetype. Handelsnavn registrert her er navnestrenger for søk; norske produktdata med form, styrke, markedsstatus og tidsvaliditet hører til catalog.drug_products i migrasjon 009.';

create unique index drug_names_drug_type_name_key
  on catalog.drug_names (drug_id, name_type, lower(name));

-- Søk slår opp på navn uavhengig av virkestoff, og kan derfor ikke bruke
-- indeksen over, som ledes av drug_id.
create index drug_names_name_idx on catalog.drug_names (lower(name));

create trigger drug_names_set_row_timestamps
  before insert or update on catalog.drug_names
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 6. catalog.clinical_concepts — kontrollert begrepsvokabular
--    (DATABASE_ARCHITECTURE.md §11, KNOWLEDGE_MODEL.md §6)
--
-- Hierarkiet organiserer innhold; det kopierer ikke klinisk innhold. Et
-- underbegrep arver ingen påstander og skal ikke duplisere dem.
--
-- Selvreferanse hindres deklarativt. Dypere sykluser (A → B → A) er en
-- cross-row-regel som ikke hører hjemme i en CHECK (DATABASE_ARCHITECTURE.md
-- §59) og er bevisst utsatt: i dette steget finnes ingen skrivevei til
-- catalog, så det finnes ingen skribent å beskytte mot. Vaktposten legges inn
-- sammen med den redaksjonelle skriveveien.
-- ----------------------------------------------------------------------------
create table catalog.clinical_concepts (
  id uuid primary key default gen_random_uuid(),
  canonical_label text not null,
  concept_type catalog.clinical_concept_type not null,
  parent_concept_id uuid
    references catalog.clinical_concepts (id) on update restrict on delete restrict,
  status catalog.vocabulary_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_concepts_label_trimmed_check
    check (canonical_label = btrim(canonical_label)),
  constraint clinical_concepts_label_not_blank_check
    check (length(canonical_label) between 1 and 200),
  constraint clinical_concepts_no_self_parent_check
    check (parent_concept_id is null or parent_concept_id <> id),
  -- Gjør begrepstypen refererbar, slik at andre tabeller kan kreve en bestemt
  -- type gjennom en fremmednøkkel i stedet for applikasjonsvalidering.
  constraint clinical_concepts_id_type_key unique (id, concept_type)
);

comment on table catalog.clinical_concepts is
  'Kontrollert vokabular for kliniske temaer som kunnskap kategoriseres og gjenfinnes på. Synonymer og oversettelser hører til en egen tabell når søk trenger dem.';
comment on column catalog.clinical_concepts.canonical_label is
  'Kanonisk etikett på norsk bokmål, for eksempel vektendring. Unik uavhengig av bokstavstørrelse.';
comment on column catalog.clinical_concepts.parent_concept_id is
  'Overordnet begrep, når hierarkiet gir mening. Hierarkiet organiserer innhold og kopierer ikke klinisk innhold.';

create unique index clinical_concepts_canonical_label_key
  on catalog.clinical_concepts (lower(canonical_label));

create index clinical_concepts_parent_concept_id_idx
  on catalog.clinical_concepts (parent_concept_id);

create trigger clinical_concepts_set_row_timestamps
  before insert or update on catalog.clinical_concepts
  for each row execute function catalog.set_row_timestamps();

-- ----------------------------------------------------------------------------
-- 7. catalog.populations — strukturerte gyldighetsgrenser
--    (DATABASE_ARCHITECTURE.md §12, KNOWLEDGE_MODEL.md §7)
--
-- Valgt normaliseringsgrad: én rad per navngitt populasjon, med de fire
-- dimensjonene DATABASE_ARCHITECTURE.md §12 nevner som egne kolonner — alder,
-- indikasjon/diagnose, graviditet/amming og sentral komorbiditet. Dimensjonene
-- er ikke krysset ut i egne rader, så modellen gir ingen kombinatorisk
-- eksplosjon: en ny populasjon koster én rad.
--
-- Semantikk for NULL: NULL betyr at populasjonen ikke er avgrenset på
-- dimensjonen. NULL betyr ikke «ukjent» og ikke «vurdert og funnet irrelevant»
-- (ANTIDEP_CONSTITUTION.md §6). Aldersgrensene er de faktiske
-- gyldighetsgrensene og kan spørres strukturert; etiketten er et lesbart
-- håndtak, ikke datagrunnlaget.
--
-- Bevisst utelatt fordi ingen påstand i første slice trenger det: kjønn,
-- organfunksjon som egen dimensjon (dekkes foreløpig av komorbiditet) og flere
-- samtidige komorbiditeter, som ville krevd en koblingstabell.
-- ----------------------------------------------------------------------------
create table catalog.populations (
  id uuid primary key default gen_random_uuid(),
  canonical_label text not null,
  age_min_years smallint,
  age_max_years smallint,
  indication_concept_id uuid,
  pregnancy_context catalog.population_pregnancy_context,
  comorbidity_concept_id uuid,
  status catalog.vocabulary_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Konstant kolonne som lar fremmednøklene under kreve concept_type =
  -- 'condition'. Dette holder typekravet deklarativt (DATABASE_ARCHITECTURE.md
  -- §57) i stedet for i applikasjonskode. Fremmednøklene bruker MATCH SIMPLE,
  -- så en NULL i begrepskolonnen slår av kravet for den raden.
  required_condition_type catalog.clinical_concept_type
    generated always as ('condition'::catalog.clinical_concept_type) stored,
  constraint populations_label_trimmed_check
    check (canonical_label = btrim(canonical_label)),
  constraint populations_label_not_blank_check
    check (length(canonical_label) between 1 and 200),
  constraint populations_age_min_range_check
    check (age_min_years is null or age_min_years between 0 and 120),
  constraint populations_age_max_range_check
    check (age_max_years is null or age_max_years between 0 and 120),
  constraint populations_age_interval_check
    check (
      age_min_years is null
      or age_max_years is null
      or age_max_years >= age_min_years
    ),
  constraint populations_indication_fkey
    foreign key (indication_concept_id, required_condition_type)
    references catalog.clinical_concepts (id, concept_type)
    on update restrict on delete restrict,
  constraint populations_comorbidity_fkey
    foreign key (comorbidity_concept_id, required_condition_type)
    references catalog.clinical_concepts (id, concept_type)
    on update restrict on delete restrict
);

comment on table catalog.populations is
  'Populasjonen en påstand eller et evidensfunn gjelder for, normalisert nok til at viktige gyldighetsgrenser kan spørres strukturert. NULL i en dimensjon betyr at populasjonen ikke er avgrenset på den dimensjonen, ikke at dimensjonen er ukjent.';
comment on column catalog.populations.canonical_label is
  'Kort lesbart håndtak, for eksempel voksne med depressiv lidelse. De strukturerte kolonnene er datagrunnlaget; etiketten er ikke en gyldighetsgrense.';
comment on column catalog.populations.age_min_years is
  'Nedre aldersgrense i hele år, inklusiv. NULL betyr ingen nedre grense.';
comment on column catalog.populations.age_max_years is
  'Øvre aldersgrense i hele år, inklusiv. NULL betyr ingen øvre grense.';
comment on column catalog.populations.indication_concept_id is
  'Indikasjon eller diagnose populasjonen er avgrenset til. Må være et begrep av typen condition; kravet håndheves av fremmednøkkelen mot (id, concept_type).';
comment on column catalog.populations.comorbidity_concept_id is
  'Sentral komorbiditet populasjonen er avgrenset til. Én dimensjon i denne versjonen; flere samtidige komorbiditeter krever en koblingstabell og legges til når en reell påstand trenger det.';
comment on column catalog.populations.required_condition_type is
  'Teknisk konstant som lar fremmednøklene kreve concept_type = condition. Ingen klinisk betydning.';

create unique index populations_canonical_label_key
  on catalog.populations (lower(canonical_label));

create index populations_indication_concept_id_idx
  on catalog.populations (indication_concept_id);

create index populations_comorbidity_concept_id_idx
  on catalog.populations (comorbidity_concept_id);

create trigger populations_set_row_timestamps
  before insert or update on catalog.populations
  for each row execute function catalog.set_row_timestamps();

-- Populasjonsdefinisjonen er uforanderlig (DATABASE_ARCHITECTURE.md §7).
--
-- En populasjon er en gyldighetsgrense, ikke bare en etikett: den avgjør hvem
-- en påstand eller et evidensfunn gjelder for (KNOWLEDGE_MODEL.md §7).
-- ClaimRevision og EvidenceItem peker på population_id, og revisjonene er
-- uforanderlige. Hvis de definerende feltene kunne endres etterpå, ville en
-- redigering her stille endre omfanget av all historikk som allerede peker hit,
-- uten at det ble opprettet en ny revisjon. Det er nøyaktig mønsteret §7 og
-- §7.1 forbyr.
--
-- Et endret omfang er derfor en ny populasjon: opprett en ny rad og sett den
-- gamle til status = 'deprecated'. Status og tidsstempler er bevisst utenfor
-- vernet, slik at utfasing er mulig uten å røre betydningen — utfasing er en
-- statusendring, ikke en sletting (DATABASE_ARCHITECTURE.md §36).
--
-- Dette er en immutable-row guard, som §60 navngir som en god triggerbruk.
-- Vernet gjelder også eieren. En reell datakorreksjon i en senere migrasjon må
-- derfor slå av triggeren eksplisitt, som en synlig og reviewbar handling.
--
-- Begrepshierarkiet er bevisst ikke vernet på samme måte: en ClinicalConcept
-- organiserer og gjenfinner innhold (§11) og er ikke en gyldighetsgrense for en
-- påstand, så en etikettkorreksjon der endrer ikke omfanget av historikk.
create function catalog.freeze_population_definition()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.canonical_label is distinct from old.canonical_label
    or new.age_min_years is distinct from old.age_min_years
    or new.age_max_years is distinct from old.age_max_years
    or new.indication_concept_id is distinct from old.indication_concept_id
    or new.pregnancy_context is distinct from old.pregnancy_context
    or new.comorbidity_concept_id is distinct from old.comorbidity_concept_id
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Populasjonsdefinisjonen for %L er uforanderlig og kan ikke endres.',
        old.canonical_label
      ),
      hint = 'Opprett en ny populasjon for det endrede omfanget, og sett den gamle til status = deprecated. Historikk som peker på den gamle populasjonen skal beholde sin opprinnelige betydning.';
  end if;

  return new;
end;
$$;

comment on function catalog.freeze_population_definition() is
  'Immutable-row guard: hindrer at de definerende feltene på en populasjon endres etter innsetting, slik at eksisterende ClaimRevision- og EvidenceItem-referanser beholder sin opprinnelige betydning. Status og tidsstempler kan endres.';

revoke execute on function catalog.freeze_population_definition() from public;

create trigger populations_freeze_definition
  before update on catalog.populations
  for each row execute function catalog.freeze_population_definition();

-- ----------------------------------------------------------------------------
-- 8. RLS og grants (DATABASE_ARCHITECTURE.md §5, §48, §73)
--
-- RLS aktiveres på alle nye tabeller og er default deny: uten policy gir
-- tabellen ingen rader til noen rolle som ikke eier den. Ingen policy skrives
-- her. Redaksjonell lesetilgang forutsetter medlemskapsmodellen i migrasjon
-- 005, og klientlesing skal uansett gå gjennom publiserte projeksjoner i api
-- (migrasjon 007), ikke direkte mot catalog.
--
-- Nye tabeller får ingen privilegier til klientrollene i PostgreSQL, men
-- grensen skrives eksplisitt, som i migrasjon 001, slik at den er lesbar her og
-- testbar etterpå.
-- ----------------------------------------------------------------------------
alter table catalog.drugs enable row level security;
alter table catalog.drug_identifiers enable row level security;
alter table catalog.drug_names enable row level security;
alter table catalog.clinical_concepts enable row level security;
alter table catalog.populations enable row level security;

revoke all privileges on all tables in schema catalog from public;
revoke all privileges on all tables in schema catalog
  from anon, authenticated, service_role;

-- ============================================================================
-- 9. Katalogdata for første golden slice
--    (MVP_IMPLEMENTATION_PLAN.md §12, §19)
--
-- Plassering: disse radene ligger i migrasjonen, ikke i supabase/seed.sql.
-- De er kontrollert vokabular og pilotdata som produksjonen er avhengig av —
-- Claims, evidensrelasjoner og publiserte projeksjoner får fremmednøkler hit —
-- og seed.sql kjøres bare ved lokal `db reset`. supabase/seed.sql er reservert
-- for rent lokal demodata.
--
-- Omfang: nøyaktig det den første slicen trenger, sertralin + mirtazapin ×
-- vektendring. Ingen øvrige pilotlegemidler, ingen øvrige pilottemaer, og ingen
-- norske produktdata: handelsnavn, former, styrker og markedsstatus er
-- tidsavgrensede produktfakta som hører til catalog.drug_products og
-- FEST-importen i migrasjon 009 og skal ikke skrives inn for hånd her.
--
-- Ingen kliniske påstander seedes. Radene under er strukturelle
-- katalogoppføringer og deterministiske identifikatorer, ikke evidensbaserte
-- synteser (ANTIDEP_CONSTITUTION.md §5).
--
-- Radene får databasegenererte uuid-er. Senere migrasjoner og tester refererer
-- til dem via de unike naturlige nøklene, ikke via hardkodede uuid-er.
-- ============================================================================

insert into catalog.drugs (canonical_name, status)
values
  ('sertralin', 'active'),
  ('mirtazapin', 'active');

-- INN-formene på engelsk, slik at søk treffer internasjonal skrivemåte.
-- Dette er språkvarianter av virkestoffnavnet, ikke norske produktdata.
insert into catalog.drug_names (drug_id, name, name_type)
select d.id, v.name, 'alias'::catalog.drug_name_type
from (values
  ('sertralin', 'sertraline'),
  ('mirtazapin', 'mirtazapine')
) as v(canonical_name, name)
join catalog.drugs d on d.canonical_name = v.canonical_name;

-- ATC-koder på femte nivå fra WHO Collaborating Centre for Drug Statistics
-- Methodology. Deterministiske eksterne identifikatorer
-- (ANTIDEP_CONSTITUTION.md §5, punkt 1).
insert into catalog.drug_identifiers (drug_id, identifier_system, identifier_value)
select d.id, 'atc'::catalog.drug_identifier_system, v.atc_code
from (values
  ('sertralin', 'N06AB06'),
  ('mirtazapin', 'N06AX11')
) as v(canonical_name, atc_code)
join catalog.drugs d on d.canonical_name = v.canonical_name;

-- Begrepene den første slicen trenger: temaet den handler om, og diagnosen som
-- avgrenser populasjonen. Underbegreper av vektendring legges til når de første
-- påstandene faktisk krever dem.
insert into catalog.clinical_concepts (canonical_label, concept_type, status)
values
  ('vektendring', 'outcome', 'active'),
  ('depressiv lidelse', 'condition', 'active');

insert into catalog.populations (canonical_label, age_min_years, indication_concept_id)
select
  'voksne med depressiv lidelse',
  18,
  c.id
from catalog.clinical_concepts c
where c.canonical_label = 'depressiv lidelse';
