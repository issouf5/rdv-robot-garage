-- ============================================================================
-- RDV ROBOT GARAGE V2 - MODULE 0001 : SCHÉMA RELATIONNEL & TYPES ENUM
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- TYPES ENUM
CREATE TYPE public.user_role AS ENUM ('super_admin', 'admin_garage', 'receptionniste', 'mecanicien');
CREATE TYPE public.appointment_status AS ENUM ('en_attente', 'confirme', 'annule', 'termine');
CREATE TYPE public.work_order_status AS ENUM ('recu', 'en_diagnostic', 'en_cours', 'en_attente_pieces', 'termine', 'livre');
CREATE TYPE public.invoice_status AS ENUM ('brouillon', 'validee', 'payee', 'partiellement_payee', 'annulee');
CREATE TYPE public.notification_channel AS ENUM ('sms', 'whatsapp', 'email');
CREATE TYPE public.notification_status AS ENUM ('en_attente', 'envoye', 'echoue');

-- TABLE GARAGES (Multi-Tenant Core)
CREATE TABLE public.garages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nom TEXT NOT NULL,
    adresse TEXT,
    telephone TEXT,
    email TEXT,
    ifu TEXT,
    rccm TEXT,
    prefixe_facture TEXT DEFAULT 'FAC',
    prefixe_or TEXT DEFAULT 'OR',
    prefixe_devis TEXT DEFAULT 'DEV',
    tva_applicable BOOLEAN DEFAULT true,
    taux_tva NUMERIC(5,2) DEFAULT 18.00,
    devise TEXT DEFAULT 'XOF',
    actif BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE GARAGE USERS
CREATE TABLE public.garage_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    nom TEXT NOT NULL,
    prenom TEXT,
    telephone TEXT,
    role public.user_role NOT NULL DEFAULT 'mecanicien',
    actif BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_garage_user UNIQUE (garage_id, user_id)
);

-- TABLE CLIENTS
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    nom TEXT NOT NULL,
    prenom TEXT,
    telephone TEXT NOT NULL,
    email TEXT,
    adresse TEXT,
    ifu TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE VÉHICULES
CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    immatriculation TEXT NOT NULL,
    marque TEXT NOT NULL,
    modele TEXT NOT NULL,
    annee INT,
    chassis_vin TEXT,
    kilometrage INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_garage_vehicle UNIQUE (garage_id, immatriculation)
);

-- TABLE RENDEZ-VOUS
CREATE TABLE public.appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
    date_heure TIMESTAMPTZ NOT NULL,
    motif TEXT NOT NULL,
    status public.appointment_status DEFAULT 'en_attente',
    token_suivi TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE ORDRES DE RÉPARATION (OR)
CREATE TABLE public.work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id),
    vehicle_id UUID NOT NULL REFERENCES public.vehicles(id),
    mecanicien_id UUID REFERENCES public.garage_users(id),
    number TEXT NOT NULL,
    symptomes TEXT,
    diagnostic TEXT,
    travaux_effectues TEXT,
    kilometrage_entree INT,
    status public.work_order_status DEFAULT 'recu',
    total_ht NUMERIC(12,2) DEFAULT 0,
    total_tva NUMERIC(12,2) DEFAULT 0,
    total_ttc NUMERIC(12,2) DEFAULT 0,
    date_entree TIMESTAMPTZ DEFAULT NOW(),
    date_sortie_prevue TIMESTAMPTZ,
    date_sortie_reelle TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_garage_wo_number UNIQUE (garage_id, number)
);

-- TABLE PIÈCES DE RECHANGE (STOCK)
CREATE TABLE public.parts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    reference TEXT NOT NULL,
    designation TEXT NOT NULL,
    prix_achat NUMERIC(12,2) DEFAULT 0,
    prix_vente NUMERIC(12,2) DEFAULT 0,
    quantite_stock INT DEFAULT 0,
    seuil_alerte INT DEFAULT 5,
    emplacement TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_garage_part_ref UNIQUE (garage_id, reference)
);

-- TABLE LIGNES DE PIÈCES PAR OR
CREATE TABLE public.work_order_parts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID NOT NULL REFERENCES public.work_orders(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES public.parts(id),
    quantite INT NOT NULL CHECK (quantite > 0),
    prix_unitaire_ht NUMERIC(12,2) NOT NULL,
    total_ht NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE HISTORIQUE D'AUDIT DU STOCK
CREATE TABLE public.parts_stock_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    part_id UUID NOT NULL REFERENCES public.parts(id) ON DELETE CASCADE,
    work_order_id UUID REFERENCES public.work_orders(id) ON DELETE SET NULL,
    delta INT NOT NULL,
    type_mouvement TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TABLE FACTURES
CREATE TABLE public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    work_order_id UUID UNIQUE REFERENCES public.work_orders(id) ON DELETE SET NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id),
    number TEXT NOT NULL,
    status public.invoice_status DEFAULT 'brouillon',
    total_ht NUMERIC(12,2) DEFAULT 0,
    total_tva NUMERIC(12,2) DEFAULT 0,
    total_ttc NUMERIC(12,2) DEFAULT 0,
    montant_paye NUMERIC(12,2) DEFAULT 0,
    solde_du NUMERIC(12,2) DEFAULT 0,
    einvoice_numero TEXT,
    einvoice_hash TEXT,
    einvoice_qr_code TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_garage_invoice_num UNIQUE (garage_id, number)
);

-- TABLE FILE D'ATTENTE DES NOTIFICATIONS
CREATE TABLE public.notifications_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    garage_id UUID NOT NULL REFERENCES public.garages(id) ON DELETE CASCADE,
    canal public.notification_channel NOT NULL,
    destinataire TEXT NOT NULL,
    message TEXT NOT NULL,
    status public.notification_status DEFAULT 'en_attente',
    tentatives INT DEFAULT 0,
    erreur_log TEXT,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDEX MULTI-TENANT POUR HAUTES PERFORMANCES
CREATE INDEX idx_garage_users_lookup ON public.garage_users(garage_id, user_id);
CREATE INDEX idx_customers_garage ON public.customers(garage_id);
CREATE INDEX idx_vehicles_garage ON public.vehicles(garage_id);
CREATE INDEX idx_appointments_garage ON public.appointments(garage_id, date_heure);
CREATE INDEX idx_work_orders_garage ON public.work_orders(garage_id, status);
CREATE INDEX idx_parts_garage ON public.parts(garage_id, quantite_stock);
CREATE INDEX idx_invoices_garage ON public.invoices(garage_id, status);
CREATE INDEX idx_notifications_status ON public.notifications_queue(status, created_at);
