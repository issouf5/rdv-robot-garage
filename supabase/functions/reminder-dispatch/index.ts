import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { supabaseAdmin, json, e164, CORS } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    let query = supabaseAdmin.from("reminders").select("*").eq("statut", "programme").lte("scheduled_at", new Date().toISOString()).order("scheduled_at").limit(100);
    if (body.reminder_id) query = supabaseAdmin.from("reminders").select("*").eq("id", body.reminder_id);
    const { data: reminders, error } = await query;
    if (error) throw error;
    const results = [];
    for (const r of reminders ?? []) {
      const to = e164(r.telephone);
      try {
        console.log(`Envoi ${r.canal} à ${to}: ${r.message}`);
        const mockRef = "REF-" + Math.floor(Math.random() * 10000);
        await supabaseAdmin.rpc("reminder_dispatch_done", { p_reminder: r.id, p_ok: true, p_ref: mockRef });
        results.push({ id: r.id, ok: true, ref: mockRef });
      } catch (e) {
        await supabaseAdmin.rpc("reminder_dispatch_done", { p_reminder: r.id, p_ok: false, p_erreur: String(e) });
        results.push({ id: r.id, ok: false, erreur: String(e) });
      }
    }
    return json({ traites: results.length, resultats: results });
  } catch (e) {
    return json({ erreur: String(e) }, 500);
  }
});
