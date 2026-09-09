-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0006 : PORTAIL CLIENT & RDV EN LIGNE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.book_appointment_online(
    p_garage_id UUID,
    p_nom TEXT,
    p_telephone TEXT,
    p_immatriculation TEXT,
    p_marque TEXT,
    p_modele TEXT,
    p_date_heure TIMESTAMPTZ,
    p_motif TEXT
)
RETURNS TABLE (appointment_id UUID, token_suivi TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer_id UUID;
  v_vehicle_id UUID;
  v_appointment_id UUID;
  v_token TEXT;
  v_clean_phone TEXT;
BEGIN
  v_clean_phone := REGEXP_REPLACE(p_telephone, '[^0-9]', '', 'g');

  SELECT id INTO v_customer_id FROM public.customers
  WHERE garage_id = p_garage_id AND RIGHT(REGEXP_REPLACE(telephone, '[^0-9]', '', 'g'), 8) = RIGHT(v_clean_phone, 8) LIMIT 1;

  IF v_customer_id IS NULL THEN
    INSERT INTO public.customers (garage_id, nom, telephone) VALUES (p_garage_id, p_nom, p_telephone) RETURNING id INTO v_customer_id;
  END IF;

  SELECT id INTO v_vehicle_id FROM public.vehicles
  WHERE garage_id = p_garage_id AND UPPER(REGEXP_REPLACE(immatriculation, '[^a-zA-Z0-9]', '', 'g')) = UPPER(REGEXP_REPLACE(p_immatriculation, '[^a-zA-Z0-9]', '', 'g')) LIMIT 1;

  IF v_vehicle_id IS NULL THEN
    INSERT INTO public.vehicles (garage_id, customer_id, immatriculation, marque, modele)
    VALUES (p_garage_id, v_customer_id, UPPER(p_immatriculation), p_marque, p_modele) RETURNING id INTO v_vehicle_id;
  END IF;

  v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 8));

  INSERT INTO public.appointments (garage_id, customer_id, vehicle_id, date_heure, motif, status, token_suivi)
  VALUES (p_garage_id, v_customer_id, v_vehicle_id, p_date_heure, p_motif, 'en_attente', v_token)
  RETURNING id INTO v_appointment_id;

  RETURN QUERY SELECT v_appointment_id, v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_appointment_online(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO anon, authenticated;
