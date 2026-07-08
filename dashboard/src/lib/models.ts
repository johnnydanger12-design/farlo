// Kept in sync by hand with the ALLOWED_MODELS set in
// supabase/functions/aiden-chat/index.ts (and its underlying constants in
// supabase/functions/_shared/claude-agent.ts) — the Edge Function is the real
// enforcement point, this is just what the picker offers.
export interface ChatModel {
  id: string;
  label: string;
}

export const CHAT_MODELS: ChatModel[] = [
  { id: 'claude-sonnet-5', label: 'Sonnet 5' },
  { id: 'claude-opus-4-8', label: 'Opus 4.8' },
  { id: 'claude-fable-5', label: 'Fable 5' },
];

export const DEFAULT_MODEL_ID = 'claude-sonnet-5';

export function modelLabel(id: string): string {
  return CHAT_MODELS.find((m) => m.id === id)?.label ?? id;
}
