-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0007 : CONFORMITÉ E-FACTURE & SÉCURITÉ FISCALE
-- ============================================================================

-- 1. FONCTION DE GÉNÉRATION DE HASH SHA-256 POUR FISCALISATION
CREATE OR REPLACE FUNCTION public.generate_einvoice_hash(
    p_invoice_number TEXT,
    p_ifu TEXT,
    p_created_at TIMESTAMPTZ,
    p_total_ttc NUMERIC,
    p_montant_paye NUMERIC
) 
RETURNS TEXT 
LANGUAGE plpgsql 
IMMUTABLE 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_raw_payload TEXT;
  v_hash TEXT;
BEGIN
  -- Assemblage de la chaîne d'empreinte fiscale
  v_raw_payload := COALESCE(p_invoice_number, '') || '|' ||
                   COALESCE(p_ifu, 'SANS_IFU') || '|' ||
                   TO_CHAR(p_created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '|' ||
                   COALESCE(p_total_ttc::TEXT, '0') || '|' ||
                   COALESCE(p_montant_paye::TEXT, '0');

  -- Calcul du Hash SHA-256 avec pgcrypto
  v_hash := ENCODE(extensions.digest(v_raw_payload::BYTEA, 'sha256'), 'hex');
  
  RETURN v_hash;
END;
$$;

-- 2. FONCTION DE CERTIFICATION ET CERTIFICAT E-FACTURE
CREATE OR REPLACE FUNCTION public.certify_invoice_efacture(
    p_invoice_id UUID
) 
RETURNS TABLE (
    einvoice_numero TEXT,
    einvoice_hash TEXT,
    einvoice_qr_code TEXT
) 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$
DECLARE
  v_invoice RECORD;
  v_garage RECORD;
  v_einvoice_num TEXT;
  v_hash TEXT;
  v_qr_code TEXT;
BEGIN
  -- Récupération de la facture
  SELECT * INTO v_invoice FROM public.invoices WHERE id = p_invoice_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture introuvable (ID: %)', p_invoice_id;
  END IF;

  -- Récupération du garage associé
  SELECT * INTO v_garage FROM public.garages WHERE id = v_invoice.garage_id;

  -- Génération du numéro E-Facture unique s'il n'existe pas encore
  IF v_invoice.einvoice_numero IS NULL OR v_invoice.einvoice_numero = '' THEN
    v_einvoice_num := 'EF-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || SUBSTRING(v_invoice.id::TEXT FROM 1 FOR 8);
  ELSE
    v_einvoice_num := v_invoice.einvoice_numero;
  END IF;

  -- Génération du Hash Fiscale
  v_hash := public.generate_einvoice_hash(
    v_invoice.number,
    v_garage.ifu,
    v_invoice.created_at,
    v_invoice.total_ttc,
    v_invoice.montant_paye
  );

  -- URL pour le QR Code de vérification
  v_qr_code := 'https://verify.dgia-pulse.com/efacture?num=' || v_einvoice_num || '&hash=' || v_hash;

  -- Mise à jour de la facture
  UPDATE public.invoices
  SET einvoice_numero = v_einvoice_num,
      einvoice_hash = v_hash,
      einvoice_qr_code = v_qr_code,
      status = 'validee'
  WHERE id = p_invoice_id;

  RETURN QUERY SELECT v_einvoice_num, v_hash, v_qr_code;
END;
$$;

-- 3. DÉCLENCHEUR D'INVIOLABILITÉ DES FACTURES CERTIFIÉES
CREATE OR REPLACE FUNCTION public.trg_prevent_invoice_tampering()
RETURNS TRIGGER 
LANGUAGE plpgsql 
AS $$
BEGIN
  -- Empêcher la modification de données clés si la facture est déjà validée/certifiée
  IF OLD.status IN ('validee', 'payee') THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Impossible de supprimer une facture certifiée/validée !';
    END IF;

    IF (OLD.total_ht != NEW.total_ht OR OLD.total_ttc != NEW.total_ttc OR OLD.einvoice_hash != NEW.einvoice_hash) THEN
      RAISE EXCEPTION 'Modifications des montants interdites sur une facture certifiée/validée !';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_tamper_guard ON public.invoices;
CREATE TRIGGER trg_invoice_tamper_guard 
  BEFORE UPDATE OR DELETE ON public.invoices 
  FOR EACH ROW 
  EXECUTE FUNCTION public.trg_prevent_invoice_tampering();
