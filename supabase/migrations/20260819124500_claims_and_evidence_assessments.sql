-- ============================================================================
-- Antidep migrasjon 004 — Claims, evidenslenker og evidensvurderinger
--
-- Formål: etablere påstanden som kunnskapsbasens grunnenhet — stabil identitet
-- med uforanderlige revisjoner — den typede koblingen mellom en revisjon og et
-- konkret evidensfunn, og den eksplisitte vurderingen av hvor sikkert
-- grunnlaget er. Migrasjonen registrerer i tillegg de påstandene, lenkene og
-- vurderingene den første golden slicen trenger (sertralin + mirtazapin ×
-- vektendring), knyttet til de to evidensfunnene migrasjon 003 la inn.
--
-- Styrende dokumenter:
--   docs/ANTIDEP_CONSTITUTION.md
--     §4  enhver klinisk relevant påstand skal være etterprøvbar, og koblingen
--         skal dokumentere hvordan kilden støtter, nyanserer eller motsier den
--     §5  tre kunnskapstyper med ulik epistemisk status
--     §6  gradert usikkerhet; «ingen vurderbar evidens» er en egen systemtilstand
--     §7  påstanden, ikke monografien, er grunnenheten
--     §8  evidens og proveniens er førsteklasses data
--     §9  motstridende evidens bevares
--     §12 KI foreslår; mennesker har det faglige ansvaret
--     §13 alt publisert innhold har en eksplisitt livssyklus
--     §14 endringer skal være reversible, attribuerte og rapporterbare
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §12 første golden slice
--     §21 innholdet i denne migrasjonen
--     §29 Slice 1
--     §41-§42 teststrategi og kritiske negative tester
--     §47-§50 sikkerhet og tilgang
--   docs/DATABASE_ARCHITECTURE.md
--     §7 + §7.1-§7.2 stabil identitet, uforanderlige revisjoner, peker fremfor kopi
--     §13 knowledge.claims, §14 + §14.1 knowledge.claim_revisions og content_hash
--     §15 livssyklusen skal ikke skjules i ett muterbart statusfelt
--     §21 knowledge.claim_evidence_links, §22 knowledge.evidence_assessments
--     §23 kliniske anbefalinger er claims med strengere krav
--     §36-§37 ingen normal DELETE, RESTRICT på fremmednøkler
--     §57-§60 deklarative constraints, cross-row-regler og triggerbruk
--     §67 database-testing
--   docs/KNOWLEDGE_MODEL.md §8 (Claim), §9 (ClaimRevision), §12
--     (ClaimEvidenceLink), §13 (EvidenceAssessment), §19 (revisjonsmodell)
--
-- Avgrensning (MVP_IMPLEMENTATION_PLAN.md §21-§26):
--   Ingen review-, verifikasjons- eller proveniensobjekter (005), ingen
--   publisering og ingen knowledge.publication_events (006), ingen api-views
--   (007), ingen audit.events (008) og ingen ingest (009).
--   Ingen RLS-policies: medlemskapsmodellen (workflow.user_roles) kommer i
--   migrasjon 005. Tabellene er default deny uten unntak i dette steget.
--
--   created_by_actor_id (§13, §14, §21, §22) opprettes ikke. provenance.actors
--   finnes ikke ennå og hører til migrasjon 005; knowledge.evidence_items
--   mangler kolonnen av nøyaktig samme grunn. Konsekvensen er reell og skal
--   ikke pyntes over: ingen rad denne migrasjonen oppretter kan si hvem eller
--   hva som formulerte den. Kolonnene legges til i 005, sammen med aktørene de
--   skal peke på og med verifikasjons- og reviewhendelsene som gjør
--   ANTIDEP_CONSTITUTION.md §12 og §14 håndhevbare. Fram til da er radene under
--   KI-utarbeidede forslag, og ingenting i databasen kan publisere dem: det
--   finnes verken review, publiseringspeker satt, publiseringshendelser eller
--   api-projeksjon.
--
--   knowledge.recommendation_details (§23) opprettes ikke: ingen av de to
--   evidensfunnene i første slice bærer en klinisk anbefaling, bare
--   evidenssynteser. Modellen sperrer ikke for anbefalinger — knowledge_type
--   dekker dem, og de strengere kravene deres er review- og publiseringsgater
--   (005/006), ikke egne kolonner her.
--
-- Konvensjonene fra migrasjon 001 gjelder og håndheves av
-- supabase/tests/030_conventions_test.sql: én databasegenerert uuid som
-- primærnøkkel, timestamptz overalt, created_at med default now(), RLS aktivert
-- og ingen grants til anon/authenticated/service_role/PUBLIC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Kontrollerte vokabularer
--
-- Som i migrasjon 002 og 003 håndheves vokabularene som enum, altså på
-- datatypenivå, øverst i prioriteringsrekkefølgen i DATABASE_ARCHITECTURE.md
-- §57. Det åpne spørsmålet om enum kontra oppslagstabell (§72) vokser med
-- ytterligere sju typer her og bør avgjøres før api-projeksjonene i migrasjon
-- 007 begynner å eksponere verdiene.
--
-- Der et vokabular fra migrasjon 003 dekker samme akse, gjenbrukes det framfor
-- å bli kopiert: knowledge.comparator_kind, knowledge.effect_measure og
-- knowledge.estimate_unit brukes av claim_revisions nedenfor.
-- knowledge.effect_direction gjenbrukes derimot ikke — se
-- knowledge.claim_direction.
-- ----------------------------------------------------------------------------

create type knowledge.knowledge_type as enum (
  'deterministic_fact',
  'evidence_synthesis',
  'clinical_recommendation'
);

comment on type knowledge.knowledge_type is
  'De tre kunnskapstypene i ANTIDEP_CONSTITUTION.md §5: deterministic_fact (kan avgjøres direkte mot en autoritativ eller strukturert kilde, for eksempel ATC-kode eller legemiddelform), evidence_synthesis (fortolkende sammenfatning av ett eller flere evidensfunn) og clinical_recommendation (normativ påstand om hva klinikeren bør gjøre). Typene har ulik epistemisk status og ulike valideringskrav, og skal aldri presenteres som likeverdige. Typen ligger på identiteten, ikke på revisjonen: endres den, er det en annen påstand.';

create type knowledge.claim_direction as enum (
  'increase',
  'decrease',
  'no_clear_difference'
);

comment on type knowledge.claim_direction is
  'Retningen Antidep selv konkluderer med i en påstand: increase, decrease eller no_clear_difference. Vokabularet er bevisst ikke knowledge.effect_direction, som beskriver retningen én kilde rapporterer for ett funn; en påstand er Antideps syntese på tvers av grunnlaget og har derfor en annen epistemisk status (ANTIDEP_CONSTITUTION.md §5). Verdien not_stated finnes ikke her, fordi NULL allerede betyr at påstanden ikke uttrykker en strukturert retning, og to måter å si det samme på ville gjort tilstanden tvetydig. no_clear_difference er et resultat — grunnlaget viser ingen klar forskjell — og er noe annet enn at evidensen ikke kan vurderes; den tilstanden ligger i knowledge.certainty_level.';

create type knowledge.claim_evidence_relationship as enum (
  'supports',
  'partially_supports',
  'contradicts',
  'neutral_contextual',
  'indirect'
);

comment on type knowledge.claim_evidence_relationship is
  'Hvordan et evidensfunn forholder seg til en bestemt påstandsrevisjon: supports (underbygger påstanden slik den er formulert), partially_supports (underbygger deler av den, for eksempel retningen men ikke størrelsen), contradicts (taler mot den), neutral_contextual (funnet er relevant og belyser spørsmålet, men taler verken for eller mot påstanden) og indirect. De fire første er stance-verdiene i KNOWLEDGE_MODEL.md §12. indirect er med fordi DATABASE_ARCHITECTURE.md §21 krever verdien, og betyr at funnets forhold til påstanden bare kan bedømmes indirekte; verdien forutsetter derfor directness = indirect. Et funn som treffer påstanden direkte, men verken støtter eller motsier den, er neutral_contextual med directness = direct — det er stance-aksen som bærer nøytraliteten, ikke indirekthetsaksen. Motstridende lenker er like bevaringsverdige som støttende (ANTIDEP_CONSTITUTION.md §9), og systemet krever aldri at alle lenker på en revisjon har samme verdi (KNOWLEDGE_MODEL.md §13.2).';

create type knowledge.evidence_directness as enum ('direct', 'indirect');

comment on type knowledge.evidence_directness is
  'Om evidensfunnet treffer påstandens populasjon, endepunkt, komparator og tidsrom direkte, eller bare indirekte. KNOWLEDGE_MODEL.md §12 lister directness som et eget minimumsfelt ved siden av stance, mens DATABASE_ARCHITECTURE.md §21 folder indirekthet inn i relationship_type. Begge aksene finnes derfor her: uten en egen directness ville et indirekte funn som motsier påstanden ikke kunne uttrykkes, og motstridende evidens skal bevares (ANTIDEP_CONSTITUTION.md §9). Avviket mellom de to dokumentene bør ryddes i ett av dem.';

create type knowledge.assessment_framework as enum ('grade');

comment on type knowledge.assessment_framework is
  'Metoden evidensvurderingen bruker. Foreløpig bare grade (GRADE), som ANTIDEP_CONSTITUTION.md §6 navngir. Andre eksplisitte metoder legges til av migrasjonen som faktisk trenger dem; fram til da vil et forsøk på å registrere en annen metode feile synlig i stedet for å bli klassifisert feil.';

create type knowledge.certainty_level as enum (
  'high',
  'moderate',
  'low',
  'very_low',
  'no_assessable_evidence'
);

comment on type knowledge.certainty_level is
  'Sikkerheten i kunnskapsgrunnlaget for en påstandsrevisjon. De fire første er GRADE-kategoriene ANTIDEP_CONSTITUTION.md §6 krever: høy, moderat, lav og svært lav sikkerhet. no_assessable_evidence er den separate systemtilstanden §6 og KNOWLEDGE_MODEL.md §13.1 krever: det finnes ikke tilstrekkelig grunnlag til å gjøre en vurdering i det hele tatt. Den tilstanden er ikke svært lav sikkerhet, ikke liten effekt, ikke ingen forskjell og ikke lav risiko. Kolonnen som bruker typen er NOT NULL, slik at tilstanden aldri kan kollapse til en naken NULL.';

create type knowledge.grade_domain_rating as enum (
  'not_serious',
  'serious',
  'very_serious',
  'not_assessable'
);

comment on type knowledge.grade_domain_rating is
  'Vurderingen av ett GRADE-domene: not_serious, serious eller very_serious. not_assessable er med fordi et domene kan være umulig å vurdere — konsistens og publikasjonsskjevhet kan for eksempel ikke bedømmes ut fra én enkelt studie — og å registrere det som not_serious ville vært falsk presisjon (ANTIDEP_CONSTITUTION.md §6). not_assessable for ett domene er ikke det samme som no_assessable_evidence for hele vurderingen.';

-- PUBLIC har som standard usage på nye typer. Antidep gir privilegier eksplisitt
-- (DATABASE_ARCHITECTURE.md §5), som i migrasjon 001, 002 og 003.
revoke usage on type
  knowledge.knowledge_type,
  knowledge.claim_direction,
  knowledge.claim_evidence_relationship,
  knowledge.evidence_directness,
  knowledge.assessment_framework,
  knowledge.certainty_level,
  knowledge.grade_domain_rating
  from public;

-- ----------------------------------------------------------------------------
-- 2. Felles immutable-row guard for de append-only tabellene
--
-- Migrasjon 003 innførte knowledge.reject_evidence_item_mutation() for én
-- tabell. Denne migrasjonen legger til tre append-only tabeller, og tre nesten
-- identiske funksjoner ville bare gitt tre steder å vedlikeholde samme regel.
-- Funksjonen under er derfor generisk: den bruker tabellnavnet fra
-- triggerkonteksten og tar hintet — den faktiske korreksjonsveien for tabellen
-- — som triggerargument.
--
-- Dette er fortsatt en snever immutable-row guard, som DATABASE_ARCHITECTURE.md
-- §60 navngir som god triggerbruk. Den inneholder ingen klinisk logikk og ingen
-- arbeidsflyt. Migrasjon 003 sin funksjon står urørt; å skrive om et allerede
-- reviewet vern hører ikke til denne endringen.
--
-- Vernet gjelder også eieren av tabellen. En reell vedlikeholdsoperasjon må slå
-- av triggeren eksplisitt, som en synlig og reviewbar handling.
-- ----------------------------------------------------------------------------
create function knowledge.reject_append_only_mutation()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  raise exception using
    errcode = 'restrict_violation',
    message = format(
      '%I.%I er append-only; %s av rad %L er ikke tillatt.',
      tg_table_schema, tg_table_name, tg_op, old.id
    ),
    hint = coalesce(
      tg_argv[0],
      'Registrer en ny rad for det korrigerte innholdet. Eksisterende rader dokumenterer hva som faktisk ble registrert, og skal verken overskrives eller slettes.'
    );
end;
$$;

comment on function knowledge.reject_append_only_mutation() is
  'Immutable-row guard: gjør en tabell append-only ved å avvise både UPDATE og DELETE. Triggerargumentet er hintet som beskriver den riktige korreksjonsveien for den konkrete tabellen.';

revoke execute on function knowledge.reject_append_only_mutation() from public;

-- ----------------------------------------------------------------------------
-- 3. knowledge.claims — stabil identitet for en påstand
--    (DATABASE_ARCHITECTURE.md §7, §13, KNOWLEDGE_MODEL.md §8)
--
-- Raden er identiteten, ikke innholdet: formulering, populasjon, retning og
-- forbehold ligger i knowledge.claim_revisions. claim_id forblir stabilt selv
-- om formuleringen endres (KNOWLEDGE_MODEL.md §8).
--
-- Ingen status-kolonne. DATABASE_ARCHITECTURE.md §15 er eksplisitt på at
-- livssyklusen ikke skal skjules i ett muterbart statusfelt, og §13 sitt
-- minimum har derfor current_published_revision_id og retired_at framfor
-- status. Dette er et bevisst avvik fra KNOWLEDGE_MODEL.md §8, som lister
-- status som minimumsfelt: en avledet «nåværende status» skal bygges av
-- publiseringspekeren, retired_at, review-beslutningene (migrasjon 005) og
-- publiseringshendelsene (006), slik at mellomtilstandene ikke går tapt.
-- Avviket bør ryddes i KNOWLEDGE_MODEL.md.
--
-- subject_drug_id er ikke i §13 sin minimumsliste, men ANTIDEP_CONSTITUTION.md
-- §7 krever at påstandsobjektet minst kan beskrive berørte virkestoffer, og
-- både legemiddelvisningen og sammenligningen i MVP_IMPLEMENTATION_PLAN.md §12
-- slår opp påstander per virkestoff. Virkestoffet ligger på identiteten fordi
-- en endring av det ville gitt en annen påstand, ikke en ny versjon av den
-- samme. Komparatoren, som kan endres uten at identiteten gjør det, ligger
-- derimot på revisjonen.
--
-- Bevisst utelatt: påstander som gjelder en legemiddelklasse eller flere
-- virkestoff samtidig. Det krever en koblingstabell, og ingen påstand i første
-- slice trenger det. En slik tabell kan legges til uten å endre modellen her.
-- ----------------------------------------------------------------------------
create table knowledge.claims (
  id uuid primary key default gen_random_uuid(),
  knowledge_type knowledge.knowledge_type not null,
  topic_concept_id uuid not null
    references catalog.clinical_concepts (id) on update restrict on delete restrict,
  subject_drug_id uuid not null
    references catalog.drugs (id) on update restrict on delete restrict,
  current_published_revision_id uuid,
  retired_at timestamptz,
  retirement_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Gjør identiteten refererbar fra revisjonene, slik at speilkolonnene der
  -- ikke kan komme ut av takt med identiteten (se knowledge.claim_revisions).
  constraint claims_id_type_subject_key
    unique (id, knowledge_type, subject_drug_id),

  -- En påstand som trekkes tilbake skal ikke kunne bli det stille, på samme
  -- måte som en kilde ikke kan settes til retracted uten begrunnelse
  -- (DATABASE_ARCHITECTURE.md §58, ANTIDEP_CONSTITUTION.md §14).
  constraint claims_retirement_note_required_check
    check ((retired_at is null) = (retirement_note is null)),
  constraint claims_retirement_note_not_blank_check
    check (retirement_note is null
           or (retirement_note = btrim(retirement_note)
               and length(retirement_note) between 1 and 1000))
);

comment on table knowledge.claims is
  'Stabil identitet for én selvstendig klinisk relevant påstand (ANTIDEP_CONSTITUTION.md §7). Innholdet ligger i knowledge.claim_revisions; denne raden bærer kunnskapstype, tema, berørt virkestoff, publiseringspeker og eventuell tilbaketrekking. Raden har bevisst ingen status-kolonne: livssyklusen avledes av pekeren, retired_at, review-beslutninger og publiseringshendelser (DATABASE_ARCHITECTURE.md §15).';
comment on column knowledge.claims.knowledge_type is
  'Kunnskapstypen påstanden klassifiseres som (ANTIDEP_CONSTITUTION.md §5). Ligger på identiteten fordi typen bestemmer hvilke valideringskrav påstanden er underlagt; en endring av den er en annen påstand, ikke en ny revisjon. Speiles på revisjonene og på evidensvurderingen gjennom sammensatte fremmednøkler.';
comment on column knowledge.claims.topic_concept_id is
  'Det kliniske begrepet påstanden hører under, for eksempel vektendring. Begrepstypen er bevisst ikke låst: en påstand kan like gjerne handle om en tilstand eller en farmakokinetisk egenskap som om et utfall.';
comment on column knowledge.claims.subject_drug_id is
  'Virkestoffet påstanden handler om (ANTIDEP_CONSTITUTION.md §7). Én påstand gjelder ett virkestoff i denne versjonen; klasse- eller flerstoffpåstander krever en koblingstabell og legges til når en reell påstand trenger det.';
comment on column knowledge.claims.current_published_revision_id is
  'Den eksakte revisjonen som er publisert nå, eller NULL når ingenting er publisert (DATABASE_ARCHITECTURE.md §7.2). Den sammensatte fremmednøkkelen sikrer at pekeren bare kan peke på en revisjon av denne påstanden. Selve publiseringsgaten — hvem som kan flytte pekeren, og hvilke krav som må være oppfylt først — hører til migrasjon 006 sammen med knowledge.publication_events.';
comment on column knowledge.claims.retired_at is
  'Når påstanden ble trukket ut av bruk. Tilbaketrekking er en statusendring, ikke en sletting: revisjonene og evidenslenkene består (DATABASE_ARCHITECTURE.md §36).';
comment on column knowledge.claims.retirement_note is
  'Begrunnelse for tilbaketrekkingen. Påkrevd når retired_at er satt, og forbudt ellers, slik at en påstand ikke kan forsvinne fra bruk uten spor.';

create index claims_subject_drug_topic_idx
  on knowledge.claims (subject_drug_id, topic_concept_id);
create index claims_topic_concept_id_idx on knowledge.claims (topic_concept_id);
create index claims_current_published_revision_id_idx
  on knowledge.claims (current_published_revision_id);

create trigger claims_set_row_timestamps
  before insert or update on knowledge.claims
  for each row execute function catalog.set_row_timestamps();

-- Identiteten er uforanderlig (DATABASE_ARCHITECTURE.md §7).
--
-- Kunnskapstype, tema og virkestoff er det som gjør påstanden til nettopp denne
-- påstanden. Kunne de endres i ettertid, ville all publisert historikk som
-- peker på claim_id stille fått et annet innhold uten at det ble opprettet en
-- ny revisjon — nøyaktig mønsteret §7 og §7.1 forbyr. Et endret tema eller
-- virkestoff er en ny påstand.
--
-- Publiseringspekeren, tilbaketrekkingen og tidsstemplene er bevisst utenfor
-- vernet: de er livssyklus, ikke identitet, og skal kunne endres uten at
-- betydningen av påstanden røres.
--
-- Dette er samme mønster som catalog.freeze_population_definition() i migrasjon
-- 002, og en av triggerbrukene DATABASE_ARCHITECTURE.md §60 navngir som god.
create function knowledge.freeze_claim_identity()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.knowledge_type is distinct from old.knowledge_type
    or new.topic_concept_id is distinct from old.topic_concept_id
    or new.subject_drug_id is distinct from old.subject_drug_id
  then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Identiteten til påstand %L er uforanderlig og kan ikke endres.', old.id
      ),
      hint = 'Opprett en ny påstand for det endrede temaet, virkestoffet eller kunnskapstypen, og trekk den gamle tilbake med retired_at og en begrunnelse. Revisjoner, evidenslenker og publiseringshistorikk som peker på den gamle påstanden skal beholde sin opprinnelige betydning.';
  end if;

  return new;
end;
$$;

comment on function knowledge.freeze_claim_identity() is
  'Immutable-row guard: hindrer at kunnskapstype, tema og virkestoff på en påstand endres etter innsetting, slik at revisjoner og publiseringshistorikk som peker på identiteten beholder sin opprinnelige betydning. Publiseringspeker, tilbaketrekking og tidsstempler kan endres.';

revoke execute on function knowledge.freeze_claim_identity() from public;

create trigger claims_freeze_identity
  before update on knowledge.claims
  for each row execute function knowledge.freeze_claim_identity();

-- ----------------------------------------------------------------------------
-- 4. knowledge.claim_revisions — én uforanderlig faglig versjon
--    (DATABASE_ARCHITECTURE.md §14, KNOWLEDGE_MODEL.md §9, §19)
--
-- Revisjonen bærer den presise formuleringen og den strukturerte betydningen.
-- KNOWLEDGE_MODEL.md §9.2 krever struktur før fritekst: populasjon, tidsramme,
-- komparator, retning og størrelse skal ikke bare finnes inne i statement.
--
-- Speilkolonner (knowledge_type, subject_drug_id): begge er låst til
-- identitetsraden av én sammensatt fremmednøkkel og kan derfor ikke komme ut av
-- takt med den. De finnes fordi de gjør to reelle regler deklarative i stedet
-- for å kreve trigger eller applikasjonskode (DATABASE_ARCHITECTURE.md §57,
-- §59):
--   * en påstand kan ikke ha seg selv som komparator, og
--   * en evidenssyntese eller klinisk anbefaling må ha en eksplisitt
--     usikkerhetstekst (ANTIDEP_CONSTITUTION.md §6).
-- Speilet er ikke en selvstendig sannhet: fremmednøkkelen med ON UPDATE
-- RESTRICT gjør at verdien verken kan settes feil eller endres senere.
--
-- Bevisst utelatt i dette steget:
--   * created_by_actor_id — provenance.actors kommer i migrasjon 005, se
--     avgrensningen øverst.
--   * timeframe_code (§14) — et kodet tidsvokabular som short_term/long_term
--     krever en klinisk grensedragning ingen kilde i denne slicen belegger.
--     Tidsrommet lagres derfor som det evidensgrunnlaget faktisk dokumenterer,
--     et intervall. Et kodet vokabular legges til av migrasjonen som trenger det.
--   * usikkerhetsintervall rundt magnitude — §14 lister det ikke, og ingen
--     påstand i første slice bærer en tallfestet størrelse i det hele tatt.
-- ----------------------------------------------------------------------------
create table knowledge.claim_revisions (
  id uuid primary key default gen_random_uuid(),

  -- Identitet og versjonering.
  -- claim_id har både en egen fremmednøkkel og inngår i speil-fremmednøkkelen
  -- lenger nede. Den enkle nøkkelen er beholdt fordi den er den faktiske
  -- forelder-barn-relasjonen og bør være lesbar som det; den sammensatte
  -- håndhever i tillegg at speilkolonnene stemmer med identiteten.
  claim_id uuid not null
    references knowledge.claims (id) on update restrict on delete restrict,
  revision_number integer not null,
  knowledge_type knowledge.knowledge_type not null,
  subject_drug_id uuid not null,
  supersedes_revision_id uuid,

  -- Formulering
  statement text not null,
  scope text not null,

  -- Strukturert betydning
  population_id uuid
    references catalog.populations (id) on update restrict on delete restrict,
  timeframe_min interval,
  timeframe_max interval,
  comparator_kind knowledge.comparator_kind not null,
  comparator_drug_id uuid
    references catalog.drugs (id) on update restrict on delete restrict,
  direction knowledge.claim_direction,
  magnitude_measure knowledge.effect_measure,
  magnitude_value numeric,
  magnitude_unit knowledge.estimate_unit,

  -- Forbehold og usikkerhet
  qualifiers text,
  uncertainty_summary text,

  content_hash text not null,
  created_at timestamptz not null default now(),

  -- Unik revisjonsnummerering per påstand (DATABASE_ARCHITECTURE.md §14, §58).
  constraint claim_revisions_claim_number_key unique (claim_id, revision_number),
  constraint claim_revisions_revision_number_positive_check
    check (revision_number > 0),

  -- Gjør (id, claim_id) refererbar, slik at både publiseringspekeren på
  -- knowledge.claims og supersedes_revision_id under kan kreve deklarativt at
  -- de peker på en revisjon av riktig identitet. Cross-row-regel løst med
  -- sammensatt fremmednøkkel, ikke med CHECK (DATABASE_ARCHITECTURE.md §59).
  constraint claim_revisions_id_claim_key unique (id, claim_id),
  -- Gjør (id, knowledge_type) refererbar, slik at knowledge.evidence_assessments
  -- kan kreve at den vurderte revisjonen faktisk er av en type som skal ha en
  -- evidensvurdering (KNOWLEDGE_MODEL.md §13).
  constraint claim_revisions_id_type_key unique (id, knowledge_type),

  -- Speilet er låst til identitetsraden.
  constraint claim_revisions_claim_fkey
    foreign key (claim_id, knowledge_type, subject_drug_id)
    references knowledge.claims (id, knowledge_type, subject_drug_id)
    on update restrict on delete restrict,

  -- En revisjon kan ikke erstatte seg selv, og den erstattede revisjonen må
  -- tilhøre den samme påstanden (DATABASE_ARCHITECTURE.md §14).
  constraint claim_revisions_no_self_supersession_check
    check (supersedes_revision_id is null or supersedes_revision_id <> id),
  constraint claim_revisions_supersedes_fkey
    foreign key (supersedes_revision_id, claim_id)
    references knowledge.claim_revisions (id, claim_id)
    on update restrict on delete restrict,

  -- Komparator: samme akse som på evidensfunnene, med samme deklarative regel.
  constraint claim_revisions_comparator_drug_check
    check ((comparator_kind = 'drug') = (comparator_drug_id is not null)),
  constraint claim_revisions_comparator_differs_check
    check (comparator_drug_id is null or comparator_drug_id <> subject_drug_id),

  -- Tidsrommet er et intervall, og et invertert eller negativt intervall er en
  -- feil (DATABASE_ARCHITECTURE.md §58).
  constraint claim_revisions_timeframe_pairing_check
    check ((timeframe_min is null) = (timeframe_max is null)),
  constraint claim_revisions_timeframe_positive_check
    check (timeframe_min is null or timeframe_min > interval '0'),
  constraint claim_revisions_timeframe_interval_check
    check (timeframe_min is null or timeframe_max >= timeframe_min),

  -- Størrelse: samme regler som på evidensfunnene, slik at en påstand ikke kan
  -- bære et tall som er mindre tolkbart enn tallene under den.
  constraint claim_revisions_magnitude_requires_measure_check
    check (magnitude_value is null or magnitude_measure is not null),
  constraint claim_revisions_magnitude_unit_check
    check (
      case
        when magnitude_measure is null then magnitude_unit is null
        when magnitude_measure in ('mean_change', 'mean_difference')
          then magnitude_unit is not null
        else magnitude_unit is null
      end
    ),
  constraint claim_revisions_magnitude_ratio_positive_check
    check (magnitude_measure is null
           or magnitude_measure not in ('risk_ratio', 'odds_ratio')
           or coalesce(magnitude_value, 1) > 0),
  -- Et effektmål uten tallverdi ville lovet en kvantifisering påstanden ikke
  -- har. Størrelsen er enten strukturert i sin helhet, eller ikke oppgitt.
  constraint claim_revisions_magnitude_measure_requires_value_check
    check (magnitude_measure is null or magnitude_value is not null),

  -- ANTIDEP_CONSTITUTION.md §6: en evidensbasert syntese skal ha en eksplisitt
  -- usikkerhetsvurdering, og det gjelder desto mer for en klinisk anbefaling.
  -- Et deterministisk faktum kan stå uten, framfor å bli påtvunget en
  -- innholdsløs standardtekst.
  constraint claim_revisions_uncertainty_required_check
    check (knowledge_type = 'deterministic_fact' or uncertainty_summary is not null),

  -- Tekstfelter
  constraint claim_revisions_statement_check
    check (statement = btrim(statement) and length(statement) between 1 and 2000),
  constraint claim_revisions_scope_check
    check (scope = btrim(scope) and length(scope) between 1 and 2000),
  constraint claim_revisions_qualifiers_check
    check (qualifiers is null
           or (qualifiers = btrim(qualifiers) and length(qualifiers) between 1 and 4000)),
  constraint claim_revisions_uncertainty_summary_check
    check (uncertainty_summary is null
           or (uncertainty_summary = btrim(uncertainty_summary)
               and length(uncertainty_summary) between 1 and 4000)),

  -- Hashen er selvbeskrivende og versjonert, som på evidensfunnene: definisjonen
  -- av hva som hashes kan endres av en senere migrasjon uten at gamle verdier
  -- blir tvetydige. Den er bevisst ikke UNIQUE; se triggeren under.
  constraint claim_revisions_content_hash_format_check
    check (content_hash ~ '^sha256-v[0-9]+:[0-9a-f]{64}$')
);

comment on table knowledge.claim_revisions is
  'Én uforanderlig faglig versjon av en påstand: den kanoniske formuleringen og den strukturerte betydningen — populasjon, tidsrom, komparator, retning, størrelse, forbehold og usikkerhet. Raden kan verken endres eller slettes etter innsetting; en rettelse er en ny revisjon (DATABASE_ARCHITECTURE.md §7.1).';
comment on column knowledge.claim_revisions.revision_number is
  'Monotont versjonsnummer innenfor påstanden, fra 1 og oppover. Unikt per påstand, slik at to revisjoner ikke kan påstå å være samme versjon.';
comment on column knowledge.claim_revisions.knowledge_type is
  'Speil av kunnskapstypen på identitetsraden, låst av den sammensatte fremmednøkkelen. Finnes for at kravet om eksplisitt usikkerhetstekst skal kunne håndheves deklarativt på raden selv, og for at en evidensvurdering skal kunne kreve riktig type. Ikke en selvstendig sannhet.';
comment on column knowledge.claim_revisions.subject_drug_id is
  'Speil av virkestoffet på identitetsraden, låst av den sammensatte fremmednøkkelen. Finnes for at regelen om at en påstand ikke kan være sin egen komparator skal kunne håndheves deklarativt. Ikke en selvstendig sannhet.';
comment on column knowledge.claim_revisions.supersedes_revision_id is
  'Revisjonen denne erstatter, når den er en videreføring. Må tilhøre samme påstand; kravet håndheves av den sammensatte fremmednøkkelen. NULL på første revisjon og på revisjoner som ikke er skrevet som videreføring av en bestemt tidligere versjon.';
comment on column knowledge.claim_revisions.statement is
  'Kort kanonisk formulering på norsk bokmål. Skal uttrykke én påstand som kan være sann, falsk eller usikker uavhengig av nabopåstander (KNOWLEDGE_MODEL.md §9.1), og skal aldri være eneste sted populasjon, komparator eller tidsramme finnes (§9.2).';
comment on column knowledge.claim_revisions.scope is
  'Hva påstanden eksplisitt gjelder for, og hva den ikke gjelder for. Alltid utfylt: en påstand uten uttalt anvendelsesområde er i praksis videre enn grunnlaget under den.';
comment on column knowledge.claim_revisions.population_id is
  'Gyldighetsgrensen påstanden gjelder innenfor. NULL betyr at påstanden ikke er avgrenset til en bestemt populasjon, ikke at populasjonen er ukjent — en påstand Antidep ikke vet hvem gjelder for, skal ikke formuleres. Populasjonen arves ikke fra evidensen: knowledge.evidence_items.population_id er den populasjonen et funn indekseres under og kan være videre eller snevrere enn den studerte. Et avvik mellom påstandens populasjon og den studerte er indirekthet og vurderes i knowledge.evidence_assessments (DATABASE_ARCHITECTURE.md §22).';
comment on column knowledge.claim_revisions.timeframe_min is
  'Nedre grense for behandlingstiden påstanden gjelder for, lagret som interval slik at verdi og enhet ikke kan komme fra hverandre. NULL betyr at påstanden ikke er tidsavgrenset.';
comment on column knowledge.claim_revisions.comparator_kind is
  'Hva påstanden sammenligner mot. none betyr at påstanden gjelder en endring fra behandlingsstart uten komparator, ikke at komparatoren er ukjent.';
comment on column knowledge.claim_revisions.direction is
  'Retningen påstanden konkluderer med, når den kan struktureres. NULL betyr at påstanden ikke uttrykker en retning. no_clear_difference er et resultat og skal aldri forveksles med at evidensen ikke kan vurderes; den tilstanden ligger i knowledge.evidence_assessments.certainty_level.';
comment on column knowledge.claim_revisions.magnitude_value is
  'Tallfestet størrelse, når grunnlaget forsvarer en kvantifisering. NULL betyr at påstanden bevisst ikke tallfester størrelsen; tallene fra kildene ligger uansett på evidensfunnene. En påstand som er mer presis enn evidensen under den, er et brudd på ANTIDEP_CONSTITUTION.md §4 og §6.';
comment on column knowledge.claim_revisions.magnitude_unit is
  'Enhet for en dimensjonal størrelse. Påkrevd for mean_change og mean_difference, forbudt for dimensjonsløse mål — samme regel som på evidensfunnene.';
comment on column knowledge.claim_revisions.qualifiers is
  'Nødvendige forbehold som ikke passer i statement, for eksempel at grunnlaget ikke tillater sammenligning med andre virkestoffer.';
comment on column knowledge.claim_revisions.uncertainty_summary is
  'Kort eksplisitt usikkerhetstekst. Påkrevd for evidenssynteser og kliniske anbefalinger (ANTIDEP_CONSTITUTION.md §6). Erstatter ikke evidensvurderingen i knowledge.evidence_assessments, men gjør usikkerheten lesbar der påstanden vises.';
comment on column knowledge.claim_revisions.content_hash is
  'Fingeravtrykk av revisjonens faglige innhold, satt av databasen ved innsetting. Bevisst ikke unikt; se kommentaren på knowledge.set_claim_revision_content_hash().';

create index claim_revisions_supersedes_revision_id_idx
  on knowledge.claim_revisions (supersedes_revision_id);
create index claim_revisions_population_id_idx
  on knowledge.claim_revisions (population_id);
create index claim_revisions_comparator_drug_id_idx
  on knowledge.claim_revisions (comparator_drug_id);
-- Oppslaget «finnes denne formuleringen allerede for denne påstanden?».
-- Bevisst en vanlig indeks, ikke en unik constraint.
create index claim_revisions_claim_content_hash_idx
  on knowledge.claim_revisions (claim_id, content_hash);

-- Publiseringspekeren kan først få sin sammensatte fremmednøkkel når
-- knowledge.claim_revisions finnes. Regelen er invarianten
-- DATABASE_ARCHITECTURE.md §58 kaller «publiseringspeker peker på revisjon av
-- riktig identity», og den er en cross-row-regel som skal løses med riktig
-- mekanisme framfor en CHECK som leser en annen tabell (§59).
--
-- MATCH SIMPLE gjør at en NULL peker slår av kravet: en upublisert påstand er
-- den normale tilstanden i dette steget.
alter table knowledge.claims
  add constraint claims_current_published_revision_fkey
  foreign key (current_published_revision_id, id)
  references knowledge.claim_revisions (id, claim_id)
  on update restrict on delete restrict;

-- Fingeravtrykket eies av databasen, ikke av kalleren, som på evidensfunnene.
--
-- Hva hashen dekker: claim_id og hele det faglige innholdet i revisjonen.
-- claim_id er med fordi to påstander kan ha identisk formulering uten å være
-- samme påstand. revision_number og supersedes_revision_id er derimot holdt
-- utenfor: de beskriver revisjonens plass i historikken, ikke hva den påstår, og
-- var de med, ville hashen aldri kunne gjenkjenne at et nytt forslag er identisk
-- med et eksisterende (DATABASE_ARCHITECTURE.md §14.1).
--
-- Hvorfor hashen ikke er UNIQUE, i motsetning til på knowledge.evidence_items:
-- §14.1 kaller den eksplisitt et hjelpemiddel og ikke en erstatning for
-- revisjons-ID eller faglig vurdering. En hard unikhetsregel ville i tillegg
-- stengt en nødvendig korreksjonsvei. Evidenslenkene og evidensvurderingen
-- henger på revisjonen, er append-only, og vurderingen finnes i nøyaktig ett
-- eksemplar per revisjon. En feil i en lenke eller i en GRADE-vurdering rettes
-- derfor ved å opprette en ny revisjon med et korrigert sett — og den nye
-- revisjonen kan ha ordrett samme formulering som den gamle. Med UNIQUE ville
-- den blitt avvist som dublett, og feilen ville vært umulig å rette. Det er
-- samme blindvei som en for smal hash skapte på evidensfunnene, ett nivå opp.
--
-- Hashen tjener derfor sitt dokumenterte formål — å oppdage identiske
-- agentforslag og unngå unødvendige duplikatrevisjoner — som et oppslag den
-- redaksjonelle skriveveien og evidenspipelinen skal gjøre før de foreslår en
-- ny revisjon, ikke som en sperre databasen håndhever på tvers av alle tilfeller.
--
-- Numeriske verdier normaliseres med trim_scale, og tidsrom hashes som sekunder,
-- slik at 0.80 og 0.8, og «8 uker» skrevet på to måter, gir samme verdi.
--
-- Kanoniseringen er lengdeprefikset, ikke skilletegnbasert. Et utkast skjøtet
-- feltene med concat_ws('|', ...), men fritekstfeltene kan selv inneholde «|».
-- To ulike revisjoner kunne da gi samme kanoniske streng — for eksempel
-- statement = 'A|B', scope = 'C' og statement = 'A', scope = 'B|C' — og en
-- senere skrivevei ville sett dem som identiske forslag. Det er en
-- serialiseringskollisjon før SHA-256, ikke en kryptografisk kollisjon, og den
-- er reell uansett hvor sterk hashfunksjonen er. Hvert felt kodes derfor som
-- «lengde:verdi», med «~:» for NULL, slik at avbildningen fra feltverdier til
-- kanonisk streng er entydig og NULL ikke kan forveksles med tom streng.
--
-- Dette er en bevisst og snever trigger (DATABASE_ARCHITECTURE.md §60): den
-- utleder ett teknisk felt fra radens egne kolonner og inneholder ingen klinisk
-- logikk og ingen arbeidsflyt.
create function knowledge.set_claim_revision_content_hash()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  fields text[];
  field text;
  canonical text := 'sha256-v1';
begin
  fields := array[
    new.claim_id::text,
    new.statement,
    new.scope,
    new.population_id::text,
    extract(epoch from new.timeframe_min)::text,
    extract(epoch from new.timeframe_max)::text,
    new.comparator_kind::text,
    new.comparator_drug_id::text,
    new.direction::text,
    new.magnitude_measure::text,
    trim_scale(new.magnitude_value)::text,
    new.magnitude_unit::text,
    new.qualifiers,
    new.uncertainty_summary
  ];

  foreach field in array fields loop
    -- Lengdeprefiks gjør skjøten entydig; «~» skiller NULL fra tom streng.
    canonical := canonical || '|' || coalesce(length(field)::text, '~') || ':'
                 || coalesce(field, '');
  end loop;

  new.content_hash := 'sha256-v1:' || encode(sha256(convert_to(canonical, 'UTF8')), 'hex');

  return new;
end;
$$;

comment on function knowledge.set_claim_revision_content_hash() is
  'Trigger-funksjon som utleder content_hash fra påstandens identitet og revisjonens faglige innhold ved innsetting. Feltene kanoniseres lengdeprefikset, slik at to ulike revisjoner ikke kan gi samme kanoniske streng selv om fritekstfeltene inneholder skilletegnet. Gir databasen eierskap til fingeravtrykket, slik at det ikke kan oppgis av kalleren. Hashen er et oppslagshjelpemiddel og håndheves bevisst ikke som unikhetsregel (DATABASE_ARCHITECTURE.md §14.1).';

revoke execute on function knowledge.set_claim_revision_content_hash() from public;

create trigger claim_revisions_set_content_hash
  before insert on knowledge.claim_revisions
  for each row execute function knowledge.set_claim_revision_content_hash();

-- Immutabilitetsstrategi for ClaimRevision (MVP_IMPLEMENTATION_PLAN.md §21).
--
-- Valgt strategi: append-only, altså samme vern som knowledge.evidence_items og
-- ikke per-kolonne frys slik catalog.populations har.
--
-- Begrunnelse: DATABASE_ARCHITECTURE.md §7.1 sier rett ut at faglig innhold i en
-- revisjon skal være uforanderlig etter innsetting, og at en rettelse oppretter
-- en ny revisjon. En per-kolonne frys forutsetter at raden har felter som
-- lovlig kan endres uten at betydningen endres — slik en populasjon kan fases
-- ut, og et øyeblikksbilde kan flytte lagringsreferansen sin. En revisjonsrad
-- har ikke noe slikt felt: alt på den er enten den påståtte betydningen eller
-- dens plass i historikken. §7.1 sier i tillegg at arbeidsflytstatus ikke skal
-- tvinge fram mutasjon av revisjonsinnholdet; review- og publiseringstilstand
-- lagres som egne hendelser i migrasjon 005 og 006.
--
-- Hvorfor også DELETE: vanlig redaksjonelt arbeid skal ikke fysisk slette
-- kanonisk kunnskap (DATABASE_ARCHITECTURE.md §36). Fremmednøklene beskytter
-- bare rader andre rader allerede peker på; en revisjon uten lenker ville ellers
-- kunne forsvinne sporløst, og med den hullet i revisjonsnummereringen.
--
-- Ekstra tungtveiende akkurat nå: provenance.actors og audit.events finnes
-- ikke ennå. En UPDATE på en kanonisk kunnskapsrad ville derfor ikke etterlatt
-- noe spor overhodet — verken hvem, når eller hvorfor — og det er direkte i
-- strid med ANTIDEP_CONSTITUTION.md §14.
-- Revisjonsnummeret er dokumentert som monotont (KNOWLEDGE_MODEL.md §9), og en
-- videreføring skal derfor peke bakover i historikken. At den erstattede
-- revisjonen tilhører samme påstand er allerede håndhevet av den sammensatte
-- fremmednøkkelen, men rekkefølgen er en tverradsregel: den avhenger av
-- revisjonsnummeret på en annen rad og kan verken uttrykkes i en CHECK eller i
-- en fremmednøkkel (DATABASE_ARCHITECTURE.md §59). Uten regelen kunne en kjede
-- gå i sirkel eller framover, og «hvilken revisjon erstattet hvilken?» ville
-- ikke lenger vært entydig.
--
-- Finnes ikke den erstattede revisjonen, sier funksjonen ingenting: da er det
-- fremmednøkkelen som skal avvise raden, med sin egen feilkode.
create function knowledge.enforce_revision_supersedes_order()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  superseded_number integer;
begin
  if new.supersedes_revision_id is null then
    return new;
  end if;

  select r.revision_number into superseded_number
  from knowledge.claim_revisions r
  where r.id = new.supersedes_revision_id;

  if superseded_number is not null and superseded_number >= new.revision_number then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Revisjon %s kan ikke erstatte revisjon %s; en videreføring må peke på et lavere revisjonsnummer.',
        new.revision_number, superseded_number
      ),
      hint = 'Gi den nye revisjonen et høyere revisjonsnummer enn den den erstatter. Revisjonsnummeret er monotont innenfor påstanden.';
  end if;

  return new;
end;
$$;

comment on function knowledge.enforce_revision_supersedes_order() is
  'Tverradsinvariant: sikrer at en revisjon bare kan erstatte en revisjon med lavere revisjonsnummer, slik at videreføringskjeden er monoton og entydig.';

revoke execute on function knowledge.enforce_revision_supersedes_order() from public;

create trigger claim_revisions_enforce_supersedes_order
  before insert on knowledge.claim_revisions
  for each row execute function knowledge.enforce_revision_supersedes_order();

create trigger claim_revisions_reject_mutation
  before update or delete on knowledge.claim_revisions
  for each row execute function knowledge.reject_append_only_mutation(
    'Opprett en ny revisjon av påstanden for den korrigerte formuleringen. En publisert eller upublisert revisjon skal ikke overskrives eller slettes, fordi den dokumenterer hva Antidep faktisk påsto.'
  );

-- ----------------------------------------------------------------------------
-- 5. knowledge.claim_evidence_links — hvordan evidensen forholder seg til
--    påstanden (DATABASE_ARCHITECTURE.md §21, KNOWLEDGE_MODEL.md §12)
--
-- ANTIDEP_CONSTITUTION.md §4 krever at koblingen dokumenterer hvordan kilden
-- støtter, nyanserer eller motsier formuleringen, og at en kilde som bare
-- omhandler samme tema ikke godtas som støtte. Derfor er både relasjonstypen og
-- begrunnelsen påkrevd; en lenke uten begrunnelse er nettopp den kilden §4
-- forbyr å telle som støtte.
--
-- Lenken peker på en eksakt revisjon, ikke på påstandsidentiteten
-- (KNOWLEDGE_MODEL.md §19.3). Det gjør spørsmålet «hvilket evidensgrunnlag
-- gjelder nå?» entydig: det som henger på den revisjonen som er publisert.
--
-- Motstridende lenker er like bevaringsverdige som støttende
-- (ANTIDEP_CONSTITUTION.md §9), og ingenting krever at lenkene på en revisjon
-- er samstemte (KNOWLEDGE_MODEL.md §13.2).
-- ----------------------------------------------------------------------------
create table knowledge.claim_evidence_links (
  id uuid primary key default gen_random_uuid(),
  claim_revision_id uuid not null
    references knowledge.claim_revisions (id) on update restrict on delete restrict,
  evidence_item_id uuid not null
    references knowledge.evidence_items (id) on update restrict on delete restrict,
  relationship_type knowledge.claim_evidence_relationship not null,
  directness knowledge.evidence_directness not null,
  relevance_note text not null,
  created_at timestamptz not null default now(),

  -- Samme relasjon mellom samme revisjon og samme evidensfunn skal ikke kunne
  -- registreres to ganger. Uten regelen kunne et gjentatt agentforsøk fått ett
  -- funn til å se ut som flere uavhengige, og en senere vurdering til å hvile på
  -- en oppblåst evidensmengde.
  constraint claim_evidence_links_revision_item_key
    unique (claim_revision_id, evidence_item_id),

  -- Stance og indirekthet er to akser, og bare den ene verdien som selv er en
  -- påstand om indirekthet er bundet: relationship_type = 'indirect' kan ikke
  -- samtidig hevde at funnet treffer påstanden direkte. Alle øvrige
  -- kombinasjoner er frie, og de trengs: et funn kan støtte, motsi eller være
  -- nøytralt til påstanden både direkte og indirekte. Et direkte relevant funn
  -- som verken støtter eller motsier påstanden er neutral_contextual + direct.
  constraint claim_evidence_links_directness_check
    check (relationship_type <> 'indirect' or directness = 'indirect'),

  constraint claim_evidence_links_relevance_note_check
    check (relevance_note = btrim(relevance_note)
           and length(relevance_note) between 1 and 4000)
);

comment on table knowledge.claim_evidence_links is
  'Antideps eksplisitte vurdering av hvordan ett evidensfunn forholder seg til én bestemt påstandsrevisjon (KNOWLEDGE_MODEL.md §12). Ikke en referanseliste: både relasjonstype, hvor direkte evidensen treffer, og en skriftlig begrunnelse er påkrevd. Raden er append-only.';
comment on column knowledge.claim_evidence_links.claim_revision_id is
  'Den eksakte påstandsrevisjonen lenken gjelder. Referanser peker til revisjoner, ikke bare til stabile objekter (KNOWLEDGE_MODEL.md §19.3).';
comment on column knowledge.claim_evidence_links.relationship_type is
  'Stance: hvordan funnet forholder seg til påstanden. Et funn som er direkte relevant, men verken støtter eller motsier påstanden, er neutral_contextual, ikke indirect. Motstridende lenker skal bevares på lik linje med støttende (ANTIDEP_CONSTITUTION.md §9), og en revisjon kan ha lenker med ulik verdi samtidig.';
comment on column knowledge.claim_evidence_links.directness is
  'Om funnet treffer påstandens populasjon, endepunkt, komparator og tidsrom direkte. Egen akse, slik at et indirekte funn som motsier påstanden kan uttrykkes. Et avvik mellom studert og påstått populasjon er indirekthet, og vurderes samlet i knowledge.evidence_assessments.';
comment on column knowledge.claim_evidence_links.relevance_note is
  'Hvorfor funnet har denne relasjonen til denne formuleringen. Alltid utfylt: en kilde som bare handler om samme tema skal ikke kunne telle som støtte (ANTIDEP_CONSTITUTION.md §4, KNOWLEDGE_MODEL.md §12).';

-- Baklengsoppslaget: hvilke påstander hviler på dette evidensfunnet. Trengs
-- blant annet den dagen en kilde trekkes tilbake.
create index claim_evidence_links_evidence_item_id_idx
  on knowledge.claim_evidence_links (evidence_item_id);

-- Append-only av samme grunn som revisjonen selv: lenken er en datert faglig
-- vurdering av to uforanderlige objekter, og uten aktør- og audittabeller ville
-- en endring ikke etterlatt spor. Evidensgrunnlaget er dessuten en del av
-- revisjonens betydning (KNOWLEDGE_MODEL.md §19.2), så en endring i det hører
-- til en ny revisjon.
create trigger claim_evidence_links_reject_mutation
  before update or delete on knowledge.claim_evidence_links
  for each row execute function knowledge.reject_append_only_mutation(
    'Opprett en ny revisjon av påstanden med det korrigerte settet av evidenslenker. En registrert vurdering av hvordan et funn forholder seg til en revisjon skal ikke overskrives eller slettes.'
  );

-- Evidensvurderingen forsegler evidenssettet til revisjonen.
--
-- At lenkene ikke kan endres eller slettes er ikke nok. Uten denne regelen er
-- sekvensen «opprett revisjon → lenke → vurder → ny lenke» lovlig, og da
-- beskriver knowledge.evidence_assessments ikke lenger det evidensgrunnlaget den
-- faktisk vurderte. Vurderingen finnes i nøyaktig ett eksemplar per revisjon og
-- er selv append-only, så den kan ikke følge etter: resultatet ville vært en
-- GRADE-vurdering som stilltiende gjaldt et annet grunnlag enn det som står
-- registrert. Det er alvorlig når review og publisering peker på revisjons-ID,
-- og det bryter med KNOWLEDGE_MODEL.md §19.2, som krever ny revisjon når
-- evidensgrunnlaget endres på en måte som påvirker vurderingen.
--
-- Vurderingen er derfor forseglingshandlingen: før den er evidenssettet under
-- arbeid, etter den er det låst. Ny eller motstridende evidens som dukker opp
-- senere hører til en ny revisjon med sitt eget lenkesett og sin egen vurdering
-- — som er nettopp den korreksjonsveien content_hash bevisst holder åpen.
--
-- Cross-row-regel som ikke kan uttrykkes deklarativt: en CHECK kan ikke lese en
-- annen tabell (DATABASE_ARCHITECTURE.md §59), og en fremmednøkkel kan kreve at
-- en rad finnes, ikke at den ikke finnes. Dette er derfor en av
-- tverradsinvariantene §60 navngir som legitim triggerbruk.
--
-- Samtidighet: raden i knowledge.claim_revisions låses med FOR UPDATE før
-- kontrollen. Uten låsen kunne en samtidig transaksjon rekke å opprette
-- vurderingen mellom kontrollen og commit. Innsetting i
-- knowledge.evidence_assessments tar selv FOR KEY SHARE på den samme raden
-- gjennom fremmednøkkelen sin, og FOR UPDATE er uforenlig med den, så de to
-- operasjonene serialiseres mot hverandre. Merk avhengigheten: fjernes
-- fremmednøkkelen fra evidence_assessments til claim_revisions, åpnes kappløpet
-- igjen.
--
-- Deterministiske fakta får ingen evidensvurdering og forsegles derfor ikke av
-- denne regelen. For dem er publisering forseglingen, og den hører til
-- migrasjon 006 — som uansett må hindre at en publisert revisjon får nye lenker.
create function knowledge.reject_evidence_link_after_assessment()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  perform 1
  from knowledge.claim_revisions r
  where r.id = new.claim_revision_id
  for update;

  if exists (
    select 1
    from knowledge.evidence_assessments a
    where a.claim_revision_id = new.claim_revision_id
  ) then
    raise exception using
      errcode = 'restrict_violation',
      message = format(
        'Evidensgrunnlaget for revisjon %L er forseglet av en evidensvurdering og kan ikke utvides.',
        new.claim_revision_id
      ),
      hint = 'Opprett en ny revisjon av påstanden med det fullstendige evidenssettet, og gi den sin egen evidensvurdering. En vurdering skal alltid beskrive hele grunnlaget for den revisjonen den gjelder.';
  end if;

  return new;
end;
$$;

comment on function knowledge.reject_evidence_link_after_assessment() is
  'Tverradsinvariant: hindrer at evidenssettet til en påstandsrevisjon utvides etter at revisjonen har fått sin evidensvurdering, slik at vurderingen alltid beskriver hele grunnlaget den gjelder for.';

revoke execute on function knowledge.reject_evidence_link_after_assessment() from public;

create trigger claim_evidence_links_reject_after_assessment
  before insert on knowledge.claim_evidence_links
  for each row execute function knowledge.reject_evidence_link_after_assessment();

-- ----------------------------------------------------------------------------
-- 6. knowledge.evidence_assessments — hvor sikkert er grunnlaget
--    (DATABASE_ARCHITECTURE.md §22, KNOWLEDGE_MODEL.md §13)
--
-- Kjernen i ANTIDEP_CONSTITUTION.md §6: usikkerhet skal graderes og forklares,
-- GRADE-domenene skal vurderes eksplisitt, og «ingen vurderbar evidens» skal
-- være en separat systemtilstand som aldri fremstilles som lav risiko eller
-- liten effekt.
--
-- Valgt vokabular for den tilstanden: en egen knowledge.certainty_level, ikke
-- knowledge.value_availability fra migrasjon 003. value_availability forklarer
-- hvorfor en verdi Antidep forsøkte å hente ut av en kilde mangler — den ble
-- ikke målt, ikke rapportert, ikke lot seg lese ut. «Ingen vurderbar evidens»
-- er ikke en manglende uthentet verdi; det er resultatet av en vurdering
-- Antidep faktisk har gjort. Å modellere den som en availability-status ville
-- sagt at sikkerhetsgraden finnes, men ikke er rapportert — og dermed fått
-- tilstanden til å se ut som manglende data framfor som et funn. Fordi
-- certainty_level er NOT NULL og bærer tilstanden som en egen verdi, kan den
-- verken kollapse til NULL eller forveksles med very_low.
--
-- Sikkerhetsgraden kan aldri utledes av antall kilder alene (§22): de fem
-- GRADE-domenene er egne kolonner og må fylles ut når en GRADE-kategori settes.
-- Databasen kan håndheve at vurderingen er gjort; den kan ikke håndheve at den
-- er faglig riktig. Det er reviewerens oppgave (migrasjon 005).
--
-- Én vurdering per revisjon (UNIQUE). §22 kaller vurderingen versjonert, og
-- versjoneringen kommer fra revisjonene: en endret sikkerhetsgrad krever i seg
-- selv en ny revisjon (KNOWLEDGE_MODEL.md §19.2), og den nye revisjonen får sin
-- egen vurdering. MVP-en skal ha nøyaktig én eksplisitt vurdering per publisert
-- evidenssyntese (§22), og det er det unikhetsregelen gir. Flere samtidige
-- faglige vurderinger av samme revisjon er den mer avanserte modellen §22
-- nevner, og er bevisst ikke bygget nå.
--
-- Bevisst utelatt: assessed_by_actor_id og human_approved_by_actor_id
-- (KNOWLEDGE_MODEL.md §13). provenance.actors kommer i migrasjon 005, og
-- godkjenningen selv er en review-beslutning i workflow, ikke en kolonne her —
-- generering og verifikasjon skal være atskilte operasjoner
-- (ANTIDEP_CONSTITUTION.md §10, §12).
-- ----------------------------------------------------------------------------
create table knowledge.evidence_assessments (
  id uuid primary key default gen_random_uuid(),
  claim_revision_id uuid not null
    references knowledge.claim_revisions (id) on update restrict on delete restrict,
  assessed_knowledge_type knowledge.knowledge_type not null,
  framework knowledge.assessment_framework not null,
  certainty_level knowledge.certainty_level not null,
  risk_of_bias knowledge.grade_domain_rating,
  inconsistency knowledge.grade_domain_rating,
  indirectness knowledge.grade_domain_rating,
  imprecision knowledge.grade_domain_rating,
  publication_bias knowledge.grade_domain_rating,
  other_considerations text,
  rationale text not null,
  evidence_gap text,
  assessed_at timestamptz not null,
  created_at timestamptz not null default now(),

  -- Nøyaktig én vurdering per revisjon.
  constraint evidence_assessments_claim_revision_key unique (claim_revision_id),

  -- Den vurderte revisjonen må være av en type som skal ha en evidensvurdering
  -- (KNOWLEDGE_MODEL.md §13). Cross-row-regel løst med sammensatt fremmednøkkel
  -- mot (id, knowledge_type) og en CHECK på speilkolonnen, framfor en CHECK som
  -- leser en annen tabell (DATABASE_ARCHITECTURE.md §59). Fremmednøkkelen gjør
  -- speilet sant; CHECK-en begrenser hvilke verdier det kan ha.
  constraint evidence_assessments_revision_fkey
    foreign key (claim_revision_id, assessed_knowledge_type)
    references knowledge.claim_revisions (id, knowledge_type)
    on update restrict on delete restrict,
  constraint evidence_assessments_knowledge_type_check
    check (assessed_knowledge_type in ('evidence_synthesis', 'clinical_recommendation')),

  -- ANTIDEP_CONSTITUTION.md §6: en GRADE-kategori krever eksplisitt vurdering av
  -- domenene, og «ingen vurderbar evidens» er den ene tilstanden der domenene
  -- ikke kan vurderes — det finnes ikke noe å gradere ned fra. Reglene går begge
  -- veier, slik at verken en gradering uten domener eller domener uten gradering
  -- kan registreres.
  constraint evidence_assessments_risk_of_bias_pairing_check
    check ((risk_of_bias is null) = (certainty_level = 'no_assessable_evidence')),
  constraint evidence_assessments_inconsistency_pairing_check
    check ((inconsistency is null) = (certainty_level = 'no_assessable_evidence')),
  constraint evidence_assessments_indirectness_pairing_check
    check ((indirectness is null) = (certainty_level = 'no_assessable_evidence')),
  constraint evidence_assessments_imprecision_pairing_check
    check ((imprecision is null) = (certainty_level = 'no_assessable_evidence')),
  constraint evidence_assessments_publication_bias_pairing_check
    check ((publication_bias is null) = (certainty_level = 'no_assessable_evidence')),

  -- «Ingen vurderbar evidens» skal aldri kunne stå som en tom tilstand: den skal
  -- si hva som mangler, ellers er den ikke til å skille fra at ingen har sett på
  -- spørsmålet (ANTIDEP_CONSTITUTION.md §6, §17).
  constraint evidence_assessments_evidence_gap_required_check
    check (certainty_level <> 'no_assessable_evidence'
           or (evidence_gap is not null and btrim(evidence_gap) <> '')),

  constraint evidence_assessments_rationale_check
    check (rationale = btrim(rationale) and length(rationale) between 1 and 4000),
  constraint evidence_assessments_evidence_gap_check
    check (evidence_gap is null
           or (evidence_gap = btrim(evidence_gap)
               and length(evidence_gap) between 1 and 4000)),
  constraint evidence_assessments_other_considerations_check
    check (other_considerations is null
           or (other_considerations = btrim(other_considerations)
               and length(other_considerations) between 1 and 4000))
);

comment on table knowledge.evidence_assessments is
  'Den eksplisitte vurderingen av hvor sikkert evidensgrunnlaget støtter én påstandsrevisjon (ANTIDEP_CONSTITUTION.md §6, KNOWLEDGE_MODEL.md §13). Nøyaktig én vurdering per revisjon, og bare for revisjoner av typen evidence_synthesis eller clinical_recommendation. Raden er append-only.';
comment on column knowledge.evidence_assessments.assessed_knowledge_type is
  'Speil av kunnskapstypen på den vurderte revisjonen, låst av den sammensatte fremmednøkkelen og begrenset av en CHECK. Finnes for at kravet om at bare evidenssynteser og kliniske anbefalinger vurderes skal kunne håndheves deklarativt. Ikke en selvstendig sannhet.';
comment on column knowledge.evidence_assessments.framework is
  'Den eksplisitte metoden vurderingen bruker. Uten en navngitt metode ville sikkerhetsgraden vært en udokumentert skjønnsverdi.';
comment on column knowledge.evidence_assessments.certainty_level is
  'Sikkerheten i kunnskapsgrunnlaget. Alltid utfylt. no_assessable_evidence er en egen systemtilstand og betyr at grunnlaget ikke lar seg vurdere — ikke at risikoen er lav, at effekten er liten eller at det ikke er noen forskjell (ANTIDEP_CONSTITUTION.md §6, §17).';
comment on column knowledge.evidence_assessments.risk_of_bias is
  'GRADE-domenet risiko for systematisk skjevhet. Utfylt hvis og bare hvis certainty_level er en GRADE-kategori; not_assessable brukes når domenet ikke lar seg vurdere.';
comment on column knowledge.evidence_assessments.inconsistency is
  'GRADE-domenet inkonsistens mellom studier. Kan ikke vurderes ut fra én studie; da er verdien not_assessable, ikke not_serious.';
comment on column knowledge.evidence_assessments.indirectness is
  'GRADE-domenet indirekthet. Her fanges avviket mellom den studerte populasjonen og den populasjonen påstanden gjelder for, og tilsvarende avvik i endepunkt, komparator og tidsrom.';
comment on column knowledge.evidence_assessments.imprecision is
  'GRADE-domenet upresishet. Et grunnlag uten estimat eller konfidensintervall er upresist, ikke fraværende.';
comment on column knowledge.evidence_assessments.publication_bias is
  'GRADE-domenet publikasjonsskjevhet. Kan ikke vurderes ut fra én studie; da er verdien not_assessable.';
comment on column knowledge.evidence_assessments.rationale is
  'Samlet begrunnelse for sikkerhetsgraden og domenevurderingene. Alltid utfylt: en gradering uten begrunnelse er ikke etterprøvbar (ANTIDEP_CONSTITUTION.md §6).';
comment on column knowledge.evidence_assessments.evidence_gap is
  'Hva som mangler i kunnskapsgrunnlaget. Påkrevd når certainty_level er no_assessable_evidence, slik at tilstanden aldri står tom.';
comment on column knowledge.evidence_assessments.assessed_at is
  'Når den faglige vurderingen ble gjort. Et hendelsestidspunkt, ikke registreringstidspunktet for raden; det siste er created_at (DATABASE_ARCHITECTURE.md §7.3). Sammen med revisjonen gir feltet påstandens tidspunkt for siste faglige vurdering (ANTIDEP_CONSTITUTION.md §7).';

-- Append-only av samme grunn som revisjonen og lenkene: vurderingen er en datert
-- faglig bedømmelse av en uforanderlig revisjon. En endret sikkerhetsgrad krever
-- uansett en ny revisjon (KNOWLEDGE_MODEL.md §19.2), og uten aktør- og
-- audittabeller ville en endring ikke etterlatt spor.
create trigger evidence_assessments_reject_mutation
  before update or delete on knowledge.evidence_assessments
  for each row execute function knowledge.reject_append_only_mutation(
    'Opprett en ny revisjon av påstanden med en korrigert evidensvurdering. En endret sikkerhetsgrad er i seg selv en betydningsendring som krever ny revisjon.'
  );

-- ----------------------------------------------------------------------------
-- 7. RLS og grants (DATABASE_ARCHITECTURE.md §5, §48,
--    MVP_IMPLEMENTATION_PLAN.md §47)
--
-- RLS aktiveres på alle nye tabeller og er default deny: uten policy gir
-- tabellen ingen rader til noen rolle som ikke eier den. Ingen policy skrives
-- her. Redaksjonell lesetilgang forutsetter medlemskapsmodellen i migrasjon
-- 005, og klientlesing skal uansett gå gjennom publiserte projeksjoner i api
-- (migrasjon 007), aldri direkte mot knowledge.
--
-- At ingen klientrolle når disse tabellene er et innholdskrav og ikke bare et
-- sikkerhetskrav: påstandene under er KI-utarbeidede forslag fram til de har
-- passert verifikasjons- og reviewgatene (ANTIDEP_CONSTITUTION.md §12).
--
-- Nye tabeller får ingen privilegier til klientrollene i PostgreSQL, men
-- grensen skrives eksplisitt, som i migrasjon 001, 002 og 003.
-- ----------------------------------------------------------------------------
alter table knowledge.claims enable row level security;
alter table knowledge.claim_revisions enable row level security;
alter table knowledge.claim_evidence_links enable row level security;
alter table knowledge.evidence_assessments enable row level security;

revoke all privileges on all tables in schema knowledge from public;
revoke all privileges on all tables in schema knowledge
  from anon, authenticated, service_role;

-- ============================================================================
-- 8. Påstandene for første golden slice
--    (MVP_IMPLEMENTATION_PLAN.md §12, §21, §29)
--
-- Omfang: nøyaktig det slicen trenger. Én påstand per virkestoff om
-- vektendring, én revisjon per påstand, én evidenslenke til det evidensfunnet
-- migrasjon 003 registrerte for det virkestoffet, og én evidensvurdering per
-- revisjon. Ingen nye katalograder, ingen nye kilder og ingen nye evidensfunn:
-- trengs det, har scopet glippet.
--
-- Plassering: radene ligger i migrasjonen, ikke i supabase/seed.sql, av samme
-- grunn som i migrasjon 002 og 003. Publisering og api-projeksjoner får
-- fremmednøkler hit, og seed.sql kjøres bare ved lokal db reset.
--
-- Kunnskapstype (ANTIDEP_CONSTITUTION.md §5): begge påstandene er
-- evidence_synthesis. De to evidensfunnene som finnes bærer evidenssynteser,
-- ikke kliniske anbefalinger, og ingen av dem sier noe om hva klinikeren bør
-- gjøre. Ingen clinical_recommendation formuleres her.
--
-- Styrke (ANTIDEP_CONSTITUTION.md §4, §6): ingen av påstandene tallfester
-- størrelsen på vektendringen. Sertralinfunnet oppgir ingen tallverdi i det
-- hele tatt (estimate_availability = 'not_reported'), og mirtazapinfunnet oppgir
-- ett armspesifikt gjennomsnitt uten at antallet i analysen er kjent og med en
-- populasjonskobling merket uncertain_extraction. En påstand som tallfestet
-- størrelsen ville derfor vært mer presis enn grunnlaget under den.
-- magnitude_value står tomt på begge, og tallene blir stående der de er belagt:
-- på evidensfunnene.
--
-- Sammenligning: begge funnene er armspesifikke endringer fra behandlingsstart,
-- hentet fra to forskjellige studier med forskjellig varighet og forskjellige
-- utvalg. Grunnlaget tillater ingen sammenligning mellom sertralin og
-- mirtazapin, og det står eksplisitt i qualifiers på begge revisjonene, slik at
-- en senere sammenligningsvisning ikke kan stille dem opp mot hverandre uten å
-- vise forbeholdet (ANTIDEP_CONSTITUTION.md §2, §3, MVP_IMPLEMENTATION_PLAN.md
-- §31).
--
-- Populasjon: påstandene arver ikke populasjon fra evidensen. De erklærer selv
-- den gyldighetsgrensen de gjelder innenfor, og avviket mot den studerte
-- populasjonen er registrert som indirekthet i evidensvurderingen
-- (DATABASE_ARCHITECTURE.md §22).
--
-- Epistemisk status (ANTIDEP_CONSTITUTION.md §12): radene er KI-utarbeidede
-- forslag. De er ikke verifisert av en separat kontrollfase og ikke godkjent av
-- en navngitt kvalifisert redaktør, fordi verken verifikasjon, review eller
-- aktørregister finnes ennå (migrasjon 005). Ingenting i dette steget kan
-- publisere dem: current_published_revision_id står tomt på begge påstandene,
-- det finnes ingen publiseringshendelser og ingen api-projeksjon.
--
-- Radene får databasegenererte uuid-er. Tester og senere migrasjoner slår dem
-- opp via virkestoff og tema, ikke via hardkodede uuid-er.
-- ============================================================================

insert into knowledge.claims (knowledge_type, topic_concept_id, subject_drug_id)
select
  'evidence_synthesis'::knowledge.knowledge_type,
  c.id,
  d.id
from catalog.clinical_concepts c
join catalog.drugs d on d.canonical_name in ('sertralin', 'mirtazapin')
where c.canonical_label = 'vektendring';

-- Påstand 1 — sertralin.
--
-- Grunnlaget er Fava 2000: en randomisert dobbeltblind langtidsstudie der
-- vektanalysen omfatter de 48 av 96 randomiserte som fullførte, og som
-- karakteriserer sertralinarmen som en beskjeden, ikke statistisk signifikant
-- vektøkning uten å oppgi tallverdien. Påstanden gjengir retningen og at den
-- ikke er statistisk signifikant, og lar størrelsen stå åpen.
insert into knowledge.claim_revisions (
  claim_id, revision_number, knowledge_type, subject_drug_id,
  statement, scope, population_id,
  timeframe_min, timeframe_max, comparator_kind,
  direction, qualifiers, uncertainty_summary
)
select
  cl.id,
  1,
  cl.knowledge_type,
  cl.subject_drug_id,
  'Hos voksne med depressiv lidelse er vedvarende behandling med sertralin i det registrerte evidensgrunnlaget forbundet med en liten, ikke statistisk signifikant gjennomsnittlig vektøkning fra behandlingsstart.',
  'Gjelder gjennomsnittlig vektendring fra behandlingsstart ved vedvarende behandling i om lag et halvt år. Gjelder ikke andelen pasienter som får en klinisk betydelig vektøkning, og ikke sammenligning mot placebo eller mot andre antidepressiver.',
  p.id,
  interval '26 weeks',
  interval '32 weeks',
  'none',
  'increase',
  'Vektøkningen er rapportert som ikke statistisk signifikant. Grunnlaget er armspesifikt og tillater ingen sammenligning med mirtazapin eller med andre antidepressiver.',
  'Grunnlaget er ett evidensfunn fra én randomisert studie, der vektanalysen bare omfatter de 48 av 96 pasientene som ble randomisert til sertralin og fullførte. Verken tallverdi eller konfidensintervall er gjengitt i den verifiserte kildeversjonen, så retningen er kjent, mens størrelsen ikke er etterprøvbar i det registrerte grunnlaget.'
from knowledge.claims cl
join catalog.drugs d on d.id = cl.subject_drug_id
join catalog.populations p on p.canonical_label = 'voksne med depressiv lidelse'
where d.canonical_name = 'sertralin';

-- Påstand 2 — mirtazapin.
--
-- Grunnlaget er Versiani 2005: en randomisert dobbeltblind studie over åtte uker
-- som oppgir en gjennomsnittlig vektøkning på 0,8 kg med standardavvik 2,7 kg
-- for mirtazapinarmen, uten å oppgi hvor mange som inngår i vektanalysen, og med
-- et utvalg av alvorlig deprimerte pasienter der nedre aldersgrense ikke er
-- oppgitt. Påstanden gjengir retningen og lar størrelsen stå åpen.
insert into knowledge.claim_revisions (
  claim_id, revision_number, knowledge_type, subject_drug_id,
  statement, scope, population_id,
  timeframe_min, timeframe_max, comparator_kind,
  direction, qualifiers, uncertainty_summary
)
select
  cl.id,
  1,
  cl.knowledge_type,
  cl.subject_drug_id,
  'Hos voksne med depressiv lidelse er korttidsbehandling med mirtazapin i det registrerte evidensgrunnlaget forbundet med en gjennomsnittlig vektøkning fra behandlingsstart.',
  'Gjelder gjennomsnittlig vektendring fra behandlingsstart i løpet av åtte ukers behandling. Gjelder ikke lengre behandlingsvarighet, ikke andelen pasienter som får en klinisk betydelig vektøkning, og ikke sammenligning mot placebo eller mot andre antidepressiver.',
  p.id,
  interval '8 weeks',
  interval '8 weeks',
  'none',
  'increase',
  'Grunnlaget er armspesifikt og tillater ingen sammenligning med sertralin eller med andre antidepressiver. Studiepopulasjonen var alvorlig deprimerte pasienter, og koblingen til voksne med depressiv lidelse er merket som usikker i evidensgrunnlaget.',
  'Grunnlaget er ett evidensfunn fra én randomisert studie over åtte uker. Studien oppgir en gjennomsnittlig vektøkning på 0,8 kg med standardavvik 2,7 kg, men verken antallet som inngår i vektanalysen eller et konfidensintervall, og størrelsen er derfor ikke tallfestet i påstanden. Utvalget var alvorlig deprimerte pasienter uten oppgitt nedre aldersgrense, så det er usikkert hvor godt det svarer til populasjonen påstanden gjelder for.'
from knowledge.claims cl
join catalog.drugs d on d.id = cl.subject_drug_id
join catalog.populations p on p.canonical_label = 'voksne med depressiv lidelse'
where d.canonical_name = 'mirtazapin';

-- Evidenslenkene. Hver påstand kobles til evidensfunnet for det samme
-- virkestoffet på det samme endepunktet, med en begrunnelse som sier hva funnet
-- faktisk underbygger og hva det ikke underbygger (ANTIDEP_CONSTITUTION.md §4).
insert into knowledge.claim_evidence_links (
  claim_revision_id, evidence_item_id, relationship_type, directness, relevance_note
)
select
  r.id,
  e.id,
  'supports'::knowledge.claim_evidence_relationship,
  'direct'::knowledge.evidence_directness,
  'Funnet rapporterer gjennomsnittlig prosentvis vektendring for sertralinarmen i samme populasjon og over det samme tidsrommet påstanden gjelder, og oppgir retningen som en beskjeden, ikke statistisk signifikant økning. Det underbygger retningen i påstanden. Det underbygger ingen tallfestet størrelse, fordi verdien ikke er gjengitt i den verifiserte kildeversjonen, og påstanden tallfester derfor heller ikke størrelsen.'
from knowledge.claim_revisions r
join knowledge.claims cl on cl.id = r.claim_id
join catalog.drugs d on d.id = cl.subject_drug_id
join knowledge.evidence_items e on e.intervention_drug_id = d.id
where d.canonical_name = 'sertralin';

insert into knowledge.claim_evidence_links (
  claim_revision_id, evidence_item_id, relationship_type, directness, relevance_note
)
select
  r.id,
  e.id,
  'supports'::knowledge.claim_evidence_relationship,
  'indirect'::knowledge.evidence_directness,
  'Funnet rapporterer gjennomsnittlig vektendring i kilogram for mirtazapinarmen over de samme åtte ukene påstanden gjelder, og oppgir en økning. Det underbygger retningen i påstanden. Evidensen er indirekte fordi studiepopulasjonen var alvorlig deprimerte pasienter uten oppgitt nedre aldersgrense, slik at den ikke entydig svarer til voksne med depressiv lidelse; koblingen er merket uncertain_extraction i evidensfunnet.'
from knowledge.claim_revisions r
join knowledge.claims cl on cl.id = r.claim_id
join catalog.drugs d on d.id = cl.subject_drug_id
join knowledge.evidence_items e on e.intervention_drug_id = d.id
where d.canonical_name = 'mirtazapin';

-- Evidensvurderingene. Begge er svært lav sikkerhet, og begge domenevurderinger
-- er begrunnet i egenskaper ved grunnlaget, ikke i antall kilder
-- (DATABASE_ARCHITECTURE.md §22). Konsistens og publikasjonsskjevhet står som
-- not_assessable på begge fordi ett enkelt funn ikke gir grunnlag for å bedømme
-- dem; not_serious ville vært falsk presisjon.
--
-- Presisjonsdomenet skiller de to, og skillet er prinsipielt: for sertralin er
-- ingen tallverdi og intet konfidensintervall gjengitt i den verifiserte
-- kildeversjonen, så domenet lar seg ikke bedømme og står som not_assessable.
-- At en verdi ikke er rapportert er allerede modellert på evidensfunnet som
-- not_reported, og det dokumenterer ikke i seg selv at estimatet er upresist —
-- å gradere ned til very_serious på det grunnlaget ville vært å lese manglende
-- rapportering som et metodisk funn. For mirtazapin rapporterer kilden derimot
-- et gjennomsnitt og et standardavvik, og spredningen er stor sammenlignet med
-- endringen, så der er presisjonen faktisk vurderbar og gradert ned til serious.
--
-- Vurderingen er samtidig forseglingshandlingen for evidenssettet: etter at den
-- er registrert kan revisjonen ikke få flere evidenslenker.

-- Rekkefølgen under er derfor ikke tilfeldig: lenkene registreres før
-- vurderingene.
insert into knowledge.evidence_assessments (
  claim_revision_id, assessed_knowledge_type, framework, certainty_level,
  risk_of_bias, inconsistency, indirectness, imprecision, publication_bias,
  rationale, evidence_gap, assessed_at
)
select
  r.id,
  r.knowledge_type,
  'grade'::knowledge.assessment_framework,
  'very_low'::knowledge.certainty_level,
  'serious'::knowledge.grade_domain_rating,
  'not_assessable'::knowledge.grade_domain_rating,
  'not_serious'::knowledge.grade_domain_rating,
  'not_assessable'::knowledge.grade_domain_rating,
  'not_assessable'::knowledge.grade_domain_rating,
  'Ett evidensfunn fra én randomisert studie ligger til grunn. Vektanalysen omfatter bare de 48 av 96 randomiserte som fullførte, noe som gir risiko for frafallsskjevhet. Verken estimat eller konfidensintervall er gjengitt i den verifiserte kildeversjonen, så presisjonen lar seg ikke bedømme. Domenet står derfor som ikke vurderbart og ikke som en nedgradering: at en verdi ikke er rapportert der raden peker, dokumenterer ikke i seg selv at estimatet er upresist. Konsistens og publikasjonsskjevhet lar seg heller ikke vurdere ut fra ett enkelt funn. Populasjon, endepunkt og tidsrom i funnet svarer til påstanden, så indirekthet er ikke vurdert som alvorlig. Samlet sikkerhet er svært lav: grunnlaget har alvorlig risiko for skjevhet, og tre av fem domener lar seg ikke bedømme i det hele tatt.',
  'Størrelsen på vektendringen er ikke tallfestet i det registrerte grunnlaget, og det finnes ingen registrert sammenligning mot placebo eller mot andre antidepressiver.',
  timestamptz '2026-08-19T12:45:00Z'
from knowledge.claim_revisions r
join knowledge.claims cl on cl.id = r.claim_id
join catalog.drugs d on d.id = cl.subject_drug_id
where d.canonical_name = 'sertralin';

insert into knowledge.evidence_assessments (
  claim_revision_id, assessed_knowledge_type, framework, certainty_level,
  risk_of_bias, inconsistency, indirectness, imprecision, publication_bias,
  rationale, evidence_gap, assessed_at
)
select
  r.id,
  r.knowledge_type,
  'grade'::knowledge.assessment_framework,
  'very_low'::knowledge.certainty_level,
  'serious'::knowledge.grade_domain_rating,
  'not_assessable'::knowledge.grade_domain_rating,
  'serious'::knowledge.grade_domain_rating,
  'serious'::knowledge.grade_domain_rating,
  'not_assessable'::knowledge.grade_domain_rating,
  'Ett evidensfunn fra én randomisert studie ligger til grunn. Antallet som inngår i vektanalysen er ikke oppgitt, så verken frafall eller analysepopulasjon lar seg bedømme. Presisjonen er derimot vurderbar her, fordi kilden faktisk rapporterer spredningen: standardavviket på 2,7 kg er stort sammenlignet med gjennomsnittsendringen på 0,8 kg, og domenet er gradert ned til alvorlig. Et konfidensintervall er ikke oppgitt, og uten analysestørrelse kan det ikke beregnes. Studiepopulasjonen var alvorlig deprimerte pasienter uten oppgitt nedre aldersgrense, mens påstanden gjelder voksne med depressiv lidelse; avviket er vurdert som alvorlig indirekthet. Konsistens og publikasjonsskjevhet lar seg ikke vurdere ut fra ett enkelt funn.',
  'Grunnlaget dekker bare åtte ukers behandling, oppgir ikke antallet som inngår i vektanalysen, og inneholder ingen registrert sammenligning mot placebo eller mot sertralin.',
  timestamptz '2026-08-19T12:45:00Z'
from knowledge.claim_revisions r
join knowledge.claims cl on cl.id = r.claim_id
join catalog.drugs d on d.id = cl.subject_drug_id
where d.canonical_name = 'mirtazapin';
