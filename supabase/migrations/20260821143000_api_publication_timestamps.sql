-- ============================================================================
-- Antidep migrasjon 007a — publiserings- og reviewtidspunkt i api-lesemodellen
--
-- Formål: gi hver publisert påstand en dato en kliniker kan lese — når den ble
-- publisert, og når den sist ble faglig godkjent — uten å åpne reviewhistorikken.
--
-- Migrasjonsnummeret navngir planlagt innhold i MVP_IMPLEMENTATION_PLAN.md
-- §18-§27, ikke filrekkefølge. Dette er den tiende migrasjonsfilen. Den utvider
-- api-lesemodellen fra migrasjon 007 (§24) og står utenfor den planlagte rekken,
-- og får derfor en bokstav — samme konvensjon som korreksjonsmigrasjon 006a.
-- Nummeret 009 er reservert for DrugProduct/importfundamentet (§26) og tas ikke
-- her (supabase/README.md, MVP_IMPLEMENTATION_PLAN.md §74.2).
--
-- Styrende dokumenter:
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §24     api-lesemodellen denne migrasjonen utvider
--     §30     kliniker-UI-et som er triggeren for gjeldsposten
--     §74.7   gjeldsposten «Publiseringstidspunkt og reviewtidspunkt er ikke
--             eksponert i api», med governance-beslutningen som forutsetning
--   docs/PRODUCT_INFORMATION_ARCHITECTURE.md
--     §41     «Sist faglig vurdert» er et felt i evidensvisningen
--     §58     klinikeren ser publisert status, ikke workflow-støy
--   docs/CONTENT_GOVERNANCE.md
--     §36-§37 reviewsyklus og utløpt review som synlig systemtilstand
--   docs/DATABASE_ARCHITECTURE.md
--     §5      eksponering er opt-in
--     §7.3    tidsbegreper holdes adskilt
--     §42     views skal ikke utilsiktet omgå RLS
--     §48     RLS er default deny
--     §50     privilegerte funksjoner
--   docs/ANTIDEP_CONSTITUTION.md
--     §12     menneskelig faglig godkjenning fra navngitt kvalifisert redaktør
--     §17     ukjent skal ikke se ut som null risiko
--
-- ----------------------------------------------------------------------------
-- Governance-beslutningen denne migrasjonen hviler på
--
-- Gjeldsposten i §74.7 krevde en avgjørelse før den kunne innfris: hvor mye av
-- reviewhistorikken skal være offentlig? Avgjørelsen er tatt, og den er den
-- smaleste av de mulige: **kun tidsstempler**. Ingen aktøridentitet, ingen
-- beslutningstype, ingen begrunnelse.
--
-- Den følger PRODUCT_INFORMATION_ARCHITECTURE.md §58: klinikeren skal se «sist
-- faglig vurdert», ikke hvem som vurderte eller hva som ble sagt underveis. At
-- en påstand er publisert, er publisert innhold. Hvem som godkjente den, og
-- hvorfor, er det ikke.
--
-- Konsekvensen for utformingen er den viktigste delen av denne migrasjonen:
-- workflow.review_decisions åpnes **ikke** for publiseringsgodkjenninger. Den
-- opplagte implementasjonen — en RLS-policy som slipper gjennom godkjenningene
-- og et view som bare projiserer decided_at — ville vært feil, fordi
-- klientrollene allerede har et tabellvidt SELECT-grant på review_decisions fra
-- migrasjon 007. En policy som åpner raden, åpner den for hele granten, og
-- reviewers identitet og begrunnelse ville ligget ett view unna. RLS er en
-- radgrense, ikke en kolonnegrense.
--
-- I stedet fryses godkjenningstidspunktet på publiseringshendelsen når den
-- skrives. Det er samme grep som workflow.review_decisions.approved_evidence_set_digest
-- (migrasjon 006): en avledet verdi databasen eier, låst til det den beskrev i
-- øyeblikket den ble skrevet. Godkjenningen selv forblir utenfor klientflaten.
--
-- Sideeffekten er at verdien er *frosset*: en senere reviewbeslutning på samme
-- revisjon flytter den ikke. I dag er det riktig og ikke en begrensning, fordi
-- det ikke finnes noen reviewsyklus å flytte den med — tidsbasert utløp av
-- review er fortsatt uinnfridd gjeld (§74.7). Migrasjonen som innfører
-- workflow.review_requirements / review_due_at må ta stilling til om en
-- fornyet godkjenning skal oppdatere «sist faglig vurdert», og det er der den
-- beslutningen hører hjemme.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Godkjenningstidspunktet fryses på publiseringshendelsen
--
-- Hendelsen registrerer allerede hvem som publiserte og når. Den registrerer
-- ikke hvilken faglig godkjenning publiseringen hvilte på, selv om
-- publiseringsgaten (G11/G12) leser nettopp den for å slippe publiseringen
-- gjennom. Kolonnen lukker det gapet, og gjør datoen lesbar uten at beslutningen
-- den kommer fra blir det.
-- ----------------------------------------------------------------------------
alter table knowledge.publication_events
  add column approval_decided_at timestamptz;

comment on column knowledge.publication_events.approval_decided_at is
  'Tidspunktet for den menneskelige faglige godkjenningen denne publiseringen hvilte på, kopiert fra workflow.review_decisions.decided_at da hendelsen ble skrevet (ANTIDEP_CONSTITUTION.md §12). Databaseeid og frosset: en senere reviewbeslutning på samme revisjon endrer den ikke. NULL på avpublisering, som ikke har noen etterfølgende revisjon å være godkjent for.';

-- En godkjenningsdato uten en publisert revisjon er meningsløs: det ville vært
-- en godkjenning av ingenting. Den motsatte retningen håndheves bevisst ikke —
-- se triggeren under.
alter table knowledge.publication_events
  add constraint publication_events_approval_requires_revision_check
  check (approval_decided_at is null or revision_id is not null);

-- Verdien eies av databasen, som created_at og som evidensavtrykket i migrasjon
-- 006. Var den kallerstyrt, kunne den som publiserer oppgi en annen dato enn den
-- godkjenningen faktisk har, og «sist faglig vurdert» ville vært et tall den
-- kontrollerte parten selv valgte. Triggeren overskriver derfor alltid det
-- kalleren måtte ha sendt inn.
--
-- SECURITY DEFINER av samme grunn som workflow.set_review_evidence_set_digest():
-- workflow.review_decisions ligger bak RLS med default deny, og datoen må kunne
-- leses uavhengig av hvem som skriver hendelsen. Funksjonen har tomt
-- search_path, schemakvalifiserte navn, er ikke kjørbar for PUBLIC, og skriver
-- bare til raden som settes inn (DATABASE_ARCHITECTURE.md §50).
--
-- Utvalget speiler publiseringsgaten G11/G12 nøyaktig: den *gjeldende*
-- beslutningen er den siste, og bare «approved» teller. Ville vi tatt siste
-- godkjenning uansett hva som kom etter, ville en revisjon der reviewer senere
-- ba om endringer fått en dato som så ut som en gyldig godkjenning.
create function knowledge.set_publication_approval_decided_at()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_decision workflow.review_outcome;
  v_decided_at timestamptz;
begin
  if new.revision_id is null then
    new.approval_decided_at := null;
    return new;
  end if;

  select rd.decision, rd.decided_at
    into v_decision, v_decided_at
  from workflow.review_decisions rd
  where rd.claim_revision_id = new.revision_id
    and rd.review_type = 'publication_approval'
  order by rd.decided_at desc, rd.created_at desc, rd.id desc
  limit 1;

  -- Ingen godkjenning, eller en gjeldende beslutning som ikke er «approved»,
  -- gir NULL framfor en feil. Publiseringsgaten er stedet som nekter — den har
  -- feilmeldingene som navngir hva som blokkerer (G11, G12), og en trigger som
  -- også nektet ville duplisert den kontrollen på et dårligere sted.
  --
  -- Derfor er heller ikke den motsatte pairing-regelen håndhevet: en hendelse
  -- kan skrives med revisjon og uten godkjenningsdato. Den veien går bare
  -- utenom publiseringsoperasjonen, og lesemodellen behandler NULL som ukjent
  -- dato, aldri som «nylig vurdert» (ANTIDEP_CONSTITUTION.md §17).
  if v_decision is distinct from 'approved' then
    new.approval_decided_at := null;
  else
    new.approval_decided_at := v_decided_at;
  end if;

  return new;
end;
$$;

comment on function knowledge.set_publication_approval_decided_at() is
  'Gir databasen eierskap til godkjenningstidspunktet en publisering hviler på, og fryser det på hendelsen. Speiler publiseringsgaten G11/G12: den gjeldende beslutningen er den siste, og bare approved teller. SECURITY DEFINER fordi reviewbeslutningene ligger bak RLS med default deny; funksjonen leser bare og skriver bare til raden som settes inn.';

revoke execute on function knowledge.set_publication_approval_decided_at() from public;

-- Navnet sorterer foran publication_events_set_created_at, og ingen av dem
-- avhenger av den andres resultat. Hendelsestabellen er append-only (migrasjon
-- 006), så verdien kan ikke endres etter innsetting.
create trigger publication_events_set_approval_decided_at
  before insert on knowledge.publication_events
  for each row execute function knowledge.set_publication_approval_decided_at();

-- ----------------------------------------------------------------------------
-- 2. RLS: hendelsen som bærer den gjeldende publiseringen, og bare den
--
-- Fram til nå har knowledge.publication_events vært helt stengt for
-- klientrollene. Policyen åpner nøyaktig de radene som beskriver en publisering
-- som fortsatt står: hendelsen navngir den revisjonen påstanden peker på nå, og
-- påstanden er ikke trukket tilbake.
--
-- Avpubliseringer slipper ikke gjennom av seg selv: de har revision_id = NULL,
-- og likhetssammenligningen mot current_published_revision_id treffer aldri
-- NULL. Historikken forøvrig — tidligere publiseringer, rollbacks, hvem som
-- publiserte og hvorfor — forblir utenfor klientflaten.
-- ----------------------------------------------------------------------------
create policy publication_events_current_publication_read on knowledge.publication_events
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claims c
      where c.id = publication_events.claim_id
        and c.current_published_revision_id = publication_events.revision_id
        and c.retired_at is null
    )
  );

comment on policy publication_events_current_publication_read on knowledge.publication_events is
  'Hendelsen som satte den publiseringen som gjelder nå, for en påstand som ikke er trukket tilbake. Avpubliseringer, tidligere publiseringer og rollbacks er ikke lesbare. Policyen er radgrensen; kolonnegranten under avgjør hva av raden som kan leses.';

-- ----------------------------------------------------------------------------
-- 3. Grant på kolonnenivå, ikke tabellnivå
--
-- Raden policyen slipper gjennom bærer også reason og published_by_actor_id —
-- publiseringsbegrunnelsen og hvem som publiserte. Ingen av dem er publisert
-- innhold (§58), og et tabellvidt grant ville gjort dem lesbare for enhver
-- spørring som kunne nå raden.
--
-- Dette er en fjerde lås ved siden av de tre i migrasjon 007, og den er reell:
-- et security_invoker-view kan ikke projisere en kolonne kalleren mangler grant
-- på, uansett hva viewet inneholder. Et policyuttrykk kan derimot fritt
-- referere kolonner kalleren ikke har — privilegiene gjelder spørringen, ikke
-- policyen — så radgrensen svekkes ikke av at granten er smal.
--
-- Merk for vaktposter: et kolonnegrant er *ikke* synlig i has_table_privilege()
-- eller information_schema.role_table_grants. En test som bare spør om
-- tabellprivilegiet vil svare «ingen tilgang» også når kolonner er åpnet, og
-- være stille sann. Kontroller derfor role_column_grants / has_column_privilege
-- i tillegg — det gjør 270_publication_access_test.sql nå.
-- ----------------------------------------------------------------------------
-- id og created_at er med fordi lateralen i viewet trenger en deterministisk
-- «siste hendelse»-rekkefølge, og en ORDER BY er en del av spørringen: en
-- kolonne kalleren mangler grant på, gir «permission denied» selv om den aldri
-- projiseres. Begge er strukturelle og bærer verken klinisk innhold eller
-- personopplysninger. Kolonnene som gjør det — reason, published_by_actor_id,
-- published_by_actor_type — og hele forgjengerkjeden er ikke med.
grant select (id, claim_id, revision_id, published_at, created_at, approval_decided_at)
  on knowledge.publication_events to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. api.published_claims får de to datoene
--
-- Sideordnede join-er ville multiplisert raden hvis en påstand hadde flere
-- hendelser på samme revisjon — publisert, avpublisert og publisert igjen er en
-- helt vanlig historikk. Lateralen plukker den gjeldende hendelsen, og de to
-- verdiene kommer fra samme rad, slik at datoene aldri beskriver hver sin
-- publisering.
--
-- Viewet bærer publiseringspredikatet selv, i tillegg til RLS: hendelsen må
-- navngi nettopp den revisjonen påstandens peker peker på. Det er samme
-- bevisste dobbeltarbeid som i migrasjon 007 — hver av lagene skal være korrekt
-- alene.
-- ----------------------------------------------------------------------------
create or replace view api.published_claims
  with (security_invoker = true) as
select
  c.id                        as claim_id,
  r.id                        as claim_revision_id,
  r.revision_number           as revision_number,
  c.knowledge_type::text      as knowledge_type,

  c.subject_drug_id           as drug_id,
  d.canonical_name            as drug_name,
  c.topic_concept_id          as topic_concept_id,
  t.canonical_label           as topic_label,

  r.statement                 as statement,
  r.scope                     as scope,

  r.population_id             as population_id,
  p.canonical_label           as population_label,
  r.timeframe_min             as timeframe_min,
  r.timeframe_max             as timeframe_max,
  r.comparator_kind::text     as comparator_kind,
  r.comparator_drug_id        as comparator_drug_id,
  cd.canonical_name           as comparator_drug_name,

  r.direction::text           as direction,
  r.magnitude_measure::text   as magnitude_measure,
  r.magnitude_value           as magnitude_value,
  r.magnitude_unit::text      as magnitude_unit,

  r.qualifiers                as qualifiers,
  r.uncertainty_summary       as uncertainty_summary,

  ea.framework::text          as certainty_framework,
  ea.certainty_level::text    as certainty_level,
  ea.rationale                as certainty_rationale,
  ea.evidence_gap             as evidence_gap,
  ea.assessed_at              as last_assessed_at,

  (
    -- Antall lenkede evidensfunn hvis gjeldende ekstraksjonsbeslutning er
    -- tilbaketrekking. Samme avledning som publiseringsgaten G6 bruker. Uten
    -- dette ville en klient som bare viser påstandssammendraget ikke hatt noe
    -- signal om at grunnlaget er underkjent etter publisering.
    select count(*)
    from knowledge.claim_evidence_links l
    where l.claim_revision_id = r.id
      and (
        select rd.decision
        from workflow.review_decisions rd
        where rd.evidence_item_id = l.evidence_item_id
          and rd.review_type = 'extraction_withdrawal'
        order by rd.decided_at desc, rd.created_at desc, rd.id desc
        limit 1
      ) = 'extraction_withdrawn'
  )                           as withdrawn_evidence_count,

  r.content_hash              as content_hash,
  r.created_at                as revision_created_at,

  pub.published_at            as published_at,
  pub.approval_decided_at     as last_reviewed_at
from knowledge.claims c
join knowledge.claim_revisions r
  on r.id = c.current_published_revision_id
join catalog.drugs d
  on d.id = c.subject_drug_id
join catalog.clinical_concepts t
  on t.id = c.topic_concept_id
left join catalog.populations p
  on p.id = r.population_id
left join catalog.drugs cd
  on cd.id = r.comparator_drug_id
left join knowledge.evidence_assessments ea
  on ea.claim_revision_id = r.id
left join lateral (
  select pe.published_at, pe.approval_decided_at
  from knowledge.publication_events pe
  where pe.claim_id = c.id
    and pe.revision_id = r.id
  order by pe.published_at desc, pe.created_at desc, pe.id desc
  limit 1
) pub on true
where c.retired_at is null;

comment on column api.published_claims.published_at is
  'Når den revisjonen som står publisert nå, ble publisert. Transaksjonstidspunktet for publiseringshendelsen, ikke når revisjonen ble skrevet (se revision_created_at) og ikke når den ble faglig vurdert (se last_reviewed_at). Ved republisering etter avpublisering er det den siste publiseringen som gjelder, ikke den første. NULL betyr at publiseringspekeren er flyttet utenom den kontrollerte publiseringsoperasjonen og at datoen dermed er ukjent — det betyr ikke at påstanden er upublisert, og skal ikke vises som en fersk dato.';
comment on column api.published_claims.last_reviewed_at is
  'Sist faglig vurdert: tidspunktet for den menneskelige godkjenningen publiseringen hviler på (ANTIDEP_CONSTITUTION.md §12, PRODUCT_INFORMATION_ARCHITECTURE.md §58). I motsetning til last_assessed_at finnes den for alle kunnskapstyper, også deterministiske fakta uten evidensvurdering. Verdien er frosset ved publisering: en senere reviewbeslutning på samme revisjon flytter den ikke, og reviewers identitet og begrunnelse er ikke eksponert. NULL betyr ukjent godkjenningsdato, aldri «ikke vurdert» og aldri «nylig vurdert».';

