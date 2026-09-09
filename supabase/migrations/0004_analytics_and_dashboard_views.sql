-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0004 : VUES ANALYTIQUES & DASHBOARD
-- ============================================================================

CREATE OR REPLACE VIEW public.vw_dashboard_kpi AS
SELECT 
    g.id AS garage_id,
    COALESCE(SUM(i.total_ttc), 0) AS chiffre_affaires_total,
    COALESCE(SUM(i.montant_paye), 0) AS total_encaissements,
    COALESCE(SUM(i.solde_du), 0) AS reste_a_recouvrer,
    COUNT(DISTINCT wo.id) FILTER (WHERE wo.status IN ('recu', 'en_diagnostic', 'en_cours', 'en_attente_pieces')) AS or_en_cours_count,
    COUNT(DISTINCT wo.id) FILTER (WHERE wo.status = 'livre') AS or_termines_count,
    COUNT(DISTINCT a.id) FILTER (WHERE DATE(a.date_heure) = CURRENT_DATE AND a.status = 'confirme') AS rdv_aujourdhui_count
FROM public.garages g
LEFT JOIN public.invoices i ON i.garage_id = g.id AND i.status IN ('validee', 'payee', 'partiellement_payee')
LEFT JOIN public.work_orders wo ON wo.garage_id = g.id
LEFT JOIN public.appointments a ON a.garage_id = g.id
WHERE g.id = public.current_garage_id(g.id)
GROUP BY g.id;

CREATE OR REPLACE VIEW public.vw_parts_reorder_alerts AS
SELECT 
    p.id AS part_id,
    p.garage_id,
    p.reference,
    p.designation,
    p.quantite_stock,
    p.seuil_alerte,
    (p.seuil_alerte - p.quantite_stock) AS manque_a_commander,
    p.prix_achat,
    p.emplacement
FROM public.parts p
WHERE p.quantite_stock <= p.seuil_alerte
  AND p.garage_id = public.current_garage_id(p.garage_id)
ORDER BY p.quantite_stock ASC;
