// ============================================================================
// Definisjonslisten feltene i en klinisk visning står i
//
// Ett felt er et navn og en verdi, og forholdet mellom dem er semantisk: et
// `dt`/`dd`-par sier for en skjermleser at «Kildestatus» hører til «I bruk»,
// mens to `p`-er ved siden av hverandre bare ser slik ut
// (PRODUCT_INFORMATION_ARCHITECTURE.md §51, §53).
//
// Formen lå til nå i `EvidenceFinding.tsx`. Den er flyttet hit fordi kildesiden
// (§42) viser de samme feltene om den samme publikasjonen, og to utgaver av
// samme oppsett ville drevet fra hverandre — den ene ville fått en rettelse den
// andre ikke fikk (§65 «Duplicated truth»).
//
// Komponentene her bærer ingen klinisk regel. De sier hvordan et felt ser ut,
// aldri hva som skal stå i det.
// ============================================================================

import type { ReactNode } from 'react'

export interface DetailListProps {
  readonly children: ReactNode
}

/** Feltene i en visning, som en definisjonsliste. */
export function DetailList({ children }: DetailListProps) {
  return <dl className="detail-list">{children}</dl>
}

export interface DetailProps {
  readonly label: string
  readonly children: ReactNode
}

/**
 * Ett felt.
 *
 * `div`-en rundt paret er tillatt i en `dl` og holder navn og verdi sammen i
 * rutenettet. Uten den ville en to-kolonners layout kunnet skille et navn fra
 * verdien sin.
 */
export function Detail({ label, children }: DetailProps) {
  return (
    <div className="detail-list__item">
      <dt>{label}</dt>
      <dd>{children}</dd>
    </div>
  )
}

export interface DetailNoteProps {
  readonly children: ReactNode
}

/**
 * En presisering under verdien i et felt, for eksempel kildens egen
 * begrunnelse for en status. Står inne i `dd`-en, fordi den hører til verdien
 * og ikke er et felt for seg.
 */
export function DetailNote({ children }: DetailNoteProps) {
  return <span className="detail-list__note">{children}</span>
}
