// ============================================================================
// Sikkerhetsgraden bak en publisert påstand, som eksplisitte tilstander
//
// `api.published_claims.certainty_level` har to NULL-lignende tilstander som
// betyr forskjellige ting, og ingen av dem betyr lav risiko eller ingen effekt
// (ANTIDEP_CONSTITUTION.md §6, §17):
//
//   no_assessable_evidence  grunnlaget er vurdert og lar seg ikke gradere.
//                           `evidence_gap` sier hva som mangler.
//   null                    ingen GRADE-vurdering gjelder for påstandstypen.
//                           Gjelder hvis og bare hvis knowledge_type er
//                           deterministic_fact (publiseringsgaten G10 krever
//                           vurdering for de to andre typene).
//
// En klient som forgrener direkte på kolonnen får de to til å se like ut ved
// første `if (!certainty_level)`. Derfor er avledningen samlet her, som en
// lukket union kallerne må dekke.
//
// Funksjonen tar imot `string | null` framfor den lukkede unionen fra
// `src/types/api.ts` med hensikt: radtypen er en påstand om databasen, ikke en
// garanti. Kommer det en verdi utenfor vokabularet — en ny enum-verdi, en
// klient mot en nyere database — skal den bli en eksplisitt ukjent tilstand,
// ikke havne i en godartet gren.
// ============================================================================

import { CERTAINTY_LEVELS, KNOWLEDGE_TYPES } from '../types/api'

/** Graderingene GRADE faktisk uttrykker, uten den vurderte ikke-graderbare. */
export type GradedCertaintyLevel = Exclude<
  (typeof CERTAINTY_LEVELS)[number],
  'no_assessable_evidence'
>

export type ClaimCertainty =
  /** Vurdert og gradert. */
  | {
      readonly kind: 'graded'
      readonly level: GradedCertaintyLevel
      readonly framework: string | null
      readonly rationale: string | null
    }
  /**
   * Vurdert, men ikke graderbar. Skal aldri vises som en lav gradering:
   * dette er et hull i kunnskapen, ikke et svakt svar.
   */
  | {
      readonly kind: 'no_assessable_evidence'
      readonly evidenceGap: string | null
      readonly rationale: string | null
    }
  /**
   * Deterministisk faktum. GRADE gjelder ikke for påstandstypen, og fraværet
   * av gradering er dermed korrekt — ikke en manglende vurdering. Datoen for
   * menneskelig godkjenning ligger i `last_reviewed_at` også her.
   */
  | { readonly kind: 'not_applicable_deterministic_fact' }
  /**
   * Kontraktsbrudd. Fire grunner, alle med samme konsekvens: vis ukjent
   * sikkerhet, aldri lav og aldri ingen.
   *
   *   `unrecognised_knowledge_type`   kunnskapstypen er ikke en Antidep kjenner,
   *                                   så det er ukjent hvilken sikkerhetstilstand
   *                                   som i det hele tatt er gyldig for den.
   *   `missing_assessment`            en evidenssyntese eller klinisk anbefaling
   *                                   uten vurdering, som publiseringsgaten G10
   *                                   skal ha stoppet.
   *   `unrecognised_level`            en sikkerhetsverdi utenfor vokabularet.
   *   `assessment_on_deterministic_fact`
   *                                   et deterministisk faktum som likevel bærer
   *                                   en gradering. Migrasjon 004 tillater det
   *                                   ikke, og en GRADE-merking ville gitt
   *                                   faktumet en epistemisk status det ikke har.
   */
  | {
      readonly kind: 'unknown'
      readonly reason:
        | 'unrecognised_knowledge_type'
        | 'missing_assessment'
        | 'unrecognised_level'
        | 'assessment_on_deterministic_fact'
      readonly rawCertaintyLevel: string | null
      readonly rawKnowledgeType: string
    }

/** Feltene avledningen leser. `PublishedClaimRow` oppfyller den. */
export interface ClaimCertaintyInput {
  readonly knowledge_type: string
  readonly certainty_level: string | null
  readonly certainty_framework: string | null
  readonly certainty_rationale: string | null
  readonly evidence_gap: string | null
}

function isKnownCertaintyLevel(value: string): value is (typeof CERTAINTY_LEVELS)[number] {
  return (CERTAINTY_LEVELS as readonly string[]).includes(value)
}

function isKnownKnowledgeType(value: string): boolean {
  return (KNOWLEDGE_TYPES as readonly string[]).includes(value)
}

export function describeClaimCertainty(claim: ClaimCertaintyInput): ClaimCertainty {
  const level = claim.certainty_level
  const raw = { rawCertaintyLevel: level, rawKnowledgeType: claim.knowledge_type } as const

  // Kunnskapstypen først, og på alle veier. Det er den som avgjør hvilken
  // sikkerhetstilstand som er gyldig, så en type Antidep ikke kjenner gjør hele
  // vurderingen utolkbar — også når graderingen i seg selv ser gyldig ut. Ble
  // kontrollen bare gjort på NULL-veien, ville en fjerde kunnskapstype med en
  // gradering blitt presentert som en helt ordinær GRADE-vurdert påstand, og den
  // ukjente epistemiske kategorien vært usynlig (ANTIDEP_CONSTITUTION.md §5).
  if (!isKnownKnowledgeType(claim.knowledge_type)) {
    return { kind: 'unknown', reason: 'unrecognised_knowledge_type', ...raw }
  }

  if (level === null) {
    if (claim.knowledge_type === 'deterministic_fact') {
      return { kind: 'not_applicable_deterministic_fact' }
    }
    return { kind: 'unknown', reason: 'missing_assessment', ...raw }
  }

  if (!isKnownCertaintyLevel(level)) {
    return { kind: 'unknown', reason: 'unrecognised_level', ...raw }
  }

  // Den andre halvdelen av «NULL hvis og bare hvis deterministic_fact».
  // Publiseringsgaten og migrasjon 004 gjør dette umulig i databasen i dag;
  // avledningen hviler ikke på det, fordi den også leser data fra en database
  // den ikke selv har migrert.
  if (claim.knowledge_type === 'deterministic_fact') {
    return { kind: 'unknown', reason: 'assessment_on_deterministic_fact', ...raw }
  }

  if (level === 'no_assessable_evidence') {
    return {
      kind: 'no_assessable_evidence',
      evidenceGap: claim.evidence_gap,
      rationale: claim.certainty_rationale,
    }
  }

  return {
    kind: 'graded',
    level,
    framework: claim.certainty_framework,
    rationale: claim.certainty_rationale,
  }
}
