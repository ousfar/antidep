/// <reference types="vite/client" />

interface ImportMetaEnv {
  /**
   * Supabase-prosjektets URL. Struktur etablert i PR A; tas i bruk fra databaseslicene (PR B+).
   */
  readonly VITE_SUPABASE_URL?: string
  /**
   * Supabase publishable/anon-nøkkel for nettleserklienten.
   * Aldri legg service_role-/secret-nøkler i klientkode eller i repoet.
   */
  readonly VITE_SUPABASE_ANON_KEY?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
