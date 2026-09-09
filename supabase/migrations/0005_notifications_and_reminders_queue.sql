-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0005 : NOTIFICATIONS & RAPPELS AUTOMATISÉS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enqueue_notification(
    p_garage_id UUID,
    p_canal public.notification_channel,
    p_destinataire TEXT,
    p_message TEXT
) 
RETURNS UUID 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_notification_id UUID;
BEGIN
  INSERT INTO public.notifications_queue (garage_id, canal, destinataire, message, status, tentatives)
  VALUES (p_garage_id, p_canal, p_destinataire, p_message, 'en_attente', 0)
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_pending_notifications(p_limit INT DEFAULT 10) 
RETURNS TABLE (id UUID, garage_id UUID, canal public.notification_channel, destinataire TEXT, message TEXT, tentatives INT) 
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT nq.id, nq.garage_id, nq.canal, nq.destinataire, nq.message, nq.tentatives
  FROM public.notifications_queue nq
  WHERE nq.status = 'en_attente' AND nq.tentatives < 3
  ORDER BY nq.created_at ASC LIMIT p_limit;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fetch_pending_notifications(INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_pending_notifications(INT) TO service_role;
