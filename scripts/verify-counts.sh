#!/usr/bin/env bash
#
# Kontrollerer at tallene i styringsdokumentene stemmer med kilden.
#
# Bakgrunn: to ganger har et tall vært feil i planen, ikke fordi noen regnet
# feil, men fordi tallet ble arvet fra en gjeldspost eller en hand-off og ført
# videre i god tro (MVP_IMPLEMENTATION_PLAN.md §74.8). Et tall ingenting
# kontrollerer, driver. Denne vaktposten er derfor maskinell, som resten av
# konvensjonene i supabase/tests/030_conventions_test.sql.
#
# Kilden vinner alltid. Slår kontrollen ut, er dokumentet feil — ikke koden.
#
# Kun kildekode: ingen database, ingen Docker, ingen npm-avhengigheter. Kjøres
# i CI-jobben «Lint, format, typecheck, test og build».
#
#   ./scripts/verify-counts.sh
#
# Exit 0 = alle påstander stemmer. Exit 1 = avvik, eller en påstand som ikke
# lenger lar seg finne i dokumentet.

set -uo pipefail
cd "$(dirname "$0")/.."

PLAN=docs/MVP_IMPLEMENTATION_PLAN.md
feil=0

# Rapporter én påstand. En påstand som ikke finnes er et brudd, ikke et
# frikort: uten dette ville en omformulering i planen gjort vakten stille.
sjekk() {
  local navn=$1 paastatt=$2 faktisk=$3 kilde=$4
  if [ -z "$paastatt" ]; then
    printf '  FEIL     %-26s fant ingen påstand i %s\n' "$navn" "$PLAN"
    feil=1
  elif [ "$paastatt" != "$faktisk" ]; then
    printf '  AVVIK    %-26s dokumentet sier %s, %s sier %s\n' \
      "$navn" "$paastatt" "$kilde" "$faktisk"
    feil=1
  else
    printf '  ok       %-26s %s\n' "$navn" "$faktisk"
  fi
}

echo "Kontrollerer tallpåstander i $PLAN mot kilden."
echo

# 1. pgTAP-assertions.
#
# Summen av plan(N) er sann bare når suiten faktisk passerer: en feil plan(N)
# gir «Looks like you planned X but ran Y» i npm run db:test, som kjører i sin
# egen CI-jobb. Her er summen den raske stedfortrederen, slik at et tall i
# planen kan kontrolleres uten å starte en database.
sjekk "pgTAP-assertions" \
  "$(grep -oE 'teller nå [0-9]+' "$PLAN" | grep -oE '[0-9]+' | head -1)" \
  "$(grep -hoE 'select plan\([0-9]+\)' supabase/tests/*.sql | grep -oE '[0-9]+' | paste -sd+ | bc)" \
  "summen av plan(N)"

# 2. Testfiler.
sjekk "testfiler" \
  "$(grep -oE '[0-9]+ testfiler' "$PLAN" | grep -oE '[0-9]+' | head -1)" \
  "$(ls supabase/tests/*.sql | wc -l | tr -d ' ')" \
  "supabase/tests/"

# 3. Enum-typer totalt. Dette er tallet som var feil i §74.7 fram til 006a.
sjekk "enum-typer totalt" \
  "$(grep -oE '[0-9]+ enum-typer' "$PLAN" | grep -oE '[0-9]+' | head -1)" \
  "$(grep -hcE '^create type ' supabase/migrations/*.sql | paste -sd+ | bc)" \
  "create type i migrasjonene"

# 4. Enum-typer per migrasjon.
#
# Totalen alene ville ikke fanget at fordelingen er feil, og det var nettopp
# fordelingen som drev fra hverandre: gjeldsposten oppga 37 for både 005 og 006.
# Tallene er formulert som antallet lagt til i hver migrasjon, i filrekkefølge.
#
# Påstanden brytes over to linjer i planen. En linjebasert grep fanget derfor
# bare prefikset fram til bruddet, og siste ledd stod ukontrollert — en
# mutasjon av det overlevde. Linjeskift normaliseres nå bort før mønsteret
# brukes.
plan_flat=$(tr '\n' ' ' < "$PLAN" | tr -s ' ')
paastatt_fordeling=$(
  printf '%s' "$plan_flat" \
    | grep -oE 'henholdsvis [0-9]+(, [0-9]+)*(,? og [0-9]+)?' \
    | head -1 | grep -oE '[0-9]+' | paste -sd, -
)
faktisk_fordeling=$(
  grep -hcE '^create type ' supabase/migrations/*.sql | paste -sd, -
)

antall_paastatt=$(printf '%s' "$paastatt_fordeling" | tr ',' '\n' | grep -c .)
antall_faktisk=$(printf '%s' "$faktisk_fordeling" | tr ',' '\n' | grep -c .)

# Fordelingen skal oppgi ett ledd per migrasjonsfil, verken flere eller færre.
#
# Å bare sammenligne så mange ledd som planen oppgir — uten å kontrollere at
# avkortingen er berettiget — gjorde en kort påstand til en stille godkjenning:
# en påstand som var kortere enn den skulle, matchet alltid sitt eget prefiks.
#
# Restpåstanden under fanget det så lenge det siste oppgitte leddet var det
# siste som ikke var null. Migrasjon 007a la ikke til enum-typer, og da ble
# halen null: en påstand forkortet til ni ledd passerte restpåstanden, samtidig
# som prosaen rundt den fortsatt sa «de ti migrasjonsfilene». Derfor kreves nå
# fullstendighet direkte. Restpåstanden beholdes som en andre linje, ikke som
# den eneste.
if [ "$antall_paastatt" -ne "$antall_faktisk" ]; then
  printf '  AVVIK    %-26s dokumentet oppgir %s ledd, men det finnes %s migrasjonsfiler\n' \
    "enum-typer per migrasjon" "$antall_paastatt" "$antall_faktisk"
  feil=1
else
  sjekk "enum-typer per migrasjon" \
    "$paastatt_fordeling" \
    "$(printf '%s' "$faktisk_fordeling" | cut -d, -f1-"${antall_paastatt:-0}")" \
    "create type per fil"

  # Restpåstanden: migrasjonene planen ikke lister opp, la ikke til enum-typer.
  rest=$(printf '%s' "$faktisk_fordeling" | tr ',' '\n' | tail -n +"$((antall_paastatt + 1))")
  rest_ikke_null=$(printf '%s' "$rest" | grep -vc '^0$' || true)
  sjekk "enum-typer etter de oppgitte" "0" "${rest_ikke_null:-0}" \
    "antall migrasjoner med enum-typer utover de $antall_paastatt planen lister"
fi

echo
if [ "$feil" -ne 0 ]; then
  cat <<'HJELP'
Minst én påstand stemmer ikke med kilden.

Kilden vinner: rett tallet i dokumentet, ikke i koden. Står det «fant ingen
påstand», er setningen omformulert slik at vakten ikke finner den lenger —
rett da enten setningen eller mønsteret her, framfor å fjerne kontrollen.

Tilstandstall som ikke dekkes her — publiserte påstander, RLS-policyer,
tabeller med klientgrant — krever en kjørende database. Se supabase/README.md.
HJELP
  exit 1
fi

echo "Alle kontrollerte tallpåstander stemmer med kilden."
