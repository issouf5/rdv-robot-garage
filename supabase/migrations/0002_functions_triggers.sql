-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0002 : FONCTIONS, TRIGGERS & CALCULS
-- ============================================================================

-- 1. HELPER SÉCURISÉ MULTI-TENANT (CURRENT GARAGE ID)
CREATE OR REPLACE FUNCTION public.current_garage_id(p_context_garage UUID DEFAULT NULL) 
RETURNS UUID 
LANGUAGE sql 
STABLE 
SECURITY DEFINER 
SET search_path = public 
AS $$
  SELECT garage_id 
  FROM public.garage_users 
  WHERE user_id = auth.uid() 
    AND actif = true 
    AND (p_context_garage IS NULL OR garage_id = p_context_garage)
  LIMIT 1;
$$;

-- 2. DÉCLENCHEUR TIMESTAMPTZ (UPDATED_AT AUTOMATIQUE)
CREATE OR REPLACE FUNCTION public.trg_set_updated_at()
RETURNS TRIGGER 
LANGUAGE plpgsql 
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Application du trigger updated_at sur toutes les tables principales
DROP TRIGGER IF EXISTS trg_garages_updated_at ON public.garages;
CREATE TRIGGER trg_garages_updated_at BEFORE UPDATE ON public.garages FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_garage_users_updated_at ON public.garage_users;
CREATE TRIGGER trg_garage_users_updated_at BEFORE UPDATE ON public.garage_users FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_customers_updated_at ON public.customers;
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_vehicles_updated_at ON public.vehicles;
CREATE TRIGGER trg_vehicles_updated_at BEFORE UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_parts_updated_at ON public.parts;
CREATE TRIGGER trg_parts_updated_at BEFORE UPDATE ON public.parts FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_appointments_updated_at ON public.appointments;
CREATE TRIGGER trg_appointments_updated_at BEFORE UPDATE ON public.appointments FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_work_orders_updated_at ON public.work_orders;
CREATE TRIGGER trg_work_orders_updated_at BEFORE UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_quotes_updated_at ON public.quotes;
CREATE TRIGGER trg_quotes_updated_at BEFORE UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

DROP TRIGGER IF EXISTS trg_invoices_updated_at ON public.invoices;
CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_set_updated_at();

-- 3. GENERATION AUTOMATIQUE DE NUMÉROS SÉQUENTIELS DE DOCUMENTS
CREATE OR REPLACE FUNCTION public.next_doc_number(
    p_garage_id UUID, 
    p_type TEXT
) 
RETURNS TEXT 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_prefix TEXT;
  v_year TEXT;
  v_count INTEGER;
  v_next_num TEXT;
BEGIN
  v_year := TO_CHAR(NOW(), 'YY');

  -- Récupérer le préfixe configuré pour le garage
  IF p_type = 'OR' THEN
    SELECT COALESCE(prefixe_or, 'OR') INTO v_prefix FROM public.garages WHERE id = p_garage_id;
    SELECT COUNT(*) + 1 INTO v_count FROM public.work_orders WHERE garage_id = p_garage_id AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM NOW());
  ELSIF p_type = 'DEV' THEN
    SELECT COALESCE(prefixe_devis, 'DEV') INTO v_prefix FROM public.garages WHERE id = p_garage_id;
    SELECT COUNT(*) + 1 INTO v_count FROM public.quotes WHERE garage_id = p_garage_id AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM NOW());
  ELSIF p_type = 'FAC' THEN
    SELECT COALESCE(prefixe_facture, 'FAC') INTO v_prefix FROM public.garages WHERE id = p_garage_id;
    SELECT COUNT(*) + 1 INTO v_count FROM public.invoices WHERE garage_id = p_garage_id AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM NOW());
  ELSE
    RAISE EXCEPTION 'Type de document invalide: %', p_type;
  END IF;

  v_next_num := v_prefix || '-' || v_year || '-' || LPAD(v_count::TEXT, 5, '0');
  RETURN v_next_num;
END;
$$;

-- 4. TRIGGERS D'ATTRIBUTION AUTOMATIQUE DES NUMÉROS DE DOCUMENTS
CREATE OR REPLACE FUNCTION public.trg_assign_doc_number()
RETURNS TRIGGER 
LANGUAGE plpgsql 
AS $$
BEGIN
  IF NEW.number IS NULL OR NEW.number = '' THEN
    IF TG_TABLE_NAME = 'work_orders' THEN
      NEW.number := public.next_doc_number(NEW.garage_id, 'OR');
    ELSIF TG_TABLE_NAME = 'quotes' THEN
      NEW.number := public.next_doc_number(NEW.garage_id, 'DEV');
    ELSIF TG_TABLE_NAME = 'invoices' THEN
      NEW.number := public.next_doc_number(NEW.garage_id, 'FAC');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_wo_assign_num ON public.work_orders;
CREATE TRIGGER trg_wo_assign_num BEFORE INSERT ON public.work_orders FOR EACH ROW EXECUTE FUNCTION public.trg_assign_doc_number();

DROP TRIGGER IF EXISTS trg_quote_assign_num ON public.quotes;
CREATE TRIGGER trg_quote_assign_num BEFORE INSERT ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.trg_assign_doc_number();

DROP TRIGGER IF EXISTS trg_invoice_assign_num ON public.invoices;
CREATE TRIGGER trg_invoice_assign_num BEFORE INSERT ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_assign_doc_number();

-- 5. CALCULS DES MONTANTS SUR LES DEVIS ET FACTURES
CREATE OR REPLACE FUNCTION public.trg_recalculate_quote_totals()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_quote_id UUID;
  v_garage_id UUID;
  v_tva_applicable BOOLEAN;
  v_taux_tva NUMERIC(5,2);
  v_total_ht NUMERIC(12,2) := 0;
  v_total_tva NUMERIC(12,2) := 0;
  v_total_ttc NUMERIC(12,2) := 0;
BEGIN
  v_quote_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.quote_id ELSE NEW.quote_id END;

  SELECT q.garage_id, g.tva_applicable, g.taux_tva 
  INTO v_garage_id, v_tva_applicable, v_taux_tva
  FROM public.quotes q
  JOIN public.garages g ON g.id = q.garage_id
  WHERE q.id = v_quote_id;

  SELECT COALESCE(SUM(montant_ht), 0) INTO v_total_ht 
  FROM public.quote_lines 
  WHERE quote_id = v_quote_id;

  IF v_tva_applicable THEN
    v_total_tva := ROUND(v_total_ht * (v_taux_tva / 100.0), 2);
  END IF;
  
  v_total_ttc := v_total_ht + v_total_tva;

  UPDATE public.quotes 
  SET total_ht = v_total_ht,
      total_tva = v_total_tva,
      total_ttc = v_total_ttc
  WHERE id = v_quote_id;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_quote_lines_calc ON public.quote_lines;
CREATE TRIGGER trg_quote_lines_calc AFTER INSERT OR UPDATE OR DELETE ON public.quote_lines FOR EACH ROW EXECUTE FUNCTION public.trg_recalculate_quote_totals();

CREATE OR REPLACE FUNCTION public.trg_recalculate_invoice_totals()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_invoice_id UUID;
  v_garage_id UUID;
  v_tva_applicable BOOLEAN;
  v_taux_tva NUMERIC(5,2);
  v_total_ht NUMERIC(12,2) := 0;
  v_total_tva NUMERIC(12,2) := 0;
  v_total_ttc NUMERIC(12,2) := 0;
  v_montant_paye NUMERIC(12,2) := 0;
BEGIN
  v_invoice_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;

  SELECT i.garage_id, i.montant_paye, g.tva_applicable, g.taux_tva 
  INTO v_garage_id, v_montant_paye, v_tva_applicable, v_taux_tva
  FROM public.invoices i
  JOIN public.garages g ON g.id = i.garage_id
  WHERE i.id = v_invoice_id;

  SELECT COALESCE(SUM(montant_ht), 0) INTO v_total_ht 
  FROM public.invoice_lines 
  WHERE invoice_id = v_invoice_id;

  IF v_tva_applicable THEN
    v_total_tva := ROUND(v_total_ht * (v_taux_tva / 100.0), 2);
  END IF;
  
  v_total_ttc := v_total_ht + v_total_tva;

  UPDATE public.invoices 
  SET total_ht = v_total_ht,
      total_tva = v_total_tva,
      total_ttc = v_total_ttc,
      solde_du = v_total_ttc - COALESCE(v_montant_paye, 0)
  WHERE id = v_invoice_id;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_lines_calc ON public.invoice_lines;
CREATE TRIGGER trg_invoice_lines_calc AFTER INSERT OR UPDATE OR DELETE ON public.invoice_lines FOR EACH ROW EXECUTE FUNCTION public.trg_recalculate_invoice_totals();

-- 6. GESTION AUTOMATIQUE DES PAIEMENTS ET SOLDE DU
CREATE OR REPLACE FUNCTION public.trg_update_invoice_payments()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_invoice_id UUID;
  v_total_paye NUMERIC(12,2) := 0;
  v_total_ttc NUMERIC(12,2) := 0;
BEGIN
  v_invoice_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;

  SELECT COALESCE(SUM(montant), 0) INTO v_total_paye 
  FROM public.payments 
  WHERE invoice_id = v_invoice_id;

  SELECT total_ttc INTO v_total_ttc FROM public.invoices WHERE id = v_invoice_id;

  UPDATE public.invoices 
  SET montant_paye = v_total_paye,
      solde_du = v_total_ttc - v_total_paye,
      status = CASE 
        WHEN (v_total_ttc - v_total_paye) <= 0 THEN 'payee'::public.invoice_status
        WHEN v_total_paye > 0 THEN 'partiellement_payee'::public.invoice_status
        ELSE status
      END
  WHERE id = v_invoice_id;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_payments_calc ON public.payments;
CREATE TRIGGER trg_payments_calc AFTER INSERT OR UPDATE OR DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.trg_update_invoice_payments();

-- 7. DÉCRÉMENTATION DE STOCK LORS DE LA FACTURATION PAYÉE
CREATE OR REPLACE FUNCTION public.trg_decrement_stock_on_invoice()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
BEGIN
  IF NEW.status = 'payee' AND (OLD.status IS NULL OR OLD.status != 'payee') THEN
    INSERT INTO public.parts_stock_audit (garage_id, part_id, delta, reason, created_by)
    SELECT 
      NEW.garage_id, 
      il.part_id, 
      -il.quantite, 
      'Vente Facture: ' || NEW.number, 
      auth.uid()
    FROM public.invoice_lines il
    WHERE il.invoice_id = NEW.id AND il.part_id IS NOT NULL;

    UPDATE public.parts p
    SET quantite_stock = p.quantite_stock - il.quantite
    FROM public.invoice_lines il
    WHERE il.invoice_id = NEW.id AND il.part_id = p.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_paid_stock ON public.invoices;
CREATE TRIGGER trg_invoice_paid_stock AFTER UPDATE OF status ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_decrement_stock_on_invoice();
