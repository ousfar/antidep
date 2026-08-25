// ============================================================================
// Evidensvisningen — `/claims/:claimId/evidence`
//
// Adressen finnes, visningen gjør det ikke ennå.
//
// «Bygg evidence drawer» står som en egen PR i MVP_IMPLEMENTATION_PLAN.md §51,
// og er delt ut av denne. Adressen registreres likevel her, av to grunner:
//
//   1. `ClaimCard` krever `evidenceHref` (§74.13 punkt 4), så lenken finnes fra
//      det øyeblikket et kort rendres. Uten en rute ville den gitt «siden finnes
//      ikke» — en usann beskjed: adressen er riktig, innholdet er ikke bygget.
//   2. Adressen er en kontrakt (§55). Å avgjøre den nå betyr at evidensvisningen
//      kan bygges uten å endre verken kortet eller rutingen.
//
// Produktinvariant 9 — at brukeren alltid kan finne «Hvorfor sier Antidep
// dette?» — er dermed ikke innfridd ennå. Siden sier det selv framfor å se
// ferdig ut, og gjelden er registrert i §74.7.
// ============================================================================

import { Link, useParams } from 'react-router'
import { homePath } from '../routes'
import { usePageTitle } from '../use-page-title'

export function ClaimEvidencePage() {
  const { claimId = '' } = useParams()
  usePageTitle('Evidensgrunnlag')

  return (
    <>
      <p className="page-kicker">Evidensgrunnlag</p>
      <h2>Hvorfor sier Antidep dette?</h2>
      <div className="knowledge-notice knowledge-notice--absence" role="note">
        <p className="knowledge-notice__lead">
          Evidensvisningen er ikke bygget ennå. Adressen er riktig og vil vise påstanden,
          sikkerheten i evidensen, de støttende og de motstridende kildene og siste faglige
          vurdering.
        </p>
        <p className="knowledge-notice__caveat">
          Inntil den finnes, kan evidensgrunnlaget bak denne påstanden ikke leses i Antidep. Det er
          en mangel i verktøyet, ikke et tegn på at grunnlaget mangler.
        </p>
        <p className="knowledge-notice__detail">Påstandens identitet: {claimId}</p>
      </div>
      <p>
        <Link to={homePath()}>Tilbake til publisert kunnskap</Link>
      </p>
    </>
  )
}
