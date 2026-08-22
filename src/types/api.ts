// ============================================================================
// Radtyper for kontraktslaget `api`
//
// Speiler de tre viewene migrasjon 007 og 007a eksponerer:
//
//   api.published_drugs           virkestoff Antidep har publisert påstander om
//   api.published_claims          én rad per publisert påstand
//   api.published_claim_evidence  evidensgrunnlaget bak hver påstand
//
// Kilden er migrasjonene, ikke denne filen. Kolonnekommentarene i
// `supabase/migrations/20260820140000_api_published_read_model.sql` og
// `20260821143000_api_publication_timestamps.sql` er den normative
// beskrivelsen av hva hver verdi betyr; her gjentas bare det en klient må
// vite for ikke å lese en verdi feil.
//
// ----------------------------------------------------------------------------
// Hvorfor noen vokabularer er lukkede unioner og andre bare er `string`
//
// Enum-verdiene castes til text i viewene med hensikt: kontrakten er en streng
// fra et dokumentert vokabular, ikke PostgreSQL-typen. En lukket union i
// TypeScript er derfor en påstand om databasen som ingenting her håndhever, og
// en ny enum-verdi ville gjort typen usann uten at noe feilet.
//
// Linjen er trukket etter klinisk konsekvens, ikke etter hva som er praktisk:
//
//   Lukket union der klienten forgrener på verdien, og der en uventet verdi
//   som faller i feil gren ville vært klinisk feil — kunnskapstype (§5),
//   sikkerhetsgrad (§6, §17), relasjon til evidensen (§9), hvorfor en verdi
//   mangler (§17) og kildestatus (§14).
//
//   Dokumentert `string` ellers. Å promotere et vokabular til union hører til
//   den PR-en som faktisk forgrener på det.
//
// En lukket union alene fanger ingenting i kjøretid. Bare de to vokabularene
// `claim-certainty.ts` faktisk forgrener på — kunnskapstype og sikkerhetsgrad —
// har en kontroll som gjør en ukjent verdi til en eksplisitt ukjent tilstand.
// De øvrige tre står uten, og gjeldsposten er registrert i
// MVP_IMPLEMENTATION_PLAN.md §74.7. Den PR-en som forgrener på et av dem, skal
// legge til kontrollen samtidig.
//
// Paragrafhenvisninger er til docs/ANTIDEP_CONSTITUTION.md der ikke annet står.
// ============================================================================

// ----------------------------------------------------------------------------
// Radtypene er `type`, ikke `interface`, og det er ikke en stilpreferanse
//
// supabase-js krever at hver Row oppfyller `Record<string, unknown>` for at
// schemaet skal gjenkjennes. Et interface har ingen implisitt indekssignatur og
// oppfyller den ikke; et type-alias gjør det. Skrives de om til interface,
// forkastes hele Database-typen stille og hver spørring gir `never[]` — som er
// tilordnbart til alt, så typecheck fortsetter å passere mens typene ikke
// lenger betyr noe. Kompileringsvakten i
// `src/lib/published-read-model.test.ts` finnes for å fange nettopp det.
// ----------------------------------------------------------------------------

/** Databasegenerert uuid. Aldri et navn og aldri en ekstern kode. */
export type Uuid = string

/** `timestamptz`, slik PostgREST serialiserer den: ISO 8601 med tidssone. */
export type Timestamptz = string

/** `date`, slik PostgREST serialiserer den: `YYYY-MM-DD`. */
export type DateText = string

/** `interval`, slik PostgREST serialiserer den. Ikke et tall, og ikke en dato. */
export type IntervalText = string

// ----------------------------------------------------------------------------
// Lukkede vokabularer
// ----------------------------------------------------------------------------

/**
 * De tre kunnskapstypene. Ulik epistemisk status og ulike valideringskrav; en
 * klient skal ikke presentere dem likt (§5).
 */
export const KNOWLEDGE_TYPES = [
  'deterministic_fact',
  'evidence_synthesis',
  'clinical_recommendation',
] as const
export type KnowledgeType = (typeof KNOWLEDGE_TYPES)[number]

/**
 * GRADE-sikkerhet. Merk at `no_assessable_evidence` er en vurdert tilstand og
 * ikke en lav gradering: grunnlaget er vurdert og lar seg ikke gradere, og
 * `evidence_gap` er da utfylt (§6, §17).
 */
export const CERTAINTY_LEVELS = [
  'high',
  'moderate',
  'low',
  'very_low',
  'no_assessable_evidence',
] as const
export type CertaintyLevel = (typeof CERTAINTY_LEVELS)[number]

/**
 * Antideps vurdering av hvordan et evidensfunn forholder seg til påstanden.
 * `contradicts` skal vises på lik linje med `supports` (§9).
 */
export const EVIDENCE_RELATIONSHIP_TYPES = [
  'supports',
  'partially_supports',
  'contradicts',
  'neutral_contextual',
  'indirect',
] as const
export type EvidenceRelationshipType = (typeof EVIDENCE_RELATIONSHIP_TYPES)[number]

/**
 * Hvorfor en verdi eventuelt mangler. Finnes nettopp for at en tom verdi aldri
 * skal kunne leses som en nullverdi (§17): et manglende estimat er ikke et
 * estimat på null, og et manglende konfidensintervall betyr upresist grunnlag.
 */
export const VALUE_AVAILABILITIES = [
  'reported_value',
  'not_measured',
  'not_reported',
  'not_applicable',
  'not_extractable',
  'uncertain_extraction',
] as const
export type ValueAvailability = (typeof VALUE_AVAILABILITIES)[number]

/**
 * Kildens status. En kilde kan trekkes tilbake etter at påstanden ble
 * publisert; en klient skal vise det framfor å skjule det (§14).
 */
export const SOURCE_STATUSES = [
  'active',
  'outdated',
  'superseded',
  'retracted',
  'withdrawn',
] as const
export type SourceStatus = (typeof SOURCE_STATUSES)[number]

// ----------------------------------------------------------------------------
// api.published_drugs
// ----------------------------------------------------------------------------

/** Ett virkestoff Antidep har minst én publisert påstand om. */
export type PublishedDrugRow = {
  drug_id: Uuid
  canonical_name: string
  /** Katalogstatus som tekst. Et utfaset virkestoff kan ha publiserte påstander. */
  status: string
  /**
   * ATC-koder på femte nivå, sortert. Array fordi et virkestoff kan ha flere.
   * `null` betyr at ingen kode er registrert i Antidep — ikke at virkestoffet
   * mangler en.
   */
  atc_codes: string[] | null
  /** Talt over det RLS-filtrerte settet, så tallet er kallerens egen visning. */
  published_claim_count: number
}

// ----------------------------------------------------------------------------
// api.published_claims
// ----------------------------------------------------------------------------

/** Én publisert påstand, i den revisjonen publiseringspekeren peker på. */
export type PublishedClaimRow = {
  /** Stabil identitet på tvers av revisjoner. Bruk denne til lenker (§7). */
  claim_id: Uuid
  /** Den eksakte publiserte revisjonen. Endrer seg ved hver publisering. */
  claim_revision_id: Uuid
  revision_number: number
  knowledge_type: KnowledgeType

  drug_id: Uuid
  drug_name: string
  topic_concept_id: Uuid
  topic_label: string

  statement: string
  scope: string

  /** `null` betyr uavgrenset til en registrert populasjon, ikke ukjent populasjon. */
  population_id: Uuid | null
  population_label: string | null
  /** `null` betyr at revisjonen ikke er avgrenset i tid. */
  timeframe_min: IntervalText | null
  timeframe_max: IntervalText | null
  /** Uten komparator er en effektstørrelse ikke tolkbar. */
  comparator_kind: string
  comparator_drug_id: Uuid | null
  comparator_drug_name: string | null

  /** `null` betyr at revisjonen ikke angir retning — ikke at retningen er nøytral (§17). */
  direction: string | null
  magnitude_measure: string | null
  /** `null` betyr at effekten ikke er kvantifisert, ikke at den er null (§17). */
  magnitude_value: number | null
  magnitude_unit: string | null

  qualifiers: string | null
  /** Alltid utfylt for evidenssynteser og kliniske anbefalinger (§6). */
  uncertainty_summary: string | null

  certainty_framework: string | null
  /**
   * `null` hvis og bare hvis `knowledge_type` er `deterministic_fact`: ingen
   * GRADE-vurdering gjelder for typen. Det er en annen tilstand enn
   * `no_assessable_evidence`, og ingen av dem betyr lav risiko eller ingen
   * effekt (§6, §17). Bruk `describeClaimCertainty()` framfor å forgrene her.
   */
  certainty_level: CertaintyLevel | null
  certainty_rationale: string | null
  /** Alltid utfylt når `certainty_level` er `no_assessable_evidence`. */
  evidence_gap: string | null
  /** Siste evidensvurdering. `null` for deterministiske fakta. */
  last_assessed_at: Timestamptz | null

  /**
   * Antall evidenslenker der ekstraksjonen er trukket tilbake etter
   * publisering. Normalt 0. Over 0 betyr at Antidep har underkjent deler av
   * grunnlaget under en påstand som fortsatt står publisert, og påstanden skal
   * ikke presenteres som uberørt.
   */
  withdrawn_evidence_count: number

  /** Databaseeid avtrykk av revisjonens kliniske innhold. Egnet som cachenøkkel. */
  content_hash: string
  /** Da revisjonen ble skrevet. Verken publisert eller faglig vurdert. */
  revision_created_at: Timestamptz
  /**
   * Da revisjonen som står publisert nå, ble publisert. `null` betyr ukjent
   * publiseringsdato — ikke at påstanden er upublisert, og skal ikke vises som
   * en fersk dato.
   */
  published_at: Timestamptz | null
  /**
   * Sist faglig vurdert: den menneskelige godkjenningen publiseringen hviler
   * på (§12). Finnes for alle kunnskapstyper, også deterministiske fakta.
   * `null` betyr ukjent, aldri «ikke vurdert» og aldri «nylig vurdert».
   */
  last_reviewed_at: Timestamptz | null
}

// ----------------------------------------------------------------------------
// api.published_claim_evidence
// ----------------------------------------------------------------------------

/**
 * Én evidenslenke på en publisert revisjon, med funnet og kilden under.
 * Settet er komplett med hensikt: støttende, motstridende, nøytrale og
 * indirekte lenker står side om side, og en klient skal ikke filtrere bort de
 * motstridende (§9).
 */
export type PublishedClaimEvidenceRow = {
  claim_id: Uuid
  claim_revision_id: Uuid
  claim_evidence_link_id: Uuid

  relationship_type: EvidenceRelationshipType
  /** Egen akse fra `relationship_type`: `direct` eller `indirect`. */
  directness: string
  relevance_note: string

  evidence_item_id: Uuid
  study_design: string

  population_id: Uuid | null
  population_label: string | null
  population_detail: string
  population_availability: ValueAvailability
  sample_size: number | null
  sample_size_availability: ValueAvailability

  intervention_drug_id: Uuid
  intervention_drug_name: string
  intervention_detail: string | null
  comparator_kind: string
  comparator_drug_id: Uuid | null
  comparator_drug_name: string | null
  comparator_detail: string | null

  outcome_concept_id: Uuid
  outcome_label: string
  outcome_detail: string
  timepoint_min: IntervalText | null
  timepoint_max: IntervalText | null
  timepoint_availability: ValueAvailability

  /** Retningen kilden selv rapporterer. Antideps vurdering ligger i `relationship_type`. */
  reported_direction: string
  effect_measure: string | null
  estimate: number | null
  estimate_unit: string | null
  estimate_availability: ValueAvailability
  ci_lower: number | null
  ci_upper: number | null
  ci_level_percent: number | null
  confidence_interval_availability: ValueAvailability

  limitations_text: string | null
  /** Hvor i kilden funnet står. Uten den er verifikasjon mot originalen upraktisk (§16). */
  source_locator: string

  /**
   * Aldri `null`. `true` betyr at funnet er underkjent og ikke lenger står som
   * gyldig evidens, selv om påstanden over det fortsatt er publisert. Et slikt
   * funn merkes, det skjules ikke (§14).
   */
  extraction_withdrawn: boolean
  extraction_withdrawn_at: Timestamptz | null
  extraction_withdrawal_rationale: string | null

  /** `null` betyr at ingen versjon er registrert — ikke at kilden er uendret. */
  source_version_id: Uuid | null
  source_version_retrieved_at: Timestamptz | null
  source_version_retrieved_from: string | null
  source_version_external_version: string | null
  source_version_content_hash: string | null

  source_id: Uuid
  source_type: string
  source_title: string
  source_authors_or_issuer: string
  source_publisher_or_journal: string | null
  source_publication_date: DateText | null
  source_publication_date_precision: string | null
  source_status: SourceStatus
  source_status_note: string | null
  /** Sorterte arrays: kildemodellen tillater flere, og ingen er definert som primær. */
  source_dois: string[] | null
  source_pmids: string[] | null
}
