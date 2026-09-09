-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0002 : FONCTIONS, TRIGGERS & CALCULS
-- ============================================================================

-- 1. IDENTIFICATION DU GARAGE EN COURS (HELPER RLS)
CREATE OR REPLACE FUNCTION public.current_garage_id(p_garage_id UUID DEFAULT NULL)
RETURNS UUID 
LANGUAGE plpgsql 
STABLE 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_garage_id UUID;
BEGIN
  IF p_garage_id IS NOT NULL THEN
    SELECT garage_id INTO v_garage_id
    FROM public.garage_users
    WHERE user_id = auth.uid() AND garage_id = p_garage_id AND actif = true;
    RETURN v_garage_id;
  END IF;

  SELECT garage_id INTO v_garage_id
  FROM public.garage_users
  WHERE user_id = auth.uid() AND actif = true
  LIMIT 1;

  RETURN v_garage_id;
END;
$$;

-- 2. GESTION AUTOMATIQUE ET SÉCURISÉE DU STOCK DE PIÈCES
CREATE OR REPLACE FUNCTION public.trg_update_stock_on_parts_usage()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_stock_actuel INT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT quantite_stock INTO v_stock_actuel FROM public.parts WHERE id = NEW.part_id;
    IF v_stock_actuel < NEW.quantite THEN
      RAISE EXCEPTION 'Stock insuffisant pour la pièce (ID: %). Stock disponible: %, Réclamé: %', NEW.part_id, v_stock_actuel, NEW.quantite;
    END IF;

    UPDATE public.parts SET quantite_stock = quantite_stock - NEW.quantite WHERE id = NEW.part_id;
    INSERT INTO public.parts_stock_audit(part_id, work_order_id, delta, type_mouvement)
    VALUES (NEW.part_id, NEW.work_order_id, -NEW.quantite, 'UTILISATION_OR');

  ELSIF TG_OP = 'UPDATE' THEN
    UPDATE public.parts SET quantite_stock = quantite_stock + OLD.quantite - NEW.quantite WHERE id = NEW.part_id;
    INSERT INTO public.parts_stock_audit(part_id, work_order_id, delta, type_mouvement)
    VALUES (NEW.part_id, NEW.work_order_id, OLD.quantite - NEW.quantite, 'AJUSTEMENT_OR');

  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.parts SET quantite_stock = quantite_stock + OLD.quantite WHERE id = OLD.part_id;
    INSERT INTO public.parts_stock_audit(part_id, work_order_id, delta, type_mouvement)
    VALUES (OLD.part_id, OLD.work_order_id, OLD.quantite, 'ANNULATION_OR');
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_manage_parts_stock ON public.work_order_parts;
CREATE TRIGGER trg_manage_parts_stock
  AFTER INSERT OR UPDATE OR DELETE ON public.work_order_parts
  FOR EACH ROW EXECUTE FUNCTION public.trg_update_stock_on_parts_usage();

-- 3. RECALCUL AUTOMATIQUE DE LA FACTURE ET DES TOTAUX OR
CREATE OR REPLACE FUNCTION public.recalculate_invoice_totals(p_invoice_id UUID)
RETURNS VOID 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_total_ht NUMERIC(12,2) := 0;
  v_taux_tva NUMERIC(5,2) := 18.00;
  v_tva_applicable BOOLEAN := true;
  v_total_tva NUMERIC(12,2) := 0;
  v_total_ttc NUMERIC(12,2) := 0;
  v_montant_paye NUMERIC(12,2) := 0;
  v_garage_id UUID;
  v_work_order_id UUID;
BEGIN
  SELECT garage_id, work_order_id, montant_paye INTO v_garage_id, v_work_order_id, v_montant_paye
  FROM public.invoices WHERE id = p_invoice_id;

  SELECT g.tva_applicable, g.taux_tva INTO v_tva_applicable, v_taux_tva FROM public.garages g WHERE g.id = v_garage_id;

  IF v_work_order_id IS NOT NULL THEN
    SELECT COALESCE(SUM(total_ht), 0) INTO v_total_ht FROM public.work_order_parts WHERE work_order_id = v_work_order_id;
  END IF;

  IF v_tva_applicable THEN
    v_total_tva := ROUND(v_total_ht * (v_taux_tva / 100.0), 2);
  ELSE
    v_total_tva := 0;
  END IF;

  v_total_ttc := v_total_ht + v_total_tva;

  UPDATE public.invoices
  SET total_ht = v_total_ht,
      total_tva = v_total_tva,
      total_ttc = v_total_ttc,
      solde_du = GREATEST(0, v_total_ttc - v_montant_paye)
  WHERE id = p_invoice_id;
END;
$$;
