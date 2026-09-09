-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0006 : PORTAIL CLIENT & RDV EN LIGNE
-- ============================================================================

-- 1. FONCTION DE PRÈS-RESERVATION / PRISE DE RDV EN LIGNE (ACCÈS PUBLIC)
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
RETURNS TABLE (
    appointment_id UUID,
    token_suivi TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID;
  v_vehicle_id UUID;
  v_appointment_id UUID;
  v_token TEXT;
  v_clean_phone TEXT;
BEGIN
  -- Nettoyage du numéro de téléphone (garder les 8 derniers chiffres minimum)
  v_clean_phone := REGEXP_REPLACE(p_telephone, '[^0-9]', '', 'g');

  -- 1. Recherche ou Création du Client
  SELECT id INTO v_customer_id
  FROM public.customers
  WHERE garage_id = p_garage_id
    AND RIGHT(REGEXP_REPLACE(telephone, '[^0-9]', '', 'g'), 8) = RIGHT(v_clean_phone, 8)
  LIMIT 1;

  IF v_customer_id IS NULL THEN
    INSERT INTO public.customers (garage_id, nom, telephone)
    VALUES (p_garage_id, p_nom, p_telephone)
    RETURNING id INTO v_customer_id;
  END IF;

  -- 2. Recherche ou Création du Véhicule
  SELECT id INTO v_vehicle_id
  FROM public.vehicles
  WHERE garage_id = p_garage_id
    AND UPPER(REGEXP_REPLACE(immatriculation, '[^a-zA-Z0-9]', '', 'g')) = UPPER(REGEXP_REPLACE(p_immatriculation, '[^a-zA-Z0-9]', '', 'g'))
  LIMIT 1;

  IF v_vehicle_id IS NULL THEN
    INSERT INTO public.vehicles (garage_id, customer_id, immatriculation, marque, modele)
    VALUES (p_garage_id, v_customer_id, UPPER(p_immatriculation), p_marque, p_modele)
    RETURNING id INTO v_vehicle_id;
  END IF;

  -- 3. Génération du Jeton de Suivi
  v_token := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 8));

  -- 4. Création du Rendez-vous
  INSERT INTO public.appointments (
    garage_id,
    customer_id,
    vehicle_id,
    date_heure,
    motif,
    status,
    token_suivi
  ) VALUES (
    p_garage_id,
    v_customer_id,
    v_vehicle_id,
    p_date_heure,
    p_motif,
    'en_attente',
    v_token
  )
  RETURNING id INTO v_appointment_id;

  RETURN QUERY SELECT v_appointment_id, v_token;
END;
$$;

-- Autoriser les visiteurs anonymes et clients enregistrés à réserver
GRANT EXECUTE ON FUNCTION public.book_appointment_online(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT) TO anon, authenticated;

-- 2. CONSULTATION DU SUIVI DE VÉHICULE PAR LE CLIENT (PAR JETON DE SUIVI)
CREATE OR REPLACE FUNCTION public.get_vehicle_status_by_token(
    p_token TEXT
)
RETURNS TABLE (
    garage_nom TEXT,
    garage_telephone TEXT,
    client_nom TEXT,
    immatriculation TEXT,
    marque TEXT,
    modele TEXT,
    date_rdv TIMESTAMPTZ,
    status_rdv public.appointment_status,
    statut_or public.work_order_status,
    symptomes TEXT,
    travaux_effectues TEXT,
    date_sortie_prevue TIMESTAMPTZ,
    total_ttc NUMERIC,
    solde_du NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    g.nom AS garage_nom,
    g.telephone AS garage_telephone,
    c.nom AS client_nom,
    v.immatriculation,
    v.marque,
    v.modele,
    a.date_heure AS date_rdv,
    a.status AS status_rdv,
    wo.status AS statut_or,
    wo.symptomes,
    wo.travaux_effectues,
    wo.date_sortie_prevue,
    COALESCE(i.total_ttc, wo.total_ttc, 0) AS total_ttc,
    COALESCE(i.solde_du, wo.total_ttc, 0) AS solde_du
  FROM public.appointments a
  JOIN public.garages g ON g.id = a.garage_id
  LEFT JOIN public.customers c ON c.id = a.customer_id
  LEFT JOIN public.vehicles v ON v.id = a.vehicle_id
  LEFT JOIN public.work_orders wo ON wo.appointment_id = a.id
  LEFT JOIN public.invoices i ON i.work_order_id = wo.id
  WHERE a.token_suivi = UPPER(p_token);
END;
$$;

-- Autoriser la consultation publique de l'état du véhicule via le jeton
GRANT EXECUTE ON FUNCTION public.get_vehicle_status_by_token(TEXT) TO anon, authenticated;

-- 3. RECHERCHE RAPIDE HISTORIQUE CLIENT VIA TÉLÉPHONE
CREATE OR REPLACE FUNCTION public.get_customer_history_by_phone(
    p_garage_id UUID,
    p_telephone TEXT
)
RETURNS TABLE (
    vehicle_id UUID,
    immatriculation TEXT,
    marque TEXT,
    modele TEXT,
    dernier_passage TIMESTAMPTZ,
    total_interventions INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean_phone TEXT;
BEGIN
  v_clean_phone := REGEXP_REPLACE(p_telephone, '[^0-9]', '', 'g');

  RETURN QUERY
  SELECT 
    v.id AS vehicle_id,
    v.immatriculation,
    v.marque,
    v.modele,
    MAX(wo.created_at) AS dernier_passage,
    COUNT(wo.id)::INT AS total_interventions
  FROM public.vehicles v
  JOIN public.customers c ON c.id = v.customer_id
  LEFT JOIN public.work_orders wo ON wo.vehicle_id = v.id
  WHERE v.garage_id = p_garage_id
    AND RIGHT(REGEXP_REPLACE(c.telephone, '[^0-9]', '', 'g'), 8) = RIGHT(v_clean_phone, 8)
  GROUP BY v.id, v.immatriculation, v.marque, v.modele;
END;
$$;
