-- Migrasjon 005 — seedomfang for aktører, og hva som bevisst ikke er seedet.
--
-- MVP_IMPLEMENTATION_PLAN.md §29 og ANTIDEP_CONSTITUTION.md §11 og §12:
-- migrasjonen registrerer aktørene som faktisk produserte de eksisterende
-- radene, og ingenting mer. Verifikasjoner og reviewbeslutninger er utførte
-- handlinger, og ingen slik handling har funnet sted; en seedet «verified» eller
-- en seedet godkjenning ville vært nøyaktig den fiktive kontrollen og den
-- fiktive godkjenningen konstitusjonen forbyr.
--
-- Testen er derfor like mye en test av hva som ikke finnes som av hva som
-- finnes. Den skal justeres av den migrasjonen som faktisk utfører en kontroll
-- eller registrerer en reell godkjenning, ikke omgås.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Aktørene som faktisk produserte de eksisterende radene
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select actor_key, actor_type::text, agent_role::text
    from provenance.actors
    order by actor_key
  $$,
  $$values ('agent:claim-synthesis', 'agent', 'claim_synthesis'),
           ('agent:evidence-extraction', 'agent', 'evidence_extraction')$$,
  'aktørregisteret inneholder nøyaktig de to KI-rollene som produserte migrasjon 003 og 004'
);
select is_empty(
  $$select actor_key from provenance.actors where description = '' or description is null$$,
  'begge aktørene forklarer konkret hva de er'
);
select is_empty(
  $$select actor_key from provenance.actors where auth_user_id is not null$$,
  'ingen aktør er knyttet til en brukerkonto; det finnes ingen brukere ennå'
);
select is_empty(
  $$select actor_key from provenance.actors where retired_at is not null$$,
  'ingen aktør er trukket tilbake'
);

-- ---------------------------------------------------------------------------
-- Hva som bevisst ikke er seedet (ANTIDEP_CONSTITUTION.md §11, §12)
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from provenance.actors where actor_type = 'human'),
  0::bigint,
  'det finnes ingen menneskelig aktør; ingen navngitt kvalifisert redaktør er registrert ennå'
);
select is(
  (select count(*) from workflow.user_roles),
  0::bigint,
  'ingen rolletildeling er seedet; det finnes ingen brukerkontoer å tildele til'
);
select is(
  (select count(*) from workflow.evidence_verifications),
  0::bigint,
  'ingen ekstraksjonsverifikasjon er seedet; ingen separat kontroll er utført'
);
select is(
  (select count(*) from workflow.claim_verifications),
  0::bigint,
  'ingen claim-verifikasjon er seedet; ingen separat kontroll er utført'
);
select is(
  (select count(*) from workflow.review_decisions),
  0::bigint,
  'ingen reviewbeslutning er seedet; en seedet godkjenning ville vært den fiktive godkjenningen ANTIDEP_CONSTITUTION.md §12 forbyr'
);

-- Følgen av at ingenting er godkjent: ingenting er publisert heller.
--
-- Migrasjon 006 opprettet publiseringsgaten, og den endrer ikke dette bildet.
-- Den kan ikke: publisering av en evidenssyntese krever en godkjenning fra en
-- navngitt kvalifisert redaktør, og det finnes fortsatt ingen. Gaten leverer et
-- bevis på at den nekter, ikke en publisert påstand, og disse tre assertionene
-- er det maskinelle uttrykket for det. De skal justeres av migrasjonen som
-- registrerer en reell godkjenning og en reell publisering, ikke omgås.
select is(
  (select count(*) from knowledge.claims where current_published_revision_id is not null),
  0::bigint,
  'ingen påstand er publisert; ingen godkjenning finnes å publisere på'
);
select is(
  (select count(*) from knowledge.publication_events),
  0::bigint,
  'ingen publiseringshendelse er seedet; en seedet publisering ville hvilt på en godkjenning som ikke finnes'
);
-- Kontroll av at de to assertionene over ikke passerer av feil grunn: det finnes
-- faktisk revisjoner som kunne vært publisert dersom gaten hadde vært åpen.
select is(
  (select count(*) from knowledge.claim_revisions),
  2::bigint,
  'de to påstandsrevisjonene finnes fortsatt; det er gaten som stopper dem, ikke fravær av innhold'
);

-- ---------------------------------------------------------------------------
-- Attribusjonen av de eksisterende radene er sann og fullstendig
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select e.id::text
    from knowledge.evidence_items e
    join provenance.actors a on a.id = e.created_by_actor_id
    where a.actor_key <> 'agent:evidence-extraction'
  $$,
  'alle evidensfunn er attribuert til ekstraksjonsrollen som produserte dem i migrasjon 003'
);
select is_empty(
  $$
    select t.table_name || ':' || t.wrong_rows::text
    from (
      select 'knowledge.claims' as table_name, count(*) as wrong_rows
      from knowledge.claims c
      join provenance.actors a on a.id = c.created_by_actor_id
      where a.actor_key <> 'agent:claim-synthesis'
      union all
      select 'knowledge.claim_revisions', count(*)
      from knowledge.claim_revisions r
      join provenance.actors a on a.id = r.created_by_actor_id
      where a.actor_key <> 'agent:claim-synthesis'
      union all
      select 'knowledge.claim_evidence_links', count(*)
      from knowledge.claim_evidence_links l
      join provenance.actors a on a.id = l.created_by_actor_id
      where a.actor_key <> 'agent:claim-synthesis'
      union all
      select 'knowledge.evidence_assessments', count(*)
      from knowledge.evidence_assessments ea
      join provenance.actors a on a.id = ea.created_by_actor_id
      where a.actor_key <> 'agent:claim-synthesis'
    ) t
    where t.wrong_rows > 0
  $$,
  'påstandslaget er i sin helhet attribuert til synteserollen som produserte det i migrasjon 004'
);

select * from finish();

rollback;
