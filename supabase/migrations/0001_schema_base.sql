-- TYPES
create type public.user_role as enum ('proprietaire','gerant','reception','mecanicien');
create type public.appointment_status as enum ('attente','confirme','termine','annule');
create type public.wo_status as enum ('nouveau','diagnostic','validation','pieces','reparation','controle','termine','livre');
create type public.wo_priority as enum ('normale','urgente','critique');
create type public.quote_status as enum ('brouillon','envoye','attente','accepte','refuse','expire','converti','annule');
create type public.invoice_status as enum ('brouillon','emise','partielle','payee','retard','annulee');
create type public.payment_method as enum ('especes','orange_money','moov_money','virement','carte','autre');
create type public.stock_movement_type as enum ('entree','sortie','ajustement');
create type public.po_status as enum ('brouillon','commandee','partielle','livree','annulee');
create type public.reminder_type as enum ('rdv_j1','rdv_j2','entretien','devis_relance','vehicule_pret','paiement_relance');
create type public.reminder_canal as enum ('sms','whatsapp','les_deux');
create type public.reminder_statut as enum ('programme','envoye','echec','annule');

-- TABLES PRINCIPALES
create table public.garages (
  id uuid primary key default gen_random_uuid(), nom text not null, telephone text, whatsapp text, adresse text,
  devise text not null default 'FCFA', tax_enabled boolean not null default true, tax_rate numeric(5,2) not null default 18,
  slug text unique, booking_enabled boolean not null default true, nif text, rccm text, centre_fiscal text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.garage_users (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, role public.user_role not null default 'reception',
  nom_affiche text, telephone text, mecanicien_id uuid, actif boolean not null default true,
  created_at timestamptz not null default now(), unique (garage_id, user_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade,
  nom text not null, telephone text, email text, adresse text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade, marque text not null, modele text not null, annee int, couleur text,
  immatriculation text, kilometrage int not null default 0, prochaine_revision date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.mechanics (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade,
  nom text not null, telephone text, specialite text, experience int default 0, actif boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.garage_users add constraint garage_users_mecanicien_fk foreign key (mecanicien_id) references public.mechanics(id) on delete set null;

create table public.appointments (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade,
  customer_id uuid not null references public.customers(id), vehicle_id uuid not null references public.vehicles(id), mechanic_id uuid references public.mechanics(id),
  service text not null, notes text, starts_at timestamptz not null, ends_at timestamptz not null, statut public.appointment_status not null default 'attente',
  work_order_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint appt_time_valid check (ends_at > starts_at)
);

create table public.work_orders (
  id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, numero text,
  appointment_id uuid references public.appointments(id), customer_id uuid not null references public.customers(id), vehicle_id uuid not null references public.vehicles(id),
  mechanic_id uuid references public.mechanics(id), intervention text not null, travaux text, symptomes text, cause_identifiee text, controles jsonb not null default '{}',
  temps_estime_h numeric(6,2) not null default 0, photos text[] not null default '{}', est_main_oeuvre bigint not null default 0, est_pieces bigint not null default 0,
  date_entree date not null default current_date, date_sortie_prevue date, date_sortie_reelle date, statut public.wo_status not null default 'nouveau',
  priorite public.wo_priority not null default 'normale', observations text, heure_debut time, heure_pause time, heure_reprise time, heure_fin time,
  qc_essai boolean not null default false, qc_niveaux boolean not null default false, qc_voyants boolean not null default false, qc_serrage boolean not null default false, qc_nettoyage boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (garage_id, numero)
);

create table public.work_order_parts (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, work_order_id uuid not null references public.work_orders(id) on delete cascade, nom text not null, reference text, part_id uuid, qte int not null default 1, prix_unitaire bigint not null default 0);
create table public.work_order_history (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, work_order_id uuid not null references public.work_orders(id) on delete cascade, label text not null, created_at timestamptz not null default now());

create table public.suppliers (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, nom text not null, telephone text, specialite text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.parts (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, nom text not null, reference text not null, categorie text, marque text, prix_achat bigint not null default 0, prix_vente bigint not null default 0, stock int not null default 0, seuil_min int not null default 0, emplacement text, supplier_id uuid references public.suppliers(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (garage_id, reference), constraint parts_stock_positif check (stock >= 0));
alter table public.work_order_parts add constraint wo_parts_part_fk foreign key (part_id) references public.parts(id) on delete set null;

create table public.stock_movements (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, part_id uuid not null references public.parts(id) on delete cascade, type public.stock_movement_type not null, qte int not null check (qte > 0), raison text, user_label text, created_at timestamptz not null default now());
create table public.purchase_orders (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, numero text, supplier_id uuid references public.suppliers(id), date_commande date not null default current_date, livraison_prevue date, statut public.po_status not null default 'brouillon', notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (garage_id, numero));
create table public.purchase_order_lines (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, po_id uuid not null references public.purchase_orders(id) on delete cascade, part_id uuid not null references public.parts(id), qte_commandee int not null check (qte_commandee > 0), qte_recue int not null default 0, prix_achat bigint not null default 0, constraint po_line_recu check (qte_recue <= qte_commandee));

create table public.quotes (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, numero text, customer_id uuid not null references public.customers(id), vehicle_id uuid references public.vehicles(id), work_order_id uuid references public.work_orders(id), date_emission date not null default current_date, date_expiration date, description text, conditions text, remise bigint not null default 0, statut public.quote_status not null default 'brouillon', public_token text unique default encode(gen_random_bytes(16),'hex'), token_expires_at timestamptz, sous_total bigint not null default 0, tva bigint not null default 0, total bigint not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (garage_id, numero));
create table public.quote_lines (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, quote_id uuid not null references public.quotes(id) on delete cascade, type text not null check (type in ('main_oeuvre','piece','service','autre')), designation text not null, reference text, part_id uuid references public.parts(id) on delete set null, qte numeric(10,2) not null check (qte > 0), prix_unitaire bigint not null check (prix_unitaire >= 0), total_ligne bigint generated always as (round(qte * prix_unitaire)::bigint) stored);

create table public.invoices (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, numero text, customer_id uuid not null references public.customers(id), vehicle_id uuid references public.vehicles(id), work_order_id uuid references public.work_orders(id), quote_id uuid references public.quotes(id), date_emission date not null default current_date, echeance date, remise bigint not null default 0, notes text, statut public.invoice_status not null default 'emise', sous_total bigint not null default 0, tva bigint not null default 0, total bigint not null default 0, montant_paye bigint not null default 0, einvoice_numero text, einvoice_emise_at timestamptz, einvoice_hash text, einvoice_payload jsonb, einvoice_statut text check (einvoice_statut in ('generee','transmise','validee','rejetee')), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (garage_id, numero));
create table public.invoice_lines (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, invoice_id uuid not null references public.invoices(id) on delete cascade, type text not null check (type in ('main_oeuvre','piece','service','autre')), designation text not null, reference text, part_id uuid references public.parts(id) on delete set null, qte numeric(10,2) not null check (qte > 0), prix_unitaire bigint not null check (prix_unitaire >= 0), total_ligne bigint generated always as (round(qte * prix_unitaire)::bigint) stored);

create table public.payments (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, numero text, invoice_id uuid not null references public.invoices(id), customer_id uuid not null references public.customers(id), montant bigint not null check (montant > 0), methode public.payment_method not null, reference text, notes text, encaisse_par uuid references auth.users(id), user_label text, paid_at date not null default current_date, created_at timestamptz not null default now(), unique (garage_id, numero));

create table public.document_counters (garage_id uuid not null references public.garages(id) on delete cascade, kind text not null check (kind in ('or','dev','fact','rec','cmd','efact')), annee int not null, compteur int not null default 0, primary key (garage_id, kind, annee));
create table public.audit_log (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, user_id uuid, user_label text, action text not null, detail text, created_at timestamptz not null default now());

create table public.reminder_templates (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, type public.reminder_type not null, modele text not null, actif boolean not null default true, updated_at timestamptz not null default now(), unique (garage_id, type));
create table public.reminders (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, type public.reminder_type not null, canal public.reminder_canal not null default 'sms', customer_id uuid not null references public.customers(id), vehicle_id uuid references public.vehicles(id), appointment_id uuid references public.appointments(id), work_order_id uuid references public.work_orders(id), quote_id uuid references public.quotes(id), invoice_id uuid references public.invoices(id), telephone text not null, message text not null, statut public.reminder_statut not null default 'programme', scheduled_at timestamptz not null default now(), sent_at timestamptz, provider text, provider_ref text, erreur text, created_at timestamptz not null default now());

create table public.bonus_rules (id uuid primary key default gen_random_uuid(), garage_id uuid not null unique references public.garages(id) on delete cascade, taux_main_oeuvre numeric(5,2) not null default 10, prime_qualite bigint not null default 5000, actif boolean not null default true, updated_at timestamptz not null default now());

create table public.notification_queue (id uuid primary key default gen_random_uuid(), garage_id uuid not null references public.garages(id) on delete cascade, customer_id uuid not null references public.customers(id), type text not null check (type in ('efacture_generee','rdv_confirme','rappel')), payload jsonb not null, canal text not null default 'sms', statut text not null default 'pending' check (statut in ('pending','sent','failed')), created_at timestamptz not null default now(), sent_at timestamptz, erreur text);

-- INDEX
create index idx_garage_users_garage on public.garage_users (garage_id);
create index idx_customers_garage on public.customers (garage_id);
create index idx_vehicles_garage on public.vehicles (garage_id, customer_id);
create index idx_appointments_garage on public.appointments (garage_id, starts_at);
create index idx_wo_garage on public.work_orders (garage_id, statut);
create index idx_parts_garage on public.parts (garage_id);
create index idx_invoices_garage on public.invoices (garage_id, statut);
create index idx_reminders_garage on public.reminders (garage_id, statut, scheduled_at);
create index idx_notif_queue_pending on public.notification_queue (statut, created_at) where statut = 'pending';
