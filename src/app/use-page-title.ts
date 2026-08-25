// ============================================================================
// Sidetittelen
//
// En klientside-ruter bytter ikke dokumenttittel av seg selv. Uten dette heter
// hver adresse det samme i faneraden, i historikken og i et bokmerke — og §55
// og §57 i PRODUCT_INFORMATION_ARCHITECTURE.md gjør nettopp bokmerket og den
// delte lenken til et krav. Tittelen er også det første en skjermleser leser
// etter en navigering.
// ============================================================================

import { useEffect } from 'react'

const SUFFIX = 'Antidep'

/**
 * Setter dokumenttittelen så lenge komponenten står montert.
 *
 * Tittelen gjenopprettes ikke ved avmontering: neste side setter sin egen, og
 * en gjenoppretting ville gitt et kort glimt av forrige sides tittel.
 */
export function usePageTitle(title: string): void {
  useEffect(() => {
    document.title = title.length === 0 ? SUFFIX : `${title} – ${SUFFIX}`
  }, [title])
}
