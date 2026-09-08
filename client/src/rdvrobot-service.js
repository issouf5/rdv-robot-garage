import { createClient } from '@supabase/supabase-js';

export const METHODES_UI_DB = { 'Espèces': 'especes', 'Orange Money': 'orange_money', 'Moov Money': 'moov_money', 'Virement bancaire': 'virement', 'Carte bancaire': 'carte', 'Autre': 'autre' };
export const WO_STATUTS_UI = { nouveau: 'Nouveau', diagnostic: 'Diagnostic', validation: 'Attente validation', pieces: 'Pièces à commander', reparation: 'En réparation', controle: 'Contrôle qualité', termine: 'Terminé', livre: 'Livré' };

export function createRdvRobotClient({ url, anonKey }) {
  const supabase = createClient(url, anonKey);
  let garageId = null;
  const gq = () => { if (!garageId) throw new Error('Garage non résolu'); return garageId; };

  return {
    supabase, get garageId() { return garageId; }, setGarage(id) { garageId = id; },
    async signIn({ email, password }) { const { data, error } = await supabase.auth.signInWithPassword({ email, password }); if (error) throw error; return data; },
    async resolveGarage() { const { data, error } = await supabase.from('garage_users').select('role, garages(*)').eq('actif', true).limit(1); if (error) throw error; if (data?.length) { garageId = data[0].garages.id; return { garage: data[0].garages, role: data[0].role }; } return null; },
    
    appointments: { list: async ({from, to}) => { let q = supabase.from('appointments').select('*, customers(nom), vehicles(modele)').eq('garage_id', gq()).order('starts_at'); if(from) q = q.gte('starts_at', from); if(to) q = q.lte('starts_at', to); const {data, error} = await q; if(error) throw error; return data; }, create: async (a) => { const {data, error} = await supabase.from('appointments').insert({...a, garage_id: gq()}).select(); if(error) throw error; return data[0]; } },
    workOrders: { list: async () => { const {data, error} = await supabase.from('work_orders').select('*, customers(nom), vehicles(modele)').eq('garage_id', gq()).order('created_at', {ascending:false}); if(error) throw error; return data; }, changeStatut: async (id, statut) => { const {error} = await supabase.from('work_orders').update({statut}).eq('id', id); if(error) throw error; } },
    invoices: { list: async () => { const {data, error} = await supabase.from('invoices').select('*, customers(nom)').eq('garage_id', gq()).order('created_at', {ascending:false}); if(error) throw error; return data; } },
    generateEInvoice: async (invoiceId) => { const {data, error} = await supabase.rpc('generate_einvoice', {p_invoice: invoiceId}); if(error) throw error; return data; },
    verifyEInvoice: async (numero) => { const {data, error} = await supabase.rpc('verify_einvoice', {p_numero: numero}); if(error) throw error; return data; },
    ownerDashboard: async () => { const {data, error} = await supabase.rpc('owner_dashboard_summary'); if(error) throw error; return data?.[0]; },
    getMyGarages: async () => { const {data, error} = await supabase.rpc('get_my_garages'); if(error) throw error; return data; }
  };
      }
