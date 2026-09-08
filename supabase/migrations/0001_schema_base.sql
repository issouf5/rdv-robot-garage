-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0001 : SCHEMA, EXTENSIONS & TABLES
-- ============================================================================

-- 1. EXTENSIONS REQUISES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;

-- 2. TYPES ENUM
DO $$ BEGIN
  CREATE TYPE public.user_role AS ENUM ('super_admin', 'admin_garage', 'receptionniste', 'mecanicien', 'comptable');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.appointment_status AS ENUM ('en_attente', 'confirme', 'annule', 'termine', 'en_retard');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.work_order_status AS ENUM ('recu', 'en_diagnostic', 'en_cours', 'en_attente_pieces', 'termine', 'livre');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.quote_status AS ENUM ('brouillon', 'envoye', 'accepte', 'refuse', 'expire');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.invoice_status AS ENUM ('brouillon', 'validee', 'payee', 'partiellement_payee', 'annulee');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.payment_method AS ENUM ('especes', 'orange_money', 'moov_money', 'carte_bancaire', 'cheque', 'virement');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('sms', 'whatsapp', 'email');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('en_attente', 'envoye', 'echoue');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. TABLES PRINCIPALES

-- GARAGES
CREATE TABLE IF NOT EXISTS public.garages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nom TEXT NOT NULL,
    adresse TEXT,
    telephone TEXT NOT NULL,
    email TEXT,
    ifu TEXT, -- Identifiant Fiscal Unique (Burkina Faso)
    rccm TEXT,
    prefixe_facture TEXT DEFAULT 'FAC',
    prefixe_or TEXT DEFAULT 'OR',
    prefixe_devis TEXT DEFAULT 'DEV',
    tva_applicable BOOLEAN DEFAULT true,
    taux_tva NUMERIC(5,2) DEFAULT 18.00,
    devise TEXT DEFAULT 'XOF',
    logo_url TEXT,
    actif BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- UTILISATEURS DU GARAGE (MEMBRES)
CREATE TABLE IF NOT EXISTS public.garage_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL, -- ID Auth Supabase
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    telephone TEXT,
    role public.user_role NOT NULL DEFAULT 'receptionniste',
    actif BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(garage_id, user_id)
);

-- CLIENTS
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    nom TEXT NOT NULL,
    prenom TEXT,
    telephone TEXT NOT NULL,
    telephone_secondaire TEXT,
    email TEXT,
    adresse TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- VÉHICULES
CREATE TABLE IF NOT EXISTS public.vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    immatriculation TEXT NOT NULL,
    marque TEXT NOT NULL,
    modele TEXT NOT NULL,
    annee INTEGER,
    chassis_vin TEXT,
    carburant TEXT,
    kilometrage INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- PIÈCES / STOCK
CREATE TABLE IF NOT EXISTS public.parts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    prix_achat NUMERIC(12,2) DEFAULT 0,
    prix_vente NUMERIC(12,2) DEFAULT 0,
    quantite_stock INTEGER DEFAULT 0,
    seuil_alerte INTEGER DEFAULT 5,
    emplacement TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(garage_id, reference)
);

-- RENDEZ-VOUS (RDV)
CREATE TABLE IF NOT EXISTS public.appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    date_heure TIMESTAMPTZ NOT NULL,
    motif TEXT NOT NULL,
    status public.appointment_status DEFAULT 'en_attente',
    notes TEXT,
    token_suivi TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ORDRES DE RÉPARATION (OR)
CREATE TABLE IF NOT EXISTS public.work_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    number TEXT NOT NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    mecanicien_id UUID REFERENCES public.garage_users(id) ON DELETE SET NULL,
    status public.work_order_status DEFAULT 'recu',
    kilometrage_entree INTEGER,
    symptomes TEXT,
    diagnostic TEXT,
    travaux_effectues TEXT,
    date_entree TIMESTAMPTZ DEFAULT NOW(),
    date_sortie_prevue TIMESTAMPTZ,
    date_sortie_reelle TIMESTAMPTZ,
    total_ht NUMERIC(12,2) DEFAULT 0,
    total_tva NUMERIC(12,2) DEFAULT 0,
    total_ttc NUMERIC(12,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(garage_id, number)
);

-- DEVIS (QUOTES)
CREATE TABLE IF NOT EXISTS public.quotes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    number TEXT NOT NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    work_order_id UUID REFERENCES public.work_orders(id) ON DELETE SET NULL,
    status public.quote_status DEFAULT 'brouillon',
    date_expiration DATE,
    total_ht NUMERIC(12,2) DEFAULT 0,
    total_tva NUMERIC(12,2) DEFAULT 0,
    total_ttc NUMERIC(12,2) DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(garage_id, number)
);

-- FACTURES (INVOICES)
CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    number TEXT NOT NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    work_order_id UUID REFERENCES public.work_orders(id) ON DELETE SET NULL,
    quote_id UUID REFERENCES public.quotes(id) ON DELETE SET NULL,
    status public.invoice_status DEFAULT 'brouillon',
    total_ht NUMERIC(12,2) DEFAULT 0,
    total_tva NUMERIC(12,2) DEFAULT 0,
    total_ttc NUMERIC(12,2) DEFAULT 0,
    montant_paye NUMERIC(12,2) DEFAULT 0,
    solde_du NUMERIC(12,2) DEFAULT 0,
    -- Champs E-Facture
    einvoice_numero TEXT,
    einvoice_qr_code TEXT,
    einvoice_hash TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(garage_id, number)
);

-- 4. TABLES DE DÉTAILS / LIGNES

-- LIGNES DE DEVIS
CREATE TABLE IF NOT EXISTS public.quote_lines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quote_id UUID NOT NULL REFERENCES public.quotes(id) ON DELETE CASCADE,
    part_id UUID REFERENCES public.parts(id) ON DELETE SET NULL,
    designation TEXT NOT NULL,
    quantite NUMERIC(10,2) NOT NULL DEFAULT 1,
    prix_unitaire_ht NUMERIC(12,2) NOT NULL DEFAULT 0,
    montant_ht NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- LIGNES DE FACTURES
CREATE TABLE IF NOT EXISTS public.invoice_lines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    part_id UUID REFERENCES public.parts(id) ON DELETE SET NULL,
    designation TEXT NOT NULL,
    quantite NUMERIC(10,2) NOT NULL DEFAULT 1,
    prix_unitaire_ht NUMERIC(12,2) NOT NULL DEFAULT 0,
    montant_ht NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PIÈCES D'UN ORDRE DE RÉPARATION
CREATE TABLE IF NOT EXISTS public.work_order_parts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    work_order_id UUID NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
    part_id UUID REFERENCES public.parts(id) ON DELETE RESTRICT,
    quantite NUMERIC(10,2) NOT NULL DEFAULT 1,
    prix_unitaire_ht NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- PAIEMENTS
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    montant NUMERIC(12,2) NOT NULL,
    methode public.payment_method NOT NULL DEFAULT 'especes',
    reference_transaction TEXT,
    date_paiement TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- AUDIT DU STOCK
CREATE TABLE IF NOT EXISTS public.parts_stock_audit (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES public.parts(id) ON DELETE CASCADE,
    delta INTEGER NOT NULL,
    reason TEXT,
    created_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- QUEUE DE NOTIFICATIONS
CREATE TABLE IF NOT EXISTS public.notifications_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    canal public.notification_channel NOT NULL,
    destinataire TEXT NOT NULL,
    message TEXT NOT NULL,
    status public.notification_status DEFAULT 'en_attente',
    tentatives INTEGER DEFAULT 0,
    erreur_log TEXT,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. INDEXATION OPTIMISÉE POUR LE MULTI-TENANT ET LA RECHERCHE
CREATE INDEX IF NOT EXISTS idx_customers_garage_phone ON public.customers (garage_id, telephone);
CREATE INDEX IF NOT EXISTS idx_vehicles_garage_immat ON public.vehicles (garage_id, immatriculation);
CREATE INDEX IF NOT EXISTS idx_work_orders_garage_status ON public.work_orders (garage_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_garage_status ON public.invoices (garage_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_einvoice_num ON public.invoices (einvoice_numero) WHERE einvoice_numero IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notifications_pending ON public.notifications_queue (status, created_at) WHERE status = 'en_attente';
