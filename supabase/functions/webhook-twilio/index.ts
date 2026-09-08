import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { supabaseAdmin, json, CORS } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const form = await req.formData();
  const sid = form.get("MessageSid") as string | null;
  const status = form.get("MessageStatus") as string | null;
  if (sid && status) {
    const ok = ["sent", "delivered", "read"].includes(status);
    const { data } = await supabaseAdmin.from("reminders").select("id").eq("provider_ref", sid).maybeSingle();
    if (data) await supabaseAdmin.rpc("reminder_dispatch_done", { p_reminder: data.id, p_ok: ok, p_erreur: ok ? null : status });
    return json({ ok: true });
  }
  const reply = "Merci, nous avons bien reçu votre message.";
  const twiml = `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${reply}</Message></Response>`;
  return new Response(twiml, { headers: { "Content-Type": "text/xml" } });
});
