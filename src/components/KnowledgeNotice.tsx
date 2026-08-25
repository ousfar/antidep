// ============================================================================
// De tilstandene som ikke er en påstand
//
// En klinikerflate som leser publisert kunnskap kan havne i fire tilstander der
// det ikke står noe klinisk innhold på skjermen, og de betyr helt forskjellige
// ting:
//
//   laster      vi vet ennå ingenting
//   tomt        Antidep har ingen publisert kunnskap for denne forespørselen
//   ikke funnet adressen peker ikke på noe Antidep har publisert om
//   feil        spørringen nådde ikke fram, eller ble avvist
//
// Alle fire ville vært en tom skjerm om ingen skrev dem ut, og en tom skjerm
// leses som «ingenting å bekymre seg for». Derfor er de samlet her, som synlig
// tekst med hver sin ordlyd, og ingen av dem deler utseende med de andre
// (ANTIDEP_CONSTITUTION.md §6, §17; PRODUCT_INFORMATION_ARCHITECTURE.md §17,
// §32, §65 «No-data-as-zero»).
//
// Setningen som gjentas på hver fraværstilstand står ett sted og ett sted bare.
// Skrevet på nytt per side ville den drevet fra hverandre, og det er nettopp
// den setningen som skiller «Antidep har ikke publisert dette» fra «dette er
// trygt».
// ============================================================================

import type { ReactNode } from 'react'

/** Den ene feillesningen alle fraværstilstandene deler. */
const ABSENCE_CAVEAT =
  'At Antidep ikke har publisert noe her, er ikke dokumentasjon på fravær av effekt, ' +
  'bivirkning eller risiko. Kunnskapsbasen er under oppbygging, og innhold publiseres først ' +
  'etter faglig godkjenning.'

export function KnowledgeLoading() {
  return (
    // aria-busy og live-regionen gjør ventetilstanden hørbar, ikke bare synlig.
    // Uten den er «laster» og «tomt» like for en skjermleser.
    <p className="knowledge-notice knowledge-notice--loading" aria-busy="true" aria-live="polite">
      Henter publisert kunnskap …
    </p>
  )
}

export interface KnowledgeAbsenceProps {
  /** Hva som konkret ikke finnes. Formuleres av siden, som kjenner spørsmålet. */
  readonly children: ReactNode
}

/**
 * Fravær av publisert kunnskap, med forbeholdet som hindrer at det leses som et
 * klinisk svar. Brukes både når projeksjonen er tom og når adressen ikke traff.
 */
export function KnowledgeAbsence({ children }: KnowledgeAbsenceProps) {
  return (
    <div className="knowledge-notice knowledge-notice--absence" role="note">
      <p className="knowledge-notice__lead">{children}</p>
      <p className="knowledge-notice__caveat">{ABSENCE_CAVEAT}</p>
    </div>
  )
}

export interface KnowledgeErrorProps {
  /** Den tekniske årsaken. Vises, men skilles fra den kliniske lesningen. */
  readonly message: string
}

/**
 * En feil, som en feil.
 *
 * Ordlyden sier eksplisitt at dette ikke er et svar om kunnskapen, fordi det er
 * nøyaktig den forvekslingen som gjør en nettverksfeil til «ingen kjent risiko»
 * (ANTIDEP_CONSTITUTION.md §17).
 */
export function KnowledgeError({ message }: KnowledgeErrorProps) {
  return (
    <div className="knowledge-notice knowledge-notice--error" role="alert">
      <p className="knowledge-notice__lead">
        Antidep fikk ikke hentet publisert kunnskap. Dette er en teknisk feil, ikke et svar om at
        kunnskap mangler — innholdet under er ufullstendig eller helt fraværende.
      </p>
      <p className="knowledge-notice__detail">Teknisk årsak: {message}</p>
    </div>
  )
}
