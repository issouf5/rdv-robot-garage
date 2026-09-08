import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
export const supabaseAdmin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
export const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
export const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });
export function e164(telephone: string): string {
  const digits = String(telephone || "").replace(/\D/g, "");
  if (String(telephone).trim().startsWith("+")) return "+" + digits;
  if (digits.startsWith("00")) return "+" + digits.slice(2);
  if (digits.length === 8) return "+226" + digits;
  return "+" + digits;
}
// Ajoutez ici vos clés API Orange/Twilio si nécessaire dans l'environnement
