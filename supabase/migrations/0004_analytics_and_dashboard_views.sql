-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0004 : VUES ANALYTIQUES & DASHBOARD
-- ============================================================================

-- 1. VUE KPI / TABLEAU DE BORD PRINCIPAL
CREATE OR REPLACE VIEW public.vw_dashboard_kpi AS
SELECT 
    g.id AS garage_id,
    -- CA Total (Factures Validées & Payées)
    COALESCE(SUM(i.total_ttc), 0) AS chiffre_affaires_total,
    -- Encaissements effectifs
    COALESCE(SUM(i.montant_paye), 0) AS total_encaissements,
    -- Reste à recouvrir (Règlements en attente)
    COALESCE(SUM(i.solde_du), 0) AS reste_a_recouvrer,
    -- Statistiques OR
    COUNT(DISTINCT wo.id) FILTER (WHERE wo.status IN ('recu', 'en_diagnostic', 'en_cours', 'en_attente_pieces')) AS or_en_cours_count,
    COUNT(DISTINCT wo.id) FILTER (WHERE wo.status = 'livre') AS or_termines_count,
    -- Rendez-vous du jour
    COUNT(DISTINCT a.id) FILTER (WHERE DATE(a.date_heure) = CURRENT_DATE AND a.status = 'confirme') AS rdv_aujourdhui_count
FROM public.garages g
LEFT JOIN public.invoices i ON i.garage_id = g.id AND i.status IN ('validee', 'payee', 'partiellement_payee')
LEFT JOIN public.work_orders wo ON wo.garage_id = g.id
LEFT JOIN public.appointments a ON a.garage_id = g.id
WHERE g.id = public.current_garage_id(g.id)
GROUP BY g.id;

-- 2. VUE ALERTE REAPPROVISIONNEMENT EN STOCK
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

-- 3. VUE PERFORMANCE DES MÉCANICIENS / TECHNICIENS
CREATE OR REPLACE VIEW public.vw_mechanic_performance AS
SELECT 
    gu.garage_id,
    gu.id AS mecanicien_id,
    gu.nom,
    gu.prenom,
    COUNT(wo.id) AS total_or_assignes,
    COUNT(wo.id) FILTER (WHERE wo.status = 'livre') AS total_or_completes,
    COALESCE(SUM(wo.total_ttc) FILTER (WHERE wo.status = 'livre'), 0) AS ca_genere_ttc
FROM public.garage_users gu
LEFT JOIN public.work_orders wo ON wo.mecanicien_id = gu.id
WHERE gu.role = 'mecanicien'
  AND gu.actif = true
  AND gu.garage_id = public.current_garage_id(gu.garage_id)
GROUP BY gu.garage_id, gu.id, gu.nom, gu.prenom;

-- 4. VUE SUIVI MENSEL DU CHIFFRE D'AFFAIRES
CREATE OR REPLACE VIEW public.vw_monthly_revenue AS
SELECT 
    garage_id,
    TO_CHAR(created_at, 'YYYY-MM') AS mois_annee,
    COUNT(id) AS total_factures,
    COALESCE(SUM(total_ht), 0) AS total_ht,
    COALESCE(SUM(total_tva), 0) AS total_tva,
    COALESCE(SUM(total_ttc), 0) AS total_ttc,
    COALESCE(SUM(montant_paye), 0) AS encaisse
FROM public.invoices
WHERE status IN ('validee', 'payee', 'partiellement_payee')
  AND garage_id = public.current_garage_id(garage_id)
GROUP BY garage_id, TO_CHAR(created_at, 'YYYY-MM')
ORDER BY mois_annee DESC;
