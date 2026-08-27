-- Migrasjon 005b — begge grenene av den miljøavhengige autorisasjonen.
--
-- MVP_IMPLEMENTATION_PLAN.md §74.18 valgte «vei a»: koblingen mellom
-- redaktørens aktørrad og brukerkontoen gjøres betinget av at kontoen finnes,
-- fordi en rad i auth.users er miljøspesifikk tilstand og ikke schema. Prisen
-- for det valget er at migrasjonen gjør forskjellige ting i forskjellige
-- miljøer, og at CI ellers aldri ville kjørt den grenen som faktisk kjører i
-- produksjon.
--
-- Denne filen betaler prisen. Den kjører BEGGE grenene av
-- workflow.ensure_named_editor_authorization():
--
--   negativ   kontoen mangler, som i enhver fersk stack: funksjonen skriver
--             ingenting og sier fra
--   positiv   kontoen opprettes inne i transaksjonen som rulles tilbake, slik
--             testene allerede gjør for alt annet, og hele produksjonsveien
--             kjøres — kobling, rolletildeling, auditrad og virkningen på
--             kvalifikasjonskontrollen
--
-- 220_provenance_seed_test.sql påstår at den migrerte tilstanden er uendret.
-- Det er en påstand om tilstanden, ikke om koden: den ville vært like sann om
-- migrasjonen aldri hadde kjørt. Assertion 1-3 her binder den negative grenen
-- til funksjonen ved å kalle den og kreve at kallet ikke skriver noe.
begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Den negative grenen: kontoen finnes ikke
-- ---------------------------------------------------------------------------
--
-- Dette er tilstanden i CI og i enhver lokal stack. Kallet er ikke en no-op som
-- går stille: statusen kommer tilbake til kalleren, og funksjonen gir i tillegg
-- en notice, slik at raden ikke kan utebli i stillhet under `supabase db push`.
select is(
  workflow.ensure_named_editor_authorization(),
  'account_missing',
  'uten brukerkontoen i auth.users rapporterer funksjonen at kontoen mangler'
);
select is_empty(
  $$select actor_key from provenance.actors where auth_user_id is not null$$,
  'den negative grenen knytter ingen aktør til en brukerkonto'
);
select is(
  (select count(*) from workflow.user_roles),
  0::bigint,
  'den negative grenen tildeler ingen rolle'
);

-- Aktørraden er en forutsetning og ikke noe funksjonen kan klare seg uten.
-- Mangler den, er migrasjonskjeden brutt, og det skal feile høyt framfor å bli
-- en stille no-op som ser ut som «kontoen manglet». throws_ok ruller tilbake
-- slettingen sammen med feilen.
select throws_ok(
  $$
    do $probe$
    begin
      delete from provenance.actors where actor_key = 'human:peder-holman';
      perform workflow.ensure_named_editor_authorization();
    end
    $probe$
  $$,
  'P0002',
  'Aktøren ''human:peder-holman'' finnes ikke; migrasjon 005a har ikke kjørt.',
  'uten aktørraden fra 005a feiler autorisasjonen høyt framfor å utebli stille'
);

-- Og aktøren kan ikke autoriseres for en annen konto enn den §74.18 navngir.
-- Uten denne grenen ville en aktør som allerede peker et annet sted fått
-- rollen tildelt til en konto som ikke er bundet til den — altså en rettighet
-- uten den attribusjonen den hviler på.
select throws_ok(
  $$
    do $probe$
    begin
      insert into auth.users (id, email)
      values ('cccccccc-0000-0000-0000-000000000009', 'feil-konto-350@test.invalid');
      update provenance.actors
      set auth_user_id = 'cccccccc-0000-0000-0000-000000000009'
      where actor_key = 'human:peder-holman';
      perform workflow.ensure_named_editor_authorization();
    end
    $probe$
  $$,
  '23001',
  'Aktøren ''human:peder-holman'' er allerede knyttet til brukerkontoen ''cccccccc-0000-0000-0000-000000000009'' og kan ikke autoriseres for en annen.',
  'en aktør som allerede peker på en annen brukerkonto blir ikke autorisert for denne'
);

-- ---------------------------------------------------------------------------
-- Den positive grenen: kontoen finnes
-- ---------------------------------------------------------------------------
--
-- Bare id og email settes. Det eneste denne testen trenger av kontoen, er at
-- fremmednøkkelen fra workflow.user_roles har noe å peke på; resten av
-- auth.users eies av autentiseringslaget og skal ikke etterlignes her. Samme
-- form som 250_publication_gate_test.sql.
insert into auth.users (id, email)
values ('a703ede9-3f58-4de9-8c85-73936d58df1f', 'redaktor-350@test.invalid');

select is(
  workflow.ensure_named_editor_authorization(),
  'authorized',
  'med brukerkontoen på plass utfører funksjonen autorisasjonen'
);

select results_eq(
  $$
    select actor_key, auth_user_id::text
    from provenance.actors
    where auth_user_id is not null
  $$,
  $$values ('human:peder-holman', 'a703ede9-3f58-4de9-8c85-73936d58df1f')$$,
  'nøyaktig én aktør er knyttet til en brukerkonto, og det er den navngitte redaktøren'
);

-- Hele tildelingen i én assertion, felt for felt. scope_id NULL betyr «uten
-- avgrensning» og valid_to NULL betyr «løpende»; begge er valg og ikke
-- utelatelser, så begge påstås.
select results_eq(
  $$
    select ur.user_id::text, ur.role_code::text,
           ur.scope_id is null, ur.valid_to is null, g.actor_key
    from workflow.user_roles ur
    join provenance.actors g on g.id = ur.granted_by_actor_id
  $$,
  $$values ('a703ede9-3f58-4de9-8c85-73936d58df1f', 'reviewer',
            true, true, 'human:peder-holman')$$,
  'det finnes nøyaktig én rolletildeling: en løpende reviewer-rolle uten avgrensning, tildelt av redaktørens egen aktør'
);

-- Selvtildelingen er ikke forbudt av noen CHECK (MVP_IMPLEMENTATION_PLAN.md
-- §74.17 punkt 3), så begrunnelsen i raden er hele sikringen. Assertionen
-- krever at ordet står FØRST og ikke bare et sted i teksten: et treff hvor som
-- helst i feltet ville også slått ut på en benektelse av det.
select ok(
  (select grant_reason from workflow.user_roles) like 'Selvtildeling%',
  'tildelingsraden navngir selvtildelingen i sin egen begrunnelse'
);

-- Tildelingen skriver sin egen auditrad, uten at migrasjonen setter noe: den
-- kommer fra user_roles_record_grant_audit_event i migrasjon 008.
select results_eq(
  $$
    select e.operation::text, e.object_schema, e.object_table, a.actor_key,
           e.new_revision_or_snapshot->>'role_code'
    from audit.events e
    join provenance.actors a on a.id = e.actor_id
  $$,
  $$values ('role_granted', 'workflow', 'user_roles', 'human:peder-holman', 'reviewer')$$,
  'tildelingen legger igjen én auditrad, attribuert til aktøren som tildelte rollen'
);

-- ---------------------------------------------------------------------------
-- Idempotens
-- ---------------------------------------------------------------------------
--
-- Vei a betyr at koblingen kan bli stående ugjort i et miljø der kontoen kommer
-- senere, og at funksjonen da skal kunne kalles på nytt. Et andre kall må
-- verken feile på exclusion constraint-en eller legge igjen en rolletildeling
-- til.
select is(
  workflow.ensure_named_editor_authorization(),
  'already_authorized',
  'et nytt kall etter en fullført autorisasjon rapporterer at den allerede er gjort'
);
select is(
  (select count(*) from workflow.user_roles),
  1::bigint,
  'et nytt kall legger ikke igjen en rolletildeling til'
);

-- ---------------------------------------------------------------------------
-- Virkningen: kvalifikasjonskravet er innfridd, publiseringsgaten er det ikke
-- ---------------------------------------------------------------------------
--
-- 220 krever at en faglig beslutning i redaktørens navn avvises med
-- insufficient_privilege så lenge kontoen mangler. Her er speilbildet, og det
-- er prøvd framfor talt: den samme handlingen går gjennom når autorisasjonen er
-- på plass.
--
-- Beslutningen er bevisst `changes_requested` og ikke `approved`. Det som
-- kontrolleres er kvalifikasjonskravet, og det leser verken beslutningstypen
-- eller utfallet. En «approved» ville derimot vært en registrert faglig
-- godkjenning uten at noen har gjennomgått noe — nøyaktig den fiktive
-- godkjenningen ANTIDEP_CONSTITUTION.md §12 forbyr, og transaksjonen som ruller
-- tilbake gjør den ikke mindre fiktiv mens den står.
select lives_ok(
  $$
    insert into workflow.review_decisions
      (claim_revision_id, claim_revision_creator_actor_id,
       review_type, decision, rationale,
       reviewer_actor_id, reviewer_actor_type, decided_at)
    select r.id, r.created_by_actor_id,
           'publication_approval', 'changes_requested',
           'Testprobe for kvalifikasjonskravet. Ingen faglig gjennomgang har funnet sted.',
           a.id, 'human', now()
    from knowledge.claim_revisions r
    cross join provenance.actors a
    where a.actor_key = 'human:peder-holman'
    order by r.id
    limit 1
  $$,
  'med brukerkonto og gyldig reviewer-rolle avviser kvalifikasjonskontrollen ikke lenger en beslutning i redaktørens navn'
);

-- Men autorisasjonen åpner ikke publiseringsgaten. De tre andre tingene Milepæl
-- B mangler (§74.4) er urørt, og gaten skal fortsatt stoppe på den første av
-- dem — ekstraksjonsverifikasjonen — og ikke på reviewer.
select throws_like(
  $$
    select knowledge.assert_claim_revision_publishable(
      (select id from knowledge.claim_revisions order by id limit 1))
  $$,
  '%uten registrert ekstraksjonsverifikasjon%',
  'rolletildelingen åpner ikke publiseringsgaten; den stopper fortsatt på den manglende ekstraksjonsverifikasjonen'
);

select * from finish();

rollback;
