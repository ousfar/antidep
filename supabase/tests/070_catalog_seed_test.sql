-- Migrasjon 002 — katalogdata for første golden slice.
--
-- MVP_IMPLEMENTATION_PLAN.md §12 definerer den første vertikale slicen som
-- sertralin + mirtazapin × vektendring, og §19 sier at migrasjon 002 skal seede
-- kun det slicen trenger. Testen verifiserer både at dataene finnes og at
-- omfanget ikke har vokst: masseinnhold før evidenspipelinen er kvalitetsmålt
-- er eksplisitt i strid med planen (§55, Del XIX punkt 2).
begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- ---------------------------------------------------------------------------
-- Virkestoffene i slicen
-- ---------------------------------------------------------------------------
select set_eq(
  $$select canonical_name from catalog.drugs$$,
  $$values ('sertralin'), ('mirtazapin')$$,
  'katalogen inneholder nøyaktig de to virkestoffene i golden slice'
);
select is_empty(
  $$select canonical_name from catalog.drugs where status <> 'active'$$,
  'begge virkestoffene er aktive'
);

-- Constitution §3: alltid antidepressiver, aldri den forbudte formen.
select is_empty(
  $$
    select d.canonical_name
    from catalog.drugs d
    where d.canonical_name ~* 'antidepressiva'
    union all
    select c.canonical_label
    from catalog.clinical_concepts c
    where c.canonical_label ~* 'antidepressiva'
    union all
    select p.canonical_label
    from catalog.populations p
    where p.canonical_label ~* 'antidepressiva'
  $$,
  'ingen katalogetikett bruker den forbudte ordformen'
);

-- ---------------------------------------------------------------------------
-- Alternative navn og eksterne identifikatorer
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select d.canonical_name, n.name, n.name_type::text
    from catalog.drug_names n
    join catalog.drugs d on d.id = n.drug_id
    order by d.canonical_name
  $$,
  $$values ('mirtazapin', 'mirtazapine', 'alias'),
           ('sertralin', 'sertraline', 'alias')$$,
  'INN-formene er registrert som alias på riktig virkestoff'
);
select results_eq(
  $$
    select d.canonical_name, i.identifier_system::text, i.identifier_value
    from catalog.drug_identifiers i
    join catalog.drugs d on d.id = i.drug_id
    order by d.canonical_name
  $$,
  $$values ('mirtazapin', 'atc', 'N06AX11'),
           ('sertralin', 'atc', 'N06AB06')$$,
  'ATC-kodene er registrert som eksterne identifikatorer, ikke som identitet'
);

-- Norske produktdata hører til catalog.drug_products og FEST-importen i
-- migrasjon 009 og skal ikke være skrevet inn for hånd her.
select is_empty(
  $$select name from catalog.drug_names where name_type = 'trade_name'$$,
  'ingen handelsnavn er seedet; norske produktdata kommer i migrasjon 009'
);

-- ---------------------------------------------------------------------------
-- Kliniske begreper
-- ---------------------------------------------------------------------------
select set_eq(
  $$select canonical_label, concept_type::text from catalog.clinical_concepts$$,
  $$values ('vektendring', 'outcome'), ('depressiv lidelse', 'condition')$$,
  'begrepsvokabularet inneholder nøyaktig temaet og diagnosen slicen trenger'
);
select is_empty(
  $$select canonical_label from catalog.clinical_concepts where status <> 'active'$$,
  'begge begrepene er aktive'
);

-- ---------------------------------------------------------------------------
-- Populasjon
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select p.canonical_label, p.age_min_years, p.age_max_years,
           c.canonical_label, p.pregnancy_context::text, p.comorbidity_concept_id
    from catalog.populations p
    left join catalog.clinical_concepts c on c.id = p.indication_concept_id
  $$,
  $$values ('voksne med depressiv lidelse', 18::smallint, null::smallint,
            'depressiv lidelse', null::text, null::uuid)$$,
  'populasjonen har strukturert aldersgrense og indikasjon, og er ikke avgrenset på øvrige dimensjoner'
);

-- ---------------------------------------------------------------------------
-- Omfanget har ikke vokst utover slicen
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from catalog.drugs),
  2::bigint,
  'ingen øvrige pilotlegemidler er seedet (MVP_IMPLEMENTATION_PLAN.md §9)'
);
select is(
  (select count(*) from catalog.clinical_concepts),
  2::bigint,
  'ingen øvrige pilottemaer er seedet (MVP_IMPLEMENTATION_PLAN.md §11)'
);

select * from finish();

rollback;
