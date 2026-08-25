// ============================================================================
// Ukjent adresse
//
// Siden sier at Antidep ikke kjenner adressen, og ingenting om klinikk. En
// «finner ikke»-side som formulerer seg om innhold, ville gjort en feilskrevet
// URL til et utsagn om kunnskap (ANTIDEP_CONSTITUTION.md §17).
// ============================================================================

import { Link, useLocation } from 'react-router'
import { homePath } from '../routes'
import { usePageTitle } from '../use-page-title'

export function NotFoundPage() {
  const { pathname } = useLocation()
  usePageTitle('Ukjent adresse')

  return (
    <>
      <h2>Ukjent adresse</h2>
      <p>
        Antidep kjenner ikke adressen <code>{pathname}</code>. Det er et utsagn om adressen, ikke om
        klinisk kunnskap.
      </p>
      <p>
        <Link to={homePath()}>Tilbake til publisert kunnskap</Link>
      </p>
    </>
  )
}
