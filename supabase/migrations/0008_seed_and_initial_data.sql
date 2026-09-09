-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0008 : MIGRATION & DONNÉES INITIALES (SEED)
-- ============================================================================

DO $$
DECLARE
  v_garage_id UUID;
  v_user_admin_id UUID := '00000000-0000-0000-0000-000000000001';
  v_user_meca_id UUID  := '00000000-0000-0000-0000-000000000002';
  v_customer_id UUID;
  v_vehicle_id UUID;
BEGIN

  -- 1. INITIALISATION DU GARAGE DE DÉMONSTRATION
  IF NOT EXISTS (SELECT 1 FROM public.garages WHERE nom = 'Garage Pilot DGIA') THEN
    INSERT INTO public.garages (
      nom,
      adresse,
      telephone,
      email,
      ifu,
      rccm,
      prefixe_facture,
      prefixe_or,
      prefixe_devis,
      tva_applicable,
      taux_tva,
      devise,
      actif
    ) VALUES (
      'Garage Pilot DGIA',
      'Secteur 2, Yako, Burkina Faso',
      '+22657182048',
      'contact@dgia-pulse.com',
      '30012345A',
      'BF-OUA-2026-B-1234',
      'FAC',
      'OR',
      'DEV',
      true,
      18.00,
      'XOF',
      true
    ) RETURNING id INTO v_garage_id;
  ELSE
    SELECT id INTO v_garage_id FROM public.garages WHERE nom = 'Garage Pilot DGIA' LIMIT 1;
  END IF;

  -- 2. DÉFINITION DES MEMBRES ET RÔLES DU GARAGE
  INSERT INTO public.garage_users (garage_id, user_id, nom, prenom, telephone, role, actif)
  VALUES 
    (v_garage_id, v_user_admin_id, 'Sermé', 'Issouf', '+22657182048', 'admin_garage', true),
    (v_garage_id, v_user_meca_id, 'Sawadogo', 'Moussa', '+22670000000', 'mecanicien', true)
  ON CONFLICT (garage_id, user_id) DO NOTHING;

  -- 3. INJECTION DU CATALOGUE DE PIÈCES INITIAL (EXEMPLES)
  INSERT INTO public.parts (garage_id, reference, designation, prix_achat, prix_vente, quantite_stock, seuil_alerte, emplacement)
  VALUES 
    (v_garage_id, 'FIL-HUIL-01', 'Filtre à Huile Universel', 2500, 4500, 15, 5, 'Rayon A1'),
    (v_garage_id, 'FIL-AIR-02', 'Filtre à Air Berline', 3500, 6000, 3, 5, 'Rayon A2'),
    (v_garage_id, 'HUILE-10W40', 'Huile Moteur 10W40 (Bidon 5L)', 12000, 18500, 8, 4, 'Rayon B1'),
    (v_garage_id, 'PLA-FREIN-01', 'Jeu de Plaquettes de Frein Avant', 8000, 14000, 2, 4, 'Rayon C3')
  ON CONFLICT (garage_id, reference) DO NOTHING;

  -- 4. CRÉATION D'UN CLIENT ET D'UN VÉHICULE TÉMOINS
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE garage_id = v_garage_id AND telephone = '+22676001122') THEN
    INSERT INTO public.customers (garage_id, nom, prenom, telephone, adresse)
    VALUES (v_garage_id, 'Ouédraogo', 'Kader', '+22676001122', 'Yako Center')
    RETURNING id INTO v_customer_id;

    INSERT INTO public.vehicles (garage_id, customer_id, immatriculation, marque, modele, annee, kilometrage)
    VALUES (v_garage_id, v_customer_id, '11-JJ-4500', 'Toyota', 'Corolla', 2018, 125000)
    RETURNING id INTO v_vehicle_id;
  END IF;

END $$;
