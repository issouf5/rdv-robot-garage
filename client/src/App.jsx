import React, { useState, useEffect } from 'react';
import { createRdvRobotClient } from './rdvrobot-service';
import { LayoutDashboard, Wrench, FileText, Users, LogOut, Loader2 } from 'lucide-react';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://votre-projet.supabase.co';
const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'votre-cle-anon';

export default function App() {
  const [api, setApi] = useState(null);
  const [user, setUser] = useState(null);
  const [garage, setGarage] = useState(null);
  const [page, setPage] = useState('login');
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState(null);

  useEffect(() => {
    const client = createRdvRobotClient({ url: SUPABASE_URL, anonKey: SUPABASE_KEY });
    setApi(client);
    checkSession(client);
  }, []);

  const checkSession = async (client) => {
    const { data: { session } } = await client.supabase.auth.getSession();
    if (session) {
      try {
        const info = await client.resolveGarage();
        if (info) {
          setUser(session.user);
          setGarage(info.garage);
          setPage('dashboard');
          loadDashboardData(client);
        } else {
          setPage('setup');
        }
      } catch (e) { console.error(e); }
    }
  };

  const loadDashboardData = async (client) => {
    setLoading(true);
    try {
      if (user.email.includes('proprietaire')) {
        const summary = await client.ownerDashboard();
        const garages = await client.getMyGarages();
        setData({ summary, garages });
      } else {
        const wos = await client.workOrders.list();
        const invs = await client.invoices.list();
        setData({ wos, invs });
      }
    } catch (e) { alert("Erreur chargement: " + e.message); }
    setLoading(false);
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    const email = e.target.email.value;
    const password = e.target.password.value;
    try {
      await api.signIn({ email, password });
      checkSession(api);
    } catch (err) { alert(err.message); }
  };

  if (!api) return <div>Chargement...</div>;

  if (page === 'login') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-100">
        <form onSubmit={handleLogin} className="bg-white p-8 rounded-xl shadow-lg w-96 space-y-4">
          <h2 className="text-2xl font-bold text-center">RDV Robot Garage</h2>
          <input name="email" placeholder="Email" className="w-full border p-2 rounded" defaultValue="proprietaire@demo.bf" />
          <input name="password" type="password" placeholder="Mot de passe" className="w-full border p-2 rounded" defaultValue="demo1234" />
          <button type="submit" className="w-full bg-orange-500 text-white p-2 rounded font-bold hover:bg-orange-600">Se connecter</button>
        </form>
      </div>
    );
  }

  if (loading) return <div className="flex items-center justify-center h-screen"><Loader2 className="animate-spin" /></div>;

  return (
    <div className="min-h-screen bg-slate-50">
      <header className="bg-slate-900 text-white p-4 flex justify-between items-center">
        <div className="font-bold text-xl">{garage?.nom}</div>
        <button onClick={() => { api.supabase.auth.signOut(); window.location.reload(); }} className="flex items-center gap-2 text-sm bg-slate-800 px-3 py-1 rounded"><LogOut size={16}/> Déconnexion</button>
      </header>
      
      <main className="p-6 max-w-6xl mx-auto">
        {user.email.includes('proprietaire') && data?.summary ? (
          <div className="space-y-6">
            <h2 className="text-2xl font-bold">Vue Globale Propriétaire</h2>
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div className="bg-white p-4 rounded-xl shadow border-l-4 border-blue-500">
                <div className="text-sm text-gray-500">Garages</div>
                <div className="text-2xl font-bold">{data.summary.total_garages}</div>
              </div>
              <div className="bg-white p-4 rounded-xl shadow border-l-4 border-green-500">
                <div className="text-sm text-gray-500">CA Mois</div>
                <div className="text-2xl font-bold">{(data.summary.ca_total_mois / 1000000).toFixed(2)}M FCFA</div>
              </div>
            </div>
            <div className="bg-white p-4 rounded-xl shadow">
              <h3 className="font-bold mb-4">Mes Établissements</h3>
              {data.garages.map(g => (
                <div key={g.id} className="flex justify-between items-center py-2 border-b last:border-0">
                  <span className="font-medium">{g.nom}</span>
                  <span className="text-sm text-gray-500">{g.or_en_cours} OR en cours</span>
                  <span className="font-bold text-green-600">{(g.ca_mois/1000).toFixed(0)}k FCFA</span>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="space-y-6">
             <h2 className="text-2xl font-bold">Tableau de Bord Atelier</h2>
             <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
               <div className="bg-white p-4 rounded-xl shadow">
                 <h3 className="font-bold mb-2 flex items-center gap-2"><Wrench size={18}/> Ordres de Réparation</h3>
                 {data?.wos?.slice(0,5).map(w => (
                   <div key={w.id} className="py-2 border-b text-sm flex justify-between">
                     <span>{w.numero} - {w.customers?.nom}</span>
                     <span className={`px-2 rounded text-xs ${w.statut==='livre'?'bg-green-100 text-green-800':'bg-yellow-100 text-yellow-800'}`}>{w.statut}</span>
                   </div>
                 ))}
               </div>
               <div className="bg-white p-4 rounded-xl shadow">
                 <h3 className="font-bold mb-2 flex items-center gap-2"><FileText size={18}/> Factures Récentes</h3>
                 {data?.invs?.slice(0,5).map(i => (
                   <div key={i.id} className="py-2 border-b text-sm flex justify-between">
                     <span>{i.numero}</span>
                     <span className="font-bold">{i.total.toLocaleString()} FCFA</span>
                   </div>
                 ))}
               </div>
             </div>
          </div>
        )}
      </main>
    </div>
  );
                                         }
