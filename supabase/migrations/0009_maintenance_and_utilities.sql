-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0009 : MAINTENANCE & UTILITAIRES
-- ============================================================================

CREATE OR REPLACE FUNCTION public.purge_old_notifications(p_days_to_keep INT DEFAULT 30)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_deleted_count INT;
BEGIN
  DELETE FROM public.notifications_queue
  WHERE status IN ('envoye', 'echoue') AND created_at < NOW() - (p_days_to_keep || ' days')::INTERVAL;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purge_old_notifications(INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_notifications(INT) TO service_role;
