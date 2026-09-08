import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { supabaseAdmin, json, e164, CORS } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { data: notifs, error } = await supabaseAdmin.rpc("fetch_pending_notifications", { p_limit: 50 });
    if (error) throw error;
    const results = [];
    for (const n of notifs ?? []) {
      try {
        const to = e164(n.telephone);
        const msg = `E-Facture ${n.payload.efacture_num} générée. Montant: ${n.payload.montant} ${n.payload.devise}. Vérifiez ici: ${n.payload.lien_verif}`;
        console.log(`Notif E-Facture à ${to}: ${msg}`);
        await supabaseAdmin.rpc("mark_notification_sent", { p_id: n.id, p_ok: true, p_ref: "NOTIF-" + Date.now() });
        results.push({ id: n.id, ok: true });
      } catch (e) {
        await supabaseAdmin.rpc("mark_notification_sent", { p_id: n.id, p_ok: false, p_erreur: String(e) });
        results.push({ id: n.id, ok: false });
      }
    }
    return json({ processed: results.length });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
