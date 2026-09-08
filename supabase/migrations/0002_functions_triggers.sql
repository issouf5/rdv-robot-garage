create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
create trigger trg_garages_updated before update on public.garages for each row execute function public.set_updated_at();
create trigger trg_customers_updated before update on public.customers for each row execute function public.set_updated_at();
create trigger trg_vehicles_updated before update on public.vehicles for each row execute function public.set_updated_at();
create trigger trg_mechanics_updated before update on public.mechanics for each row execute function public.set_updated_at();
create trigger trg_appointments_updated before update on public.appointments for each row execute function public.set_updated_at();
create trigger trg_wo_updated before update on public.work_orders for each row execute function public.set_updated_at();
create trigger trg_suppliers_updated before update on public.suppliers for each row execute function public.set_updated_at();
create trigger trg_parts_updated before update on public.parts for each row execute function public.set_updated_at();
create trigger trg_po_updated before update on public.purchase_orders for each row execute function public.set_updated_at();
create trigger trg_quotes_updated before update on public.quotes for each row execute function public.set_updated_at();
create trigger trg_invoices_updated before update on public.invoices for each row execute function public.set_updated_at();

create or replace function public.current_garage_id(p_context_garage uuid default null) returns uuid language sql stable security definer set search_path = public as $$ select coalesce(p_context_garage, (select garage_id from garage_users where user_id = auth.uid() and actif = true limit 1)); $$;
create or replace function public.current_user_role() returns public.user_role language sql stable security definer set search_path = public as $$ select role from garage_users where user_id = auth.uid() and actif = true limit 1; $$;
create or replace function public.has_role(roles public.user_role[]) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from garage_users where user_id = auth.uid() and actif = true and role = any(roles)); $$;
create or replace function public.current_mechanic_id() returns uuid language sql stable security definer set search_path = public as $$ select mecanicien_id from garage_users where user_id = auth.uid() and actif = true limit 1; $$;
create or replace function public.current_user_label() returns text language sql stable security definer set search_path = public as $$ select coalesce(nom_affiche, 'Utilisateur') from garage_users where user_id = auth.uid() and actif = true limit 1; $$;

create or replace function public.next_doc_number(p_garage uuid, p_kind text) returns text language plpgsql security definer set search_path = public as $$
declare v_prefix text; v_pad int; v_year int := extract(year from now())::int; v_n int;
begin
  if p_garage is distinct from public.current_garage_id() then raise exception 'Garage invalide'; end if;
  v_prefix := case p_kind when 'or' then 'OR' when 'dev' then 'DEV' when 'fact' then 'FACT' when 'rec' then 'REC' when 'cmd' then 'CMD' when 'efact' then 'EFACT' end;
  if v_prefix is null then raise exception 'Type inconnu: %', p_kind; end if;
  v_pad := case when p_kind in ('or','efact') then 6 else 4 end;
  insert into document_counters (garage_id, kind, annee, compteur) values (p_garage, p_kind, v_year, 1)
  on conflict (garage_id, kind, annee) do update set compteur = document_counters.compteur + 1 returning compteur into v_n;
  return format('%s-%s-%s', v_prefix, v_year, lpad(v_n::text, v_pad, '0'));
end $$;

create or replace function public.appointment_no_overlap() returns trigger language plpgsql as $$
begin
  if new.statut = 'annule' then return new; end if;
  if exists (select 1 from appointments a where a.garage_id = new.garage_id and a.id is distinct from new.id and a.statut <> 'annule'
    and tstzrange(a.starts_at, a.ends_at) && tstzrange(new.starts_at, new.ends_at)
    and ((new.mechanic_id is not null and a.mechanic_id = new.mechanic_id) or a.vehicle_id = new.vehicle_id))
  then raise exception 'Double réservation impossible'; end if;
  return new;
end $$;
create trigger trg_appointment_overlap before insert or update on public.appointments for each row execute function public.appointment_no_overlap();

create or replace function public.work_orders_before() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.numero is null then new.numero := public.next_doc_number(new.garage_id, 'or'); end if;
  if new.statut = 'livre' and old.statut is distinct from 'livre' then
    if not (new.qc_essai and new.qc_niveaux and new.qc_voyants and new.qc_serrage and new.qc_nettoyage) then raise exception 'Livraison bloquée: QC incomplet'; end if;
  end if;
  if new.statut = 'termine' and old.statut is distinct from 'termine' and new.date_sortie_reelle is null then new.date_sortie_reelle := current_date; end if;
  return new;
end $$;
create trigger trg_wo_before before insert or update on public.work_orders for each row execute function public.work_orders_before();

create or replace function public.work_orders_history() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then insert into work_order_history (garage_id, work_order_id, label) values (new.garage_id, new.id, 'OR créé (' || new.numero || ')');
  elsif new.statut is distinct from old.statut then insert into work_order_history (garage_id, work_order_id, label) values (new.garage_id, new.id, 'Statut → ' || new.statut::text);
  end if;
  return new;
end $$;
create trigger trg_wo_history after insert or update on public.work_orders for each row execute function public.work_orders_history();

create or replace function public.quotes_before() returns trigger language plpgsql security definer set search_path = public as $$ begin if new.numero is null then new.numero := public.next_doc_number(new.garage_id, 'dev'); end if; return new; end $$;
create trigger trg_quotes_before before insert on public.quotes for each row execute function public.quotes_before();
create or replace function public.invoices_before() returns trigger language plpgsql security definer set search_path = public as $$ begin if new.numero is null then new.numero := public.next_doc_number(new.garage_id, 'fact'); end if; return new; end $$;
create trigger trg_invoices_before before insert on public.invoices for each row execute function public.invoices_before();
create or replace function public.po_before() returns trigger language plpgsql security definer set search_path = public as $$ begin if new.numero is null then new.numero := public.next_doc_number(new.garage_id, 'cmd'); end if; return new; end $$;
create trigger trg_po_before before insert on public.purchase_orders for each row execute function public.po_before();

create or replace function public.recalc_quote_totals() returns trigger language plpgsql security definer set search_path = public as $$
declare v_quote_id uuid := coalesce(new.quote_id, old.quote_id); v_garage uuid; v_st bigint; v_remise bigint; v_ht bigint; v_tva bigint;
begin
  select garage_id into v_garage from quotes where id = v_quote_id;
  select coalesce(sum(total_ligne),0) into v_st from quote_lines where quote_id = v_quote_id;
  select remise into v_remise from quotes where id = v_quote_id;
  v_ht := greatest(0, v_st - v_remise);
  select case when g.tax_enabled then round(v_ht * g.tax_rate / 100)::bigint else 0 end into v_tva from garages g where g.id = v_garage;
  update quotes set sous_total = v_st, tva = v_tva, total = v_ht + v_tva where id = v_quote_id;
  return null;
end $$;
create trigger trg_quote_lines_calc after insert or update or delete on public.quote_lines for each row execute function public.recalc_quote_totals();

create or replace function public.recalc_invoice_totals() returns trigger language plpgsql security definer set search_path = public as $$
declare v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id); v_garage uuid; v_st bigint; v_remise bigint; v_ht bigint; v_tva bigint;
begin
  select garage_id into v_garage from invoices where id = v_invoice_id;
  select coalesce(sum(total_ligne),0) into v_st from invoice_lines where invoice_id = v_invoice_id;
  select remise into v_remise from invoices where id = v_invoice_id;
  v_ht := greatest(0, v_st - v_remise);
  select case when g.tax_enabled then round(v_ht * g.tax_rate / 100)::bigint else 0 end into v_tva from garages g where g.id = v_garage;
  update invoices set sous_total = v_st, tva = v_tva, total = v_ht + v_tva where id = v_invoice_id;
  return null;
end $$;
create trigger trg_invoice_lines_calc after insert or update or delete on public.invoice_lines for each row execute function public.recalc_invoice_totals();

create or replace function public.refresh_invoice_status(p_invoice uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_total bigint; v_paye bigint; v_echeance date; v_statut public.invoice_status; v_current public.invoice_status;
begin
  select total, montant_paye, echeance, statut into v_total, v_paye, v_echeance, v_current from invoices where id = p_invoice for update;
  if not found then return; end if;
  select coalesce(sum(montant),0) into v_paye from payments where invoice_id = p_invoice;
  if v_current in ('brouillon','annulee') then update invoices set montant_paye = v_paye where id = p_invoice; return; end if;
  v_statut := case when v_total > 0 and v_paye >= v_total then 'payee'::public.invoice_status when v_paye > 0 then 'partielle'::public.invoice_status when v_echeance is not null and v_echeance < current_date then 'retard'::public.invoice_status else 'emise'::public.invoice_status end;
  update invoices set montant_paye = v_paye, statut = v_statut where id = p_invoice;
end $$;

create or replace function public.audit_write(p_garage uuid, p_action text, p_detail text) returns void language plpgsql security definer set search_path = public as $$ begin insert into audit_log (garage_id, user_id, user_label, action, detail) values (p_garage, auth.uid(), public.current_user_label(), p_action, p_detail); end $$;

create or replace function public.payments_after() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.refresh_invoice_status(coalesce(new.invoice_id, old.invoice_id));
  if tg_op = 'INSERT' then perform public.audit_write(new.garage_id, 'Paiement enregistré', new.numero || ' · ' || new.montant || ' FCFA');
  return null;
end $$;
create trigger trg_payments_after after insert or update or delete on public.payments for each row execute function public.payments_after();

create or replace function public.invoices_after() returns trigger language plpgsql security definer set search_path = public as $$
begin if tg_op = 'INSERT' then perform public.refresh_invoice_status(new.id); perform public.audit_write(new.garage_id, 'Création facture', new.numero); return null; end if;
end $$;
create trigger trg_invoices_after after insert or update on public.invoices for each row execute function public.invoices_after();

create or replace function public.quotes_after() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.statut is distinct from old.statut then perform public.audit_write(new.garage_id, 'Devis ' || new.statut::text, new.numero); end if; return new; end $$;
create trigger trg_quotes_after after update on public.quotes for each row execute function public.quotes_after();

create or replace function public.parts_stock_audit() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.stock is distinct from old.stock then insert into stock_movements (garage_id, part_id, type, qte, raison, user_label) values (new.garage_id, new.id, 'ajustement', abs(new.stock - old.stock), 'Ajustement direct', public.current_user_label()); end if; return new; end $$;
create trigger trg_parts_stock_audit before update on public.parts for each row execute function public.parts_stock_audit();
