-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0007 : CONFORMITÉ E-FACTURE & SÉCURITÉ FISCALE
-- ============================================================================

CREATE OR REPLACE FUNCTION public.generate_einvoice_hash(
    p_invoice_number TEXT,
    p_ifu TEXT,
    p_created_at TIMESTAMPTZ,
    p_total_ttc NUMERIC,
    p_montant_paye NUMERIC
) 
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_raw_payload TEXT;
BEGIN
  v_raw_payload := COALESCE(p_invoice_number, '') || '|' ||
                   COALESCE(p_ifu, 'SANS_IFU') || '|' ||
                   TO_CHAR(p_created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || '|' ||
                   COALESCE(p_total_ttc::TEXT, '0') || '|' ||
                   COALESCE(p_montant_paye::TEXT, '0');

  RETURN ENCODE(extensions.digest(v_raw_payload::BYTEA, 'sha256'), 'hex');
END;
$$;
