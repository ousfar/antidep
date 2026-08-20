-- ============================================================================
-- Antidep migrasjon 007 — API-lesemodell
--
-- Formål: åpne den første kontrollerte leseveien fra klientflaten inn i
-- kunnskapsbasen. Etter denne migrasjonen kan en klient lese publiserte
-- påstander og evidensen under dem, og ingenting annet.
--
-- Migrasjonsnummeret navngir planlagt innhold i MVP_IMPLEMENTATION_PLAN.md
-- §18-§27, ikke filrekkefølge. Dette er den åttende migrasjonsfilen og
-- migrasjon 007; korreksjonsmigrasjon 006a står utenfor den planlagte rekken
-- (supabase/README.md, MVP_IMPLEMENTATION_PLAN.md §74.2).
--
-- Styrende dokumenter:
--   docs/MVP_IMPLEMENTATION_PLAN.md
--     §24  innholdet i denne migrasjonen
--     §42, §47, §48 test med faktisk klientrolle
--   docs/DATABASE_ARCHITECTURE.md
--     §5   eksponering er opt-in
--     §41  offentlig klient leser avledede views
--     §42  views skal ikke utilsiktet omgå RLS
--     §44  Data API-kontrakten skal være eksplisitt
--     §48  RLS er default deny
--     §56  cache kan være aggressiv fordi publisering er versjonert
--   docs/ANTIDEP_CONSTITUTION.md
--     §4   ingen publisert påstand uten sporbar kilde
--     §6   usikkerhet og fravær av evidens er eksplisitte tilstander
--     §9   motstridende evidens bevares
--     §17  ukjent skal ikke se ut som null risiko
--
-- Avgrensning: migrasjonen oppretter ingen tabeller, ingen funksjoner og ingen
-- data, og publiserer ingenting. Viewene projiserer et tomt sett til en
-- reviewbeslutning og en publisering faktisk har funnet sted
-- (MVP_IMPLEMENTATION_PLAN.md §74.4). Det er korrekt oppførsel, ikke en mangel.
--
-- ----------------------------------------------------------------------------
-- Trusselvurdering: hvorfor tre lås, og hva hver enkelt beskytter mot
--
-- DATABASE_ARCHITECTURE.md §42 krever security_invoker på views som bygger på
-- RLS-beskyttede data. Et security_invoker-view leser med kallerens rettigheter,
-- så klientrollene må ha SELECT på tabellene under. Det er den granten §44 punkt
-- 2 beskriver, og den er ny i dette steget: fram til nå har ingen klientrolle
-- hatt noe privilegium i de kanoniske schemaene.
--
-- Granten alene åpner ikke tabellene. Tre uavhengige lås står mellom en
-- klientrolle og en upublisert påstand:
--
--   1. Schema-USAGE mangler fortsatt. anon og authenticated har usage bare på
--      api (migrasjon 001). Uten usage på catalog eller knowledge kan de ikke
--      navngi tabellene i det hele tatt — «permission denied for schema
--      knowledge» — og PostgREST eksponerer bare api. Navneoppslaget for et view
--      skjer ved opprettelsen, så viewet leser videre. Låsen er kontrollert i
--      290_api_read_model_access_test.sql.
--   2. RLS slipper bare gjennom rader som er nådd fra en publisert, ikke
--      tilbaketrukket påstand. Policyene under er den egentlige radgrensen, og de
--      virker også om lås 1 skulle falle bort i en senere migrasjon.
--   3. Bare SELECT er gitt, og bare til anon og authenticated. Ingen
--      skriveprivilegier, ingen grants til service_role (§49).
--
-- Viewene er projeksjon, ikke sikkerhetsgrense. Derfor testes RLS for seg, mot
-- tabellene direkte med et midlertidig usage-grant, framfor bare gjennom
-- viewene: et view som duplikerer et predikat kan ellers få en ødelagt policy
-- til å se ut som om den virker.
--
-- Viewene bærer likevel publiseringspredikatet selv, i tillegg til RLS. Det er
-- bevisst dobbeltarbeid: hver av de to lagene skal være korrekt alene, slik at
-- verken en tapt policy eller en feilskrevet join er nok til å vise upublisert
-- eller tilbaketrukket innhold. 290 muteringstester begge lagene hver for seg,
-- nettopp fordi duplikatet ellers kunne skjult at det ene var ødelagt.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Lesbarhet: RLS-policyene som definerer det publiserte settet
--    (DATABASE_ARCHITECTURE.md §48, MVP_IMPLEMENTATION_PLAN.md §48)
--
-- Policyene er de første i Antidep. Fram til nå har RLS vært aktivert uten
-- policies, altså default deny for alle andre enn eieren.
--
-- Formen er bevisst enkel og asyklisk: policyen på knowledge.claims er
-- selvstendig, og hver øvrige policy spør bare om raden er nådd fra en rad som
-- allerede er synlig. Et EXISTS mot en RLS-beskyttet tabell filtreres av den
-- tabellens egen policy, så synligheten forplanter seg gjennom kjeden
--
--   claims → claim_revisions → claim_evidence_links → evidence_items → sources
--
-- uten at noen policy gjentar publiseringspredikatet. Ingen policy peker
-- tilbake mot et ledd foran seg; en syklus ville gitt «infinite recursion
-- detected in policy for relation» ved første spørring, ikke ved migrering.
--
-- Policyene gjelder bare SELECT. Skriveveien er og blir en kontrollert
-- SECURITY DEFINER-funksjon (DATABASE_ARCHITECTURE.md §43).
-- ----------------------------------------------------------------------------

-- Roten i kjeden. En påstand er lesbar når den har en publisert revisjon og
-- ikke er trukket tilbake. Begge leddene trengs: publiseringspekeren nulles av
-- knowledge.withdraw_claim_publication(), mens retired_at tar påstanden ut av
-- bruk uten å røre pekeren (DATABASE_ARCHITECTURE.md §36). En tilbaketrukket
-- påstand skal ikke stå igjen som gjeldende kunnskap.
create policy claims_published_read on knowledge.claims
  for select to anon, authenticated
  using (current_published_revision_id is not null and retired_at is null);

comment on policy claims_published_read on knowledge.claims is
  'Klientrollene ser bare påstander som har en publisert revisjon og ikke er trukket tilbake. Roten i synlighetskjeden: alle øvrige lesepolicyer avleder synlighet herfra.';

-- Nøyaktig den revisjonen pekeren peker på. Ikke den nyeste, ikke et utkast:
-- publisering peker på en eksakt revisjon (KNOWLEDGE_MODEL.md §19.3).
create policy claim_revisions_published_read on knowledge.claim_revisions
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claims c
      where c.current_published_revision_id = claim_revisions.id
    )
  );

comment on policy claim_revisions_published_read on knowledge.claim_revisions is
  'Bare revisjonen publiseringspekeren peker på er lesbar. Tidligere og kommende revisjoner av samme påstand er ikke synlige for klientrollene, selv om påstanden er publisert.';

-- Evidensvurderingen hører til revisjonen og arver synligheten fra den.
create policy evidence_assessments_published_read on knowledge.evidence_assessments
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claim_revisions r
      where r.id = evidence_assessments.claim_revision_id
    )
  );

comment on policy evidence_assessments_published_read on knowledge.evidence_assessments is
  'Sikkerhetsgraden er en del av den publiserte påstanden og er lesbar sammen med revisjonen den vurderer.';

-- Både støttende og motstridende lenker. Policyen skiller ikke på
-- relationship_type: motstridende evidens skal bevares og vises på lik linje
-- med støttende (ANTIDEP_CONSTITUTION.md §9). En policy som filtrerte bort
-- 'contradicts' ville gjort kunnskapsbasen usann.
create policy claim_evidence_links_published_read on knowledge.claim_evidence_links
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claim_revisions r
      where r.id = claim_evidence_links.claim_revision_id
    )
  );

comment on policy claim_evidence_links_published_read on knowledge.claim_evidence_links is
  'Alle evidenslenker på en publisert revisjon er lesbare, uansett relationship_type. Motstridende evidens er like synlig som støttende (ANTIDEP_CONSTITUTION.md §9).';

-- Evidensfunnet er lesbart når minst én synlig lenke peker på det.
create policy evidence_items_published_read on knowledge.evidence_items
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claim_evidence_links l
      where l.evidence_item_id = evidence_items.id
    )
  );

comment on policy evidence_items_published_read on knowledge.evidence_items is
  'Et evidensfunn er lesbart når en publisert påstandsrevisjon lenker til det. Funn som bare er ekstrahert, eller som bare henger på upubliserte revisjoner, er ikke synlige.';

-- Kilden bak et synlig evidensfunn. ANTIDEP_CONSTITUTION.md §4 krever at en
-- publisert påstand kan spores til en identifiserbar kilde; da må kilden være
-- lesbar for den som skal spore.
create policy sources_published_read on knowledge.sources
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.evidence_items e
      where e.source_id = sources.id
    )
  );

comment on policy sources_published_read on knowledge.sources is
  'Kilden bak et synlig evidensfunn er lesbar, slik at en publisert påstand faktisk kan spores til en identifiserbar kilde (ANTIDEP_CONSTITUTION.md §4).';

create policy source_identifiers_published_read on knowledge.source_identifiers
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.sources s
      where s.id = source_identifiers.source_id
    )
  );

comment on policy source_identifiers_published_read on knowledge.source_identifiers is
  'DOI og PMID for en synlig kilde. Uten dem er en henvisning ikke etterprøvbar utenfor Antidep.';

-- Kildeversjonen evidensfunnet faktisk ble ekstrahert fra. source_locator peker
-- inn i denne versjonen, ikke i kilden generelt, og for en levende kilde —
-- retningslinje, preparatomtale, nettside — kan samme URL peke på annet innhold
-- senere. Uten versjonen er drilldownen ikke reproduserbar
-- (DATABASE_ARCHITECTURE.md §18, ANTIDEP_CONSTITUTION.md §16).
create policy source_versions_published_read on knowledge.source_versions
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.evidence_items e
      where e.source_version_id = source_versions.id
    )
  );

comment on policy source_versions_published_read on knowledge.source_versions is
  'Den hentede kildeversjonen et synlig evidensfunn ble ekstrahert fra. Bare versjoner som faktisk bærer et synlig funn er lesbare; kildeversjoner uten publisert bruk er det ikke.';

-- Tilbaketrekking av en ekstraksjon, og bare den.
--
-- Publiseringsgaten (G6) behandler en tilbaketrukket ekstraksjon som en hard
-- blokk ved publisering, men beslutningen er append-only og kan komme *etter*
-- at påstanden ble publisert. Da flytter den verken publiseringspekeren eller
-- evidenslenkene, og uten denne policyen ville lesemodellen fortsatt vist
-- funnet som ordinær evidens. Det er samme grunn til at source_status er
-- eksponert: en kilde kan trekkes tilbake etter publisering.
--
-- Policyen er smal med hensikt. Bare review_type = 'extraction_withdrawal'
-- slipper gjennom; publiseringsgodkjenninger, med reviewers identitet og
-- begrunnelse, forblir utenfor klientflaten. Hvor mye av reviewhistorikken som
-- skal være offentlig er en governance-beslutning, ikke en implementasjonsdetalj
-- (MVP_IMPLEMENTATION_PLAN.md §74.7).
--
-- Begge utfallene må være lesbare, ikke bare extraction_withdrawn. Skjulte vi
-- extraction_upheld, ville en ekstraksjon som først ble trukket tilbake og
-- deretter opprettholdt sett tilbaketrukket ut for en klientrolle, mens eieren
-- så den som gyldig — lesemodellen ville da svart forskjellig avhengig av hvem
-- som spør. Viewet, ikke policyen, bestemmer hva som projiseres.
create policy review_decisions_extraction_withdrawal_read on workflow.review_decisions
  for select to anon, authenticated
  using (
    review_type = 'extraction_withdrawal'
    and exists (
      select 1
      from knowledge.evidence_items e
      where e.id = review_decisions.evidence_item_id
    )
  );

comment on policy review_decisions_extraction_withdrawal_read on workflow.review_decisions is
  'Beslutninger om tilbaketrekking av en ekstraksjon på et synlig evidensfunn, begge utfall. Den eneste raden i workflow en klientrolle kan nå. Publiseringsgodkjenninger er ikke lesbare: at en påstand er publisert framgår av projeksjonen, mens hvem som godkjente den og hvorfor ikke er publisert innhold.';

-- Katalogoppslagene. Et virkestoff er lesbart når det er nevnt av en synlig
-- revisjon eller et synlig evidensfunn — som subjekt, komparator eller
-- intervensjon. Komparatoren må være med: en påstand om sertralin sammenlignet
-- med mirtazapin er uleselig uten mirtazapins navn.
--
-- Merk at dette er videre enn api.published_drugs, som bare viser virkestoff
-- Antidep har publisert påstander *om*. Policyen styrer lesbarhet, viewet
-- styrer hvilken katalog Antidep utgir. De to er bevisst ikke samme predikat.
create policy drugs_published_read on catalog.drugs
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claim_revisions r
      where r.subject_drug_id = drugs.id
         or r.comparator_drug_id = drugs.id
    )
    or exists (
      select 1
      from knowledge.evidence_items e
      where e.intervention_drug_id = drugs.id
         or e.comparator_drug_id = drugs.id
    )
  );

comment on policy drugs_published_read on catalog.drugs is
  'Et virkestoff er lesbart når en publisert revisjon eller et synlig evidensfunn nevner det, som subjekt, komparator eller intervensjon. Videre enn api.published_drugs med hensikt: komparatorens navn må kunne leses for at påstanden skal gi mening.';

create policy drug_identifiers_published_read on catalog.drug_identifiers
  for select to anon, authenticated
  using (
    exists (
      select 1
      from catalog.drugs d
      where d.id = drug_identifiers.drug_id
    )
  );

comment on policy drug_identifiers_published_read on catalog.drug_identifiers is
  'Eksterne identifikatorer, foreløpig ATC, for et lesbart virkestoff.';

create policy clinical_concepts_published_read on catalog.clinical_concepts
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claims c
      where c.topic_concept_id = clinical_concepts.id
    )
    or exists (
      select 1
      from knowledge.evidence_items e
      where e.outcome_concept_id = clinical_concepts.id
    )
  );

comment on policy clinical_concepts_published_read on catalog.clinical_concepts is
  'Begrepet en synlig påstand hører under, og endepunktet et synlig evidensfunn måler. Begrepshierarkiet forøvrig er ikke eksponert i dette steget.';

create policy populations_published_read on catalog.populations
  for select to anon, authenticated
  using (
    exists (
      select 1
      from knowledge.claim_revisions r
      where r.population_id = populations.id
    )
    or exists (
      select 1
      from knowledge.evidence_items e
      where e.population_id = populations.id
    )
  );

comment on policy populations_published_read on catalog.populations is
  'Populasjonen en synlig revisjon gjelder for, eller et synlig evidensfunn studerte. Populasjonen er en gyldighetsgrense, ikke en etikett, og hører derfor med i den publiserte projeksjonen.';

-- ----------------------------------------------------------------------------
-- 2. Grants på tabellene under viewene (DATABASE_ARCHITECTURE.md §44 punkt 2)
--
-- Kun SELECT, kun til de to Data API-rollene, og kun på de tabellene viewene
-- faktisk leser. service_role får ingenting: den omgår RLS og er ikke
-- applikasjonens universalnøkkel (§49).
--
-- Granten gir ingen vei utenom viewene så lenge klientrollene mangler usage på
-- schemaene (lås 1 i trusselvurderingen over), og RLS ville uansett stoppet
-- lesing av upubliserte rader (lås 2).
-- ----------------------------------------------------------------------------
grant select on
  catalog.drugs,
  catalog.drug_identifiers,
  catalog.clinical_concepts,
  catalog.populations,
  knowledge.claims,
  knowledge.claim_revisions,
  knowledge.claim_evidence_links,
  knowledge.evidence_assessments,
  knowledge.evidence_items,
  knowledge.sources,
  knowledge.source_identifiers,
  knowledge.source_versions
to anon, authenticated;

-- Den ene tabellen i workflow lesemodellen trenger. Granten er tabellvid, men
-- policyen over slipper bare gjennom beslutninger om tilbaketrekking av en
-- ekstraksjon. workflow.user_roles — autorisasjonskilden — og de øvrige
-- workflow-tabellene har fortsatt verken grant eller policy.
grant select on workflow.review_decisions to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3. api.published_drugs
--
-- Virkestoffene Antidep faktisk har publisert kunnskap om. Et virkestoff som
-- bare opptrer som komparator står ikke her: det finnes ingen publisert påstand
-- om det, og en oppføring ville antydet at Antidep dekker stoffet.
-- ----------------------------------------------------------------------------
create view api.published_drugs
  with (security_invoker = true) as
select
  d.id                    as drug_id,
  d.canonical_name        as canonical_name,
  d.status::text          as status,
  (
    -- Aggregat, ikke join. catalog.drug_identifiers er unik på
    -- (identifier_system, identifier_value) — én ATC-kode peker på ett
    -- virkestoff — men ikke motsatt, og et virkestoff kan ha flere ATC-koder.
    -- En join her ville derfor duplisert virkestoffet i katalogen.
    select array_agg(i.identifier_value order by i.identifier_value)
    from catalog.drug_identifiers i
    where i.drug_id = d.id
      and i.identifier_system = 'atc'
  )                       as atc_codes,
  (
    select count(*)
    from knowledge.claims c
    where c.subject_drug_id = d.id
      and c.current_published_revision_id is not null
      and c.retired_at is null
  )                       as published_claim_count
from catalog.drugs d
where exists (
  select 1
  from knowledge.claims c
  where c.subject_drug_id = d.id
    and c.current_published_revision_id is not null
    and c.retired_at is null
);

comment on view api.published_drugs is
  'Virkestoff Antidep har minst én publisert påstand om. Radene filtreres av RLS på catalog.drugs og knowledge.claims, ikke av dette viewet alene. Et virkestoff som bare er komparator i en annen påstand står ikke her, men navnet er lesbart gjennom api.published_claims.';
comment on column api.published_drugs.drug_id is
  'Stabil identitet for virkestoffet, og nøkkelen andre api-objekter refererer til. Databasegenerert uuid, aldri et navn eller en ekstern kode (DATABASE_ARCHITECTURE.md §8).';
comment on column api.published_drugs.canonical_name is
  'Kanonisk norsk navn på virkestoffet, for eksempel sertralin. Handelsnavn og aliaser er ikke eksponert i dette steget; norske produktdata kommer med catalog.drug_products (MVP_IMPLEMENTATION_PLAN.md §26).';
comment on column api.published_drugs.status is
  'Katalogstatus for virkestoffet, som tekst. Et utfaset virkestoff kan fortsatt ha publiserte påstander, og statusen skal da være synlig framfor å skjules.';
comment on column api.published_drugs.atc_codes is
  'WHO ATC-koder på femte nivå, som array. Den språkuavhengige eksterne nøkkelen for virkestoffet. Array fordi et virkestoff kan ha flere ATC-koder; verdiene er sortert, slik at rekkefølgen er stabil mellom kall. NULL betyr at ingen ATC-kode er registrert i Antidep — ikke at virkestoffet mangler en.';
comment on column api.published_drugs.published_claim_count is
  'Antall publiserte påstander med dette virkestoffet som subjekt. Telles over det RLS-filtrerte settet, så tallet er alltid det samme som kallerens egen visning av api.published_claims.';

grant select on api.published_drugs to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. api.published_claims
--
-- Én rad per publisert påstand: nøyaktig den revisjonen publiseringspekeren
-- peker på, med den strukturerte betydningen og sikkerhetsgraden.
--
-- Evidensvurderingen er en LEFT JOIN med hensikt. Publiseringsgaten (G10 i
-- knowledge.assert_claim_revision_publishable()) krever en evidensvurdering for
-- evidence_synthesis og clinical_recommendation, men ikke for
-- deterministic_fact. certainty_level er derfor NULL hvis og bare hvis
-- knowledge_type er deterministic_fact. Se kolonnekommentaren: forskjellen
-- mellom «ingen GRADE-vurdering gjelder» og «grunnlaget lar seg ikke vurdere»
-- er en klinisk forskjell, ikke en teknisk (ANTIDEP_CONSTITUTION.md §6, §17).
-- ----------------------------------------------------------------------------
create view api.published_claims
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
  r.created_at                as revision_created_at
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
where c.retired_at is null;

comment on view api.published_claims is
  'Én rad per publisert påstand, med den revisjonen publiseringspekeren peker på. Joinen mot current_published_revision_id er selve publiseringsfilteret; viewet gjentar ikke predikatet, og RLS filtrerer uansett bort alt annet. Upubliserte, erstattede og tilbaketrukne påstander finnes ikke i dette settet.';
comment on column api.published_claims.claim_id is
  'Påstandens stabile identitet. Den er den samme på tvers av revisjoner og er nøkkelen en klient skal lagre, dele og lenke til (ANTIDEP_CONSTITUTION.md §7).';
comment on column api.published_claims.claim_revision_id is
  'Den eksakte publiserte revisjonen. Endrer seg ved hver publisering; bruk claim_id for stabile lenker og denne for å vite nøyaktig hvilken formulering som ble lest.';
comment on column api.published_claims.knowledge_type is
  'Deterministisk faktum, evidenssyntese eller klinisk anbefaling, som tekst. De tre har ulik epistemisk status og ulike valideringskrav, og en klient skal ikke presentere dem likt (ANTIDEP_CONSTITUTION.md §5).';
comment on column api.published_claims.statement is
  'Den presise formuleringen av påstanden, slik den ble godkjent og publisert.';
comment on column api.published_claims.scope is
  'Anvendelsesområdet formuleringen gjelder innenfor.';
comment on column api.published_claims.population_id is
  'Populasjonen påstanden gjelder for, når den er avgrenset. NULL betyr at revisjonen ikke er avgrenset til en registrert populasjon, ikke at populasjonen er ukjent.';
comment on column api.published_claims.population_label is
  'Etiketten på populasjonen. De strukturerte gyldighetsgrensene — aldersgrenser, indikasjon, graviditetskontekst, komorbiditet — er ikke eksponert i dette steget og hører til viewet som betjener kliniker-UI-et.';
comment on column api.published_claims.timeframe_min is
  'Nedre grense for tidsrommet påstanden gjelder, som intervall. NULL betyr at revisjonen ikke er avgrenset i tid.';
comment on column api.published_claims.timeframe_max is
  'Øvre grense for tidsrommet påstanden gjelder, som intervall. Alltid NULL når timeframe_min er NULL.';
comment on column api.published_claims.comparator_kind is
  'Hva påstanden sammenligner mot: et virkestoff, placebo, ingen behandling, eller ingenting. Uten komparator er en effektstørrelse ikke tolkbar.';
comment on column api.published_claims.comparator_drug_name is
  'Navnet på komparatorvirkestoffet, når comparator_kind er drug. Virkestoffet trenger ikke selv ha publiserte påstander og står da ikke i api.published_drugs.';
comment on column api.published_claims.direction is
  'Retningen påstanden angir. NULL betyr at revisjonen ikke angir en retning — ikke at retningen er nøytral eller at det ikke er noen forskjell (ANTIDEP_CONSTITUTION.md §17).';
comment on column api.published_claims.magnitude_value is
  'Tallverdien for effektstørrelsen. Alltid ledsaget av magnitude_measure, og av magnitude_unit for målene som krever enhet. NULL betyr at revisjonen ikke kvantifiserer effekten, ikke at effekten er null.';
comment on column api.published_claims.uncertainty_summary is
  'Den eksplisitte usikkerhetsvurderingen. Alltid utfylt for evidenssynteser og kliniske anbefalinger (ANTIDEP_CONSTITUTION.md §6); kan være NULL for et deterministisk faktum.';
comment on column api.published_claims.certainty_framework is
  'Metoden sikkerhetsgraden er satt med, foreløpig alltid grade når den finnes. NULL sammen med certainty_level.';
comment on column api.published_claims.certainty_level is
  'Sikkerheten i kunnskapsgrunnlaget, som tekst. To NULL-lignende tilstander må holdes fra hverandre, og ingen av dem betyr lav risiko eller ingen effekt: verdien no_assessable_evidence betyr at grunnlaget er vurdert og ikke lar seg gradere, med evidence_gap utfylt; NULL betyr at ingen GRADE-vurdering gjelder for påstandstypen, og forekommer hvis og bare hvis knowledge_type er deterministic_fact (publiseringsgaten G10 krever vurdering for de to andre typene). En klient skal ikke rendere noen av dem som en lav gradering (ANTIDEP_CONSTITUTION.md §6, §17).';
comment on column api.published_claims.evidence_gap is
  'Hva som mangler i kunnskapsgrunnlaget. Alltid utfylt når certainty_level er no_assessable_evidence, slik at tilstanden aldri står tom.';
comment on column api.published_claims.last_assessed_at is
  'Tidspunkt for siste faglige evidensvurdering av denne revisjonen (ANTIDEP_CONSTITUTION.md §7). NULL for deterministiske fakta, som ikke har en evidensvurdering. Publiseringstidspunktet og tidspunktet for den menneskelige reviewbeslutningen er bevisst ikke eksponert i dette steget: de ligger i knowledge.publication_events og workflow.review_decisions, som ingen klientrolle har tilgang til, og hvor mye av reviewhistorikken som skal være offentlig er en governance-beslutning.';
comment on column api.published_claims.withdrawn_evidence_count is
  'Antall av påstandens evidenslenker der ekstraksjonen er trukket tilbake etter publisering. Normalt 0: publiseringsgaten (G6) nekter å publisere en revisjon som hviler på en tilbaketrukket ekstraksjon, men beslutningen er append-only og kan komme etterpå, uten å flytte publiseringspekeren. Et tall over 0 betyr at Antidep har underkjent deler av grunnlaget under en påstand som fortsatt står publisert, og en klient skal ikke presentere påstanden som uberørt. Detaljene ligger i api.published_claim_evidence.';
comment on column api.published_claims.content_hash is
  'Databaseeid avtrykk av revisjonens kliniske innhold. Stabil så lenge revisjonen er publisert, og egnet som cachenøkkel (DATABASE_ARCHITECTURE.md §56). Ikke en sikkerhetsmekanisme og ikke en erstatning for claim_revision_id.';
comment on column api.published_claims.revision_created_at is
  'Når revisjonen ble registrert i databasen. Ikke publiseringstidspunktet og ikke tidspunktet for faglig vurdering; se last_assessed_at.';

grant select on api.published_claims to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. api.published_claim_evidence
--
-- Drilldownen bak «Hvorfor sier Antidep dette?»: én rad per evidenslenke på en
-- publisert revisjon, med funnet og kilden under.
--
-- Settet er komplett med hensikt. Motstridende og indirekte evidens står side
-- om side med støttende, og availability-kolonnene skiller «ikke rapportert» fra
-- «rapportert som null» (ANTIDEP_CONSTITUTION.md §9, DATABASE_ARCHITECTURE.md
-- §19.1). Et view som bare viste støttende funn ville vært en annen påstand enn
-- den som ble godkjent.
-- ----------------------------------------------------------------------------
create view api.published_claim_evidence
  with (security_invoker = true) as
select
  c.id                                as claim_id,
  r.id                                as claim_revision_id,
  l.id                                as claim_evidence_link_id,

  l.relationship_type::text           as relationship_type,
  l.directness::text                  as directness,
  l.relevance_note                    as relevance_note,

  e.id                                as evidence_item_id,
  e.design_code::text                 as study_design,

  e.population_id                     as population_id,
  ep.canonical_label                  as population_label,
  e.population_detail                 as population_detail,
  e.population_availability::text     as population_availability,
  e.sample_size                       as sample_size,
  e.sample_size_availability::text    as sample_size_availability,

  e.intervention_drug_id              as intervention_drug_id,
  ed.canonical_name                   as intervention_drug_name,
  e.intervention_detail               as intervention_detail,
  e.comparator_kind::text             as comparator_kind,
  e.comparator_drug_id                as comparator_drug_id,
  ecd.canonical_name                  as comparator_drug_name,
  e.comparator_detail                 as comparator_detail,

  e.outcome_concept_id                as outcome_concept_id,
  eo.canonical_label                  as outcome_label,
  e.outcome_detail                    as outcome_detail,
  e.timepoint_min                     as timepoint_min,
  e.timepoint_max                     as timepoint_max,
  e.timepoint_availability::text      as timepoint_availability,

  e.reported_direction::text          as reported_direction,
  e.effect_measure::text              as effect_measure,
  e.estimate                          as estimate,
  e.estimate_unit::text               as estimate_unit,
  e.estimate_availability::text       as estimate_availability,
  e.ci_lower                          as ci_lower,
  e.ci_upper                          as ci_upper,
  e.ci_level_percent                  as ci_level_percent,
  e.confidence_interval_availability::text
                                      as confidence_interval_availability,

  e.limitations_text                  as limitations_text,
  e.source_locator                    as source_locator,

  -- Gjeldende ekstraksjonstilstand. Avledet på nøyaktig samme måte som
  -- publiseringsgaten G6 avleder den — siste beslutning av typen
  -- extraction_withdrawal — slik at lesemodellen og gaten ikke kan svare
  -- forskjellig på «er dette funnet trukket tilbake?».
  coalesce(ew.decision = 'extraction_withdrawn', false)
                                      as extraction_withdrawn,
  case when ew.decision = 'extraction_withdrawn' then ew.decided_at end
                                      as extraction_withdrawn_at,
  case when ew.decision = 'extraction_withdrawn' then ew.rationale end
                                      as extraction_withdrawal_rationale,

  -- Kildeversjonen funnet ble ekstrahert fra, når den er registrert.
  e.source_version_id                 as source_version_id,
  sv.retrieved_at                     as source_version_retrieved_at,
  sv.retrieved_from                   as source_version_retrieved_from,
  sv.external_version                 as source_version_external_version,
  sv.content_hash                     as source_version_content_hash,

  s.id                                as source_id,
  s.source_type::text                 as source_type,
  s.title                             as source_title,
  s.authors_or_issuer                 as source_authors_or_issuer,
  s.publisher_or_journal              as source_publisher_or_journal,
  s.publication_date                  as source_publication_date,
  s.publication_date_precision::text  as source_publication_date_precision,
  s.source_status::text               as source_status,
  s.status_note                       as source_status_note,
  -- Aggregater, ikke joins og ikke skalarer. knowledge.source_identifiers er unik
  -- på (identifier_system, identifier_value), ikke på (source_id,
  -- identifier_system), så en kilde kan ha flere DOI-er — parallellpublisering
  -- gir det. Med join ville ett evidensfunn blitt til to rader og sett ut som to
  -- uavhengige funn; med «velg den laveste» ville de øvrige gyldige
  -- identifikatorene forsvunnet, og en vilkårlig kanonisering blitt en offentlig
  -- kontrakt. Ingen av identifikatorene er definert som primær, så alle følger
  -- med, sortert.
  (
    select array_agg(i.identifier_value order by i.identifier_value)
    from knowledge.source_identifiers i
    where i.source_id = s.id and i.identifier_system = 'doi'
  )                                   as source_dois,
  (
    select array_agg(i.identifier_value order by i.identifier_value)
    from knowledge.source_identifiers i
    where i.source_id = s.id and i.identifier_system = 'pmid'
  )                                   as source_pmids
from knowledge.claims c
join knowledge.claim_revisions r
  on r.id = c.current_published_revision_id
join knowledge.claim_evidence_links l
  on l.claim_revision_id = r.id
join knowledge.evidence_items e
  on e.id = l.evidence_item_id
join knowledge.sources s
  on s.id = e.source_id
join catalog.drugs ed
  on ed.id = e.intervention_drug_id
join catalog.clinical_concepts eo
  on eo.id = e.outcome_concept_id
left join catalog.populations ep
  on ep.id = e.population_id
left join catalog.drugs ecd
  on ecd.id = e.comparator_drug_id
left join knowledge.source_versions sv
  on sv.id = e.source_version_id
left join lateral (
  select rd.decision, rd.decided_at, rd.rationale
  from workflow.review_decisions rd
  where rd.evidence_item_id = e.id
    and rd.review_type = 'extraction_withdrawal'
  order by rd.decided_at desc, rd.created_at desc, rd.id desc
  limit 1
) ew on true
where c.retired_at is null;

comment on view api.published_claim_evidence is
  'Evidensgrunnlaget bak hver publiserte påstand: én rad per evidenslenke, med funnet og kilden. Dette er drilldownen ANTIDEP_CONSTITUTION.md §4 og §16 krever. Settet er komplett: støttende, motstridende, nøytrale og indirekte lenker står side om side, og en klient skal ikke filtrere bort de motstridende (§9).';
comment on column api.published_claim_evidence.claim_id is
  'Påstanden funnet er lenket til. Join-nøkkelen mot api.published_claims.';
comment on column api.published_claim_evidence.relationship_type is
  'Antideps eksplisitte vurdering av hvordan funnet forholder seg til påstanden: støtter, motsier, er nøytralt kontekstuelt, eller er indirekte. Ikke en referanseliste — en kilde om samme tema er ikke støtte i seg selv.';
comment on column api.published_claim_evidence.directness is
  'Om funnet treffer påstandens populasjon, endepunkt, komparator og tidsrom direkte. Egen akse fra relationship_type, slik at et indirekte funn som motsier påstanden kan uttrykkes.';
comment on column api.published_claim_evidence.relevance_note is
  'Hvorfor funnet har nettopp denne relasjonen til nettopp denne formuleringen.';
comment on column api.published_claim_evidence.population_availability is
  'Hvorfor population_id eventuelt mangler: rapportert verdi, ikke rapportert i kilden, ikke aktuelt, eller usikker ekstraksjon. Kolonnen finnes for at en tom verdi aldri skal kunne leses som en nullverdi (DATABASE_ARCHITECTURE.md §19.1).';
comment on column api.published_claim_evidence.sample_size_availability is
  'Samme semantikk som population_availability, for utvalgsstørrelsen. sample_size NULL med not_reported betyr at kilden ikke oppgir tallet, ikke at utvalget var tomt.';
comment on column api.published_claim_evidence.timepoint_availability is
  'Samme semantikk, for måletidspunktet.';
comment on column api.published_claim_evidence.estimate_availability is
  'Samme semantikk, for effektestimatet. Et manglende estimat er ikke et estimat på null (ANTIDEP_CONSTITUTION.md §17).';
comment on column api.published_claim_evidence.confidence_interval_availability is
  'Samme semantikk, for konfidensintervallet. Et manglende intervall betyr upresist grunnlag, ikke presist grunnlag.';
comment on column api.published_claim_evidence.reported_direction is
  'Retningen kilden selv rapporterer, som tekst. Antideps egen vurdering av forholdet til påstanden ligger i relationship_type, ikke her.';
comment on column api.published_claim_evidence.source_locator is
  'Hvor i kilden funnet står, for eksempel tabell eller sidetall. Uten den er en verifikasjon mot originalen upraktisk (ANTIDEP_CONSTITUTION.md §16).';
comment on column api.published_claim_evidence.source_status is
  'Kildens status, som tekst. En kilde kan bli trukket tilbake eller erstattet etter at påstanden ble publisert; publiseringsgaten kontrollerer status ved publisering, ikke etterpå. Statusen er derfor eksponert, og en klient skal vise en tilbaketrukket kilde som tilbaketrukket framfor å skjule den (ANTIDEP_CONSTITUTION.md §14).';
comment on column api.published_claim_evidence.source_status_note is
  'Begrunnelsen for en kildestatus som ikke er active. Alltid utfylt når statusen krever det.';
comment on column api.published_claim_evidence.source_dois is
  'DOI-er for kilden, som sortert array. Array framfor skalar fordi kildemodellen tillater flere — parallellpublisering gir det — og ingen av dem er definert som primær. Å velge én ville gjort en vilkårlig kanonisering til offentlig kontrakt. NULL betyr at ingen DOI er registrert i Antidep, ikke at kilden mangler en.';
comment on column api.published_claim_evidence.source_pmids is
  'PMID-er for kilden, som sortert array. Samme NULL- og flertallssemantikk som source_dois.';
comment on column api.published_claim_evidence.extraction_withdrawn is
  'Om Antidep har trukket tilbake denne ekstraksjonen. Aldri NULL: false betyr at ingen tilbaketrekking er registrert, eller at en tidligere tilbaketrekking er opphevet. true betyr at funnet er underkjent og ikke lenger står som gyldig evidens, selv om påstanden over det fortsatt er publisert — beslutningen er append-only og kan komme etter publiseringen. En klient skal ikke presentere et slikt funn som normalt gjeldende (ANTIDEP_CONSTITUTION.md §14).';
comment on column api.published_claim_evidence.extraction_withdrawn_at is
  'Når ekstraksjonen ble trukket tilbake. NULL når extraction_withdrawn er false.';
comment on column api.published_claim_evidence.extraction_withdrawal_rationale is
  'Begrunnelsen for tilbaketrekkingen. NULL når extraction_withdrawn er false: begrunnelsen for en beslutning som opprettholdt ekstraksjonen er redaksjonell saksbehandling, ikke publisert innhold.';
comment on column api.published_claim_evidence.source_version_id is
  'Den hentede kildeversjonen funnet ble ekstrahert fra. NULL betyr at ingen versjon er registrert for funnet — ikke at kilden er uendret siden ekstraksjonen.';
comment on column api.published_claim_evidence.source_version_retrieved_at is
  'Når kildeversjonen ble hentet. For en levende kilde er dette tidspunktet det source_locator faktisk peker inn i; kilden kan ha endret seg siden.';
comment on column api.published_claim_evidence.source_version_retrieved_from is
  'Hvor kildeversjonen ble hentet fra.';
comment on column api.published_claim_evidence.source_version_external_version is
  'Kildens egen versjonsbetegnelse, når den finnes, for eksempel utgavenummer på en retningslinje.';
comment on column api.published_claim_evidence.source_version_content_hash is
  'Avtrykk av det hentede innholdet, slik at det kan avgjøres om en senere henting er samme tekst. Lagringsreferansen til selve innholdet er bevisst ikke eksponert.';

grant select on api.published_claim_evidence to anon, authenticated;
