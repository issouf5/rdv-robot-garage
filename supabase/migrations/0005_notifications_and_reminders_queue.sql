-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0005 : NOTIFICATIONS & RAPPELS AUTOMATISÉS
-- ============================================================================

-- 1. FONCTION DE DÉPÔT D'UNE NOTIFICATION DANS LA FILE D'ATTENTE
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
  INSERT INTO public.notifications_queue (
    garage_id,
    canal,
    destinataire,
    message,
    status,
    tentatives
  ) VALUES (
    p_garage_id,
    p_canal,
    p_destinataire,
    p_message,
    'en_attente',
    0
  ) RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

-- 2. RÉCUPÉRATION DES NOTIFICATIONS EN ATTENTE (POUR EDGE FUNCTIONS / WORKERS)
CREATE OR REPLACE FUNCTION public.fetch_pending_notifications(
    p_limit INT DEFAULT 10
) 
RETURNS TABLE (
    id UUID,
    garage_id UUID,
    canal public.notification_channel,
    destinataire TEXT,
    message TEXT,
    tentatives INT
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    nq.id,
    nq.garage_id,
    nq.canal,
    nq.destinataire,
    nq.message,
    nq.tentatives
  FROM public.notifications_queue nq
  WHERE nq.status = 'en_attente'
    AND nq.tentatives < 3
  ORDER BY nq.created_at ASC
  LIMIT p_limit;
END;
$$;

-- Restreindre l'exécution aux Edge Functions (service_role)
REVOKE EXECUTE ON FUNCTION public.fetch_pending_notifications(INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_pending_notifications(INT) TO service_role;

-- 3. MISE À JOUR DE L'ÉTAT D'UNE NOTIFICATION APRÈS TRAITEMENT
CREATE OR REPLACE FUNCTION public.mark_notification_sent(
    p_id UUID,
    p_success BOOLEAN,
    p_erreur_log TEXT DEFAULT NULL
) 
RETURNS VOID 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
BEGIN
  IF p_success THEN
    UPDATE public.notifications_queue
    SET status = 'envoye',
        sent_at = NOW(),
        erreur_log = NULL
    WHERE id = p_id;
  ELSE
    UPDATE public.notifications_queue
    SET status = CASE WHEN tentatives + 1 >= 3 THEN 'echoue'::public.notification_status ELSE 'en_attente'::public.notification_status END,
        tentatives = tentatives + 1,
        erreur_log = p_erreur_log
    WHERE id = p_id;
  END IF;
END;
$$;

-- Restreindre l'exécution aux Edge Functions (service_role)
REVOKE EXECUTE ON FUNCTION public.mark_notification_sent(UUID, BOOLEAN, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_sent(UUID, BOOLEAN, TEXT) TO service_role;

-- 4. TRIGGER : CRÉATION AUTOMATIQUE DE NOTIFICATION LORS DE LA LIVRAISON/FIN D'UN OR
CREATE OR REPLACE FUNCTION public.trg_notify_work_order_ready()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_phone TEXT;
  v_nom_client TEXT;
  v_immat TEXT;
  v_garage_nom TEXT;
  v_msg TEXT;
BEGIN
  IF NEW.status = 'termine' AND (OLD.status IS NULL OR OLD.status != 'termine') THEN
    -- Informations client et véhicule
    SELECT c.telephone, c.nom, v.immatriculation, g.nom 
    INTO v_phone, v_nom_client, v_immat, v_garage_nom
    FROM public.customers c
    JOIN public.vehicles v ON v.id = NEW.vehicle_id
    JOIN public.garages g ON g.id = NEW.garage_id
    WHERE c.id = NEW.customer_id;

    IF v_phone IS NOT NULL AND v_phone != '' THEN
      v_msg := 'Bonjour ' || v_nom_client || ', votre véhicule (' || v_immat || ') est prêt chez ' || v_garage_nom || '. Montant total: ' || NEW.total_ttc || ' FCFA.';
      
      PERFORM public.enqueue_notification(
        NEW.garage_id,
        'whatsapp',
        v_phone,
        v_msg
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wo_notify_ready ON public.work_orders;
CREATE TRIGGER trg_wo_notify_ready 
  AFTER UPDATE OF status ON public.work_orders 
  FOR EACH ROW 
  EXECUTE FUNCTION public.trg_notify_work_order_ready();
