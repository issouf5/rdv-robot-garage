-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0009 : MAINTENANCE & UTILITAIRES DE PRODUCTION
-- ============================================================================

-- 1. NETTOYAGE AUTOMATIQUE DE LA FILE D'ATTENTE DES NOTIFICATIONS
CREATE OR REPLACE FUNCTION public.purge_old_notifications(
    p_days_to_keep INT DEFAULT 30
)
RETURNS INT 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_deleted_count INT;
BEGIN
  DELETE FROM public.notifications_queue
  WHERE status IN ('envoye', 'echoue')
    AND created_at < NOW() - (p_days_to_keep || ' days')::INTERVAL;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

-- Restreindre l'exécution de la maintenance au rôle système
REVOKE EXECUTE ON FUNCTION public.purge_old_notifications(INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_notifications(INT) TO service_role;

-- 2. RECALCUL ET AUDIT DE SÉCURITÉ DU STOCK DE PIÈCES
CREATE OR REPLACE FUNCTION public.recalculate_stock_from_audit(
    p_part_id UUID
)
RETURNS INT 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_total_delta INT := 0;
BEGIN
  -- Calcul du delta cumulé depuis l'audit
  SELECT COALESCE(SUM(delta), 0) INTO v_total_delta
  FROM public.parts_stock_audit
  WHERE part_id = p_part_id;

  -- Ajustement explicite de la quantité en stock
  UPDATE public.parts
  SET quantite_stock = v_total_delta
  WHERE id = p_part_id;

  RETURN v_total_delta;
END;
$$;

-- 3. DIAGNOSTIC DU GARAGE ET DE LA BASE DE DONNÉES
CREATE OR REPLACE FUNCTION public.get_database_health_stats(
    p_garage_id UUID
)
RETURNS TABLE (
    total_clients INT,
    total_vehicules INT,
    total_ordres_reparation INT,
    total_factures INT,
    notifications_en_attente INT,
    notifications_echouees INT
)
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    (SELECT COUNT(*)::INT FROM public.customers WHERE garage_id = p_garage_id),
    (SELECT COUNT(*)::INT FROM public.vehicles WHERE garage_id = p_garage_id),
    (SELECT COUNT(*)::INT FROM public.work_orders WHERE garage_id = p_garage_id),
    (SELECT COUNT(*)::INT FROM public.invoices WHERE garage_id = p_garage_id),
    (SELECT COUNT(*)::INT FROM public.notifications_queue WHERE garage_id = p_garage_id AND status = 'en_attente'),
    (SELECT COUNT(*)::INT FROM public.notifications_queue WHERE garage_id = p_garage_id AND status = 'echoue');
END;
$$;
