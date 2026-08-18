/// <reference types="vite/client" />

interface ImportMetaEnv {
  /**
   * Supabase-prosjektets URL. Struktur etablert i PR A; tas i bruk fra databaseslicene (PR B+).
   */
  readonly VITE_SUPABASE_URL?: string
  /**
   * Supabase publishable-nøkkel for nettleserklienten.
   * Legg ALDRI secret-/service_role-nøkler i klientkode eller i repoet.
   */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
