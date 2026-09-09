-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0008 : MIGRATION & DONNÉES INITIALES (SEED)
-- ============================================================================

DO $$
DECLARE
  v_garage_id UUID;
  v_user_admin_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.garages WHERE nom = 'Garage Pilot DGIA') THEN
    INSERT INTO public.garages (nom, adresse, telephone, email, ifu, rccm, prefixe_facture, prefixe_or, prefixe_devis, tva_applicable, taux_tva, devise, actif)
    VALUES ('Garage Pilot DGIA', 'Secteur 2, Yako, Burkina Faso', '+22657182048', 'contact@dgia-pulse.com', '30012345A', 'BF-OUA-2026-B-1234', 'FAC', 'OR', 'DEV', true, 18.00, 'XOF', true)
    RETURNING id INTO v_garage_id;
  ELSE
    SELECT id INTO v_garage_id FROM public.garages WHERE nom = 'Garage Pilot DGIA' LIMIT 1;
  END IF;

  INSERT INTO public.garage_users (garage_id, user_id, nom, prenom, telephone, role, actif)
  VALUES (v_garage_id, v_user_admin_id, 'Sermé', 'Issouf', '+22657182048', 'admin_garage', true)
  ON CONFLICT (garage_id, user_id) DO NOTHING;
END $$;
