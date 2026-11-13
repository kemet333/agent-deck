'use client';
// Agent Bar · Tablero de agentes (v2, 13/11/2026, Diego: «mucho más parecida y gamificada a la web que te pasé», symvibe.com).
// A crew of agents on one board: an infinite dotted canvas with zoom, team frames, agents with a character name and an
// avatar in their CLI's colour, a live counter, the command bar at the bottom («@ para dirigir» with quick actions), the
// mission map (orchestrator → teams → agents, filters, detail), a 12-slot composer with roles and loops with templates.
// Real terminals underneath (BoardEngine.swift in Agent Bar; /api/tablero in Diego OS).
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {Terminal} from '@xterm/xterm';
import {FitAddon} from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import {ArrowRightLeft,Crosshair,Layers,LayoutGrid,Maximize2,Minus,MousePointer2,Pause,Play,Plus,Repeat,Rocket,Search,Send,Square,Users,X,Zap} from 'lucide-react';
import './board.css';

type Estado='trabajando'|'te_necesita'|'en_reposo'|'pausada'|'terminada'|'dormida';
type Consola={id:string;nombre:string;cli:string;cliNombre:string;comando?:string;rol:string;equipo:string;cwd:string;x:number;y:number;w:number;h:number;estado:Estado;salida:number|null;inicio:number;turnos:number};
type Bucle={id:string;consola:string;mensaje:string;disparo:'inactividad'|'cada';segundos:number;objetivo:string;max:number;vueltas:number;activo:boolean;motivo:string};
type Propuesta={de:string;deNombre:string;a:string;texto:string};
type Vista={consolas:Consola[];bucles:Bucle[];cuenta:Record<Estado,number>;propuestas:Propuesta[];max:number;ahora:number;turnos:number};

const NOMBRE:Record<Estado,string>={trabajando:'Trabajando',te_necesita:'Te necesita',en_reposo:'En reposo',pausada:'En pausa',terminada:'Terminada',dormida:'Dormida'};
const ORDEN:Estado[]=['te_necesita','trabajando','en_reposo','pausada','terminada','dormida'];
const CLI:Record<string,{nombre:string;color:string;letra:string}>={claude:{nombre:'Claude Code',color:'#e8673a',letra:'✳'},codex:{nombre:'Codex',color:'#5b8cff',letra:'◎'},gemini:{nombre:'Gemini',color:'#b48cff',letra:'✦'},shell:{nombre:'Terminal',color:'#8f8a84',letra:'›_'},custom:{nombre:'Comando',color:'#8f8a84',letra:'⌘'}};
const ROLES=['General','Frontend','Backend','Tests','Revisor','Diseño','Docs','Seguridad'];
const PLANTILLAS:[string,string,'inactividad'|'cada',number,string][]=[
 ['Revisión de avance','Dime en tres líneas qué has hecho, qué falta y si algo te bloquea.','cada',900,''],
 ['Que no se pare','Sigue con lo siguiente del plan.','inactividad',60,''],
 ['Rescate del build','El build falla: arréglalo y vuelve a compilar.','inactividad',90,'npm run build'],
 ['Vigilar tests','Ejecuta los tests y arregla lo que falle.','inactividad',90,'npm test'],
 ['Punto de guardado','Haz commit de lo que funcione con un mensaje claro.','cada',1800,''],
 ['Barrido de revisión','Revisa el diff de la última hora y apunta riesgos.','cada',3600,''],
];

// two transports: Agent Bar's native engine (message handler with replies) or /api/tablero over HTTP (Diego OS)
const nativo=()=>(window as any).webkit?.messageHandlers?.board;
async function api(path:string,body?:unknown):Promise<any>{
 const n=nativo();
 if(n){try{return await n.postMessage({path,body:body??{}});}catch(e:any){throw Error(String(e?.message||e||'No ha funcionado.'));}}
 const r=await fetch('/api/tablero'+path,body===undefined?{credentials:'same-origin'}:{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 const j:any=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||'No ha funcionado.');return j;
}
const base=(p:string)=>p.split('/').filter(Boolean).pop()||'~';
const tiempo=(s:number)=>{if(!s||s<0)return '';const m=Math.floor(s/60),h=Math.floor(m/60);return h?`${h} h ${m%60} min`:m?`${m} min`:`${Math.floor(s)} s`;};
/** one live stream for the whole board; each card registers for its console's bytes */
const hub=(()=>{
 const buf=new Map<string,Uint8Array[]>(),subs=new Map<string,{write:(u:Uint8Array)=>void;reset:()=>void}>();
 let es:EventSource|null=null,usuarios=0;
 const bytes=(b64:string)=>{const bin=atob(b64),u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return u;};
 const entregar=(id:string,u:Uint8Array)=>{const s=subs.get(id);if(s)s.write(u);else{const l=buf.get(id)||[];l.push(u);while(l.length>400)l.shift();buf.set(id,l);}};
 return {
  abrir(){if(usuarios++||es)return;
   if(nativo()){(window as any).__boardEvents=(lote:[string,string][])=>{for(const [ev,data] of lote){if(ev==='nueva'){subs.get(data)?.reset();buf.delete(data);}else if(ev==='o'){const i=data.indexOf(' ');entregar(data.slice(0,i),bytes(data.slice(i+1)));}}};
    buf.clear();for(const s of subs.values())s.reset();void api('/flujo',{});return;}
   es=new EventSource('/api/tablero/flujo');
   es.addEventListener('hola',()=>{buf.clear();for(const s of subs.values())s.reset();});
   es.addEventListener('nueva',(e:MessageEvent)=>{subs.get(e.data)?.reset();buf.delete(e.data);});
   es.addEventListener('o',(e:MessageEvent)=>{const i=e.data.indexOf(' ');entregar(e.data.slice(0,i),bytes(e.data.slice(i+1)));});},
  cerrar(){if(--usuarios<=0){usuarios=0;es?.close();es=null;buf.clear();}},
  registrar(id:string,s:{write:(u:Uint8Array)=>void;reset:()=>void}){subs.set(id,s);for(const u of buf.get(id)||[])s.write(u);buf.delete(id);return ()=>{if(subs.get(id)===s)subs.delete(id);};},
 };
})();

function Avatar({c,size=26}:{c:{nombre:string;cli:string;estado?:Estado};size?:number}){
 const k=CLI[c.cli]||CLI.custom;
 return <span className={`ab-avatar is-${c.estado||'en_reposo'}`} style={{width:size,height:size,['--cli' as any]:k.color}}>
  <b style={{fontSize:size*0.42}}>{c.nombre.slice(0,1)}</b><i style={{fontSize:size*0.34}}>{k.letra}</i></span>;
}

/** one agent: header (avatar, name, role, CLI, state, time, turns), the real terminal, its resize handle */
function Tarjeta({c,ahora,onMove,onAccion,foco,escala}:{c:Consola;ahora:number;onMove:(id:string,p:Partial<Consola>,guardar:boolean)=>void;onAccion:(a:string,c:Consola)=>void;foco:boolean;escala:number}){
 const caja=useRef<HTMLDivElement>(null),term=useRef<Terminal|null>(null);
 useEffect(()=>{
  if(!caja.current||c.estado==='dormida')return;
  const t=new Terminal({fontFamily:"'SF Mono', Menlo, monospace",fontSize:12.5,lineHeight:1.15,cursorBlink:true,scrollback:5000,theme:{background:'#100e0c',foreground:'#ece6df',cursor:'#e8673a',selectionBackground:'#4a3a2e'}});
  const f=new FitAddon();t.loadAddon(f);t.open(caja.current);term.current=t;try{f.fit();}catch{}
  let cola='',timer:any=null;
  const sub=t.onData(d=>{cola+=d;if(!timer)timer=setTimeout(()=>{const d64=btoa(unescape(encodeURIComponent(cola)));cola='';timer=null;void api('/teclear',{id:c.id,d:d64}).catch(()=>{});},8);});
  const quitar=hub.registrar(c.id,{write:u=>t.write(u),reset:()=>t.reset()});
  let ultimo='';
  const ro=new ResizeObserver(()=>{try{f.fit();}catch{}const k=t.cols+'x'+t.rows;if(k!==ultimo){ultimo=k;void api('/tam',{id:c.id,cols:t.cols,rows:t.rows}).catch(()=>{});}});
  ro.observe(caja.current);
  return ()=>{ro.disconnect();quitar();sub.dispose();t.dispose();term.current=null;};
 },[c.id,c.estado==='dormida']);// eslint-disable-line react-hooks/exhaustive-deps
 useEffect(()=>{if(foco)term.current?.focus();},[foco]);
 const arrastre=(modo:'mover'|'tam')=>(e:React.PointerEvent)=>{
  if((e.target as HTMLElement).closest('button'))return;
  e.preventDefault();const x0=e.clientX,y0=e.clientY,o={x:c.x,y:c.y,w:c.w,h:c.h};
  const pos=(ev:PointerEvent)=>{const dx=(ev.clientX-x0)/escala,dy=(ev.clientY-y0)/escala;return modo==='mover'?{x:Math.max(0,o.x+dx),y:Math.max(0,o.y+dy)}:{w:Math.max(380,o.w+dx),h:Math.max(240,o.h+dy)};};
  const mov=(ev:PointerEvent)=>onMove(c.id,pos(ev),false);
  const fin=(ev:PointerEvent)=>{window.removeEventListener('pointermove',mov);window.removeEventListener('pointerup',fin);onMove(c.id,pos(ev),true);};
  window.addEventListener('pointermove',mov);window.addEventListener('pointerup',fin);
 };
 const k=CLI[c.cli]||CLI.custom;
 return (
  <article className={`ab-card is-${c.estado}${foco?' is-focus':''}`} style={{left:c.x,top:c.y,width:c.w,height:c.h,['--cli' as any]:k.color}} data-id={c.id}>
   <header onPointerDown={arrastre('mover')}>
    <Avatar c={c}/>
    <div className="ab-who"><strong>{c.nombre}</strong><span>{c.rol||k.nombre} · {base(c.cwd)}</span></div>
    <span className="ab-cli" style={{color:k.color}}>{k.nombre}</span>
    <span className={`ab-state is-${c.estado}`}><i/>{NOMBRE[c.estado]}</span>
    {c.inicio>0&&c.estado!=='dormida'&&<span className="ab-time">{tiempo(ahora-c.inicio)}</span>}
    {c.turnos>0&&<span className="ab-turns" title="Turnos terminados"><Zap size={11}/>{c.turnos}</span>}
    <nav>
     {c.estado!=='dormida'&&c.estado!=='terminada'&&<button title={c.estado==='pausada'?'Reanudar':'Pausar'} onClick={()=>onAccion(c.estado==='pausada'?'reanudarPausa':'pausar',c)}>{c.estado==='pausada'?<Play size={13}/>:<Pause size={13}/>}</button>}
     <button title="Pasar lo último a otro agente" onClick={()=>onAccion('traspaso',c)}><ArrowRightLeft size={13}/></button>
     <button title="Bucle" onClick={()=>onAccion('bucle',c)}><Repeat size={13}/></button>
     <button title="Cerrar" onClick={()=>onAccion('cerrar',c)}><X size={13}/></button>
    </nav>
   </header>
   {c.estado==='dormida'
    ?<div className="ab-sleep"><Avatar c={c} size={54}/><p>{c.nombre} se quedó dormida al cerrar la app.</p><button className="ab-primary" onClick={()=>onAccion('reanudar',c)}><Play size={14}/>{c.cli==='claude'||c.cli==='codex'?'Despertar y seguir la conversación':'Despertar'}</button></div>
    :<div className="ab-term" ref={caja}/>}
   {c.estado==='te_necesita'&&<div className="ab-needs-banner"><b>{c.nombre}</b> espera tu respuesta</div>}
   <span className="ab-resize" onPointerDown={arrastre('tam')}/>
  </article>
 );
}

export function TableroView(){
 const [v,setV]=useState<Vista|null>(null),[error,setError]=useState(''),[foco,setFoco]=useState('');
 const [modal,setModal]=useState<null|'compositor'|'mapa'|'bucle'|'traspaso'|'cerrar'|'agrupar'>(null),[sujeto,setSujeto]=useState<Consola|null>(null);
 const [orden,setOrden]=useState(''),[aviso,setAviso]=useState(''),[enviadas,setEnviadas]=useState<string[]>([]),[escala,setEscala]=useState(0.8);
 const lienzo=useRef<HTMLDivElement>(null),barra=useRef<HTMLTextAreaElement>(null),moviendo=useRef<Record<string,Partial<Consola>>>({});
 const leer=useCallback(async()=>{try{setV(await api(''));setError('');}catch(e){setError(e instanceof Error?e.message:'Sin conexión con el tablero.');}},[]);
 useEffect(()=>{hub.abrir();return()=>hub.cerrar();},[]);
 useEffect(()=>{void leer();const t=setInterval(()=>void leer(),1500);return()=>clearInterval(t);},[leer]);
 useEffect(()=>{if(!aviso)return;const t=setTimeout(()=>setAviso(''),3500);return()=>clearTimeout(t);},[aviso]);
 const consolas=useMemo(()=>(v?.consolas||[]).map(c=>({...c,...moviendo.current[c.id]})),[v]);
 const hacer=async(fn:()=>Promise<unknown>,ok?:string)=>{try{await fn();if(ok)setAviso(ok);await leer();}catch(e){setAviso(e instanceof Error?e.message:'No ha funcionado.');}};
 const onMove=(id:string,p:Partial<Consola>,guardar:boolean)=>{moviendo.current[id]={...moviendo.current[id],...p};setV(x=>x?{...x}:x);
  if(guardar)void api('/mover',{id,...moviendo.current[id]}).then(()=>{delete moviendo.current[id];return leer();}).catch(()=>{});};
 const ir=(c:Consola)=>{setFoco(c.id);setModal(null);lienzo.current?.scrollTo({left:Math.max(0,c.x*escala-60),top:Math.max(0,c.y*escala-60),behavior:'smooth'});};
 const onAccion=(a:string,c:Consola)=>{
  if(a==='traspaso'||a==='bucle'){setSujeto(c);setModal(a);}
  else if(a==='cerrar'){if(c.estado==='dormida'||c.estado==='terminada')void hacer(()=>api('/cerrar',{id:c.id}),`${c.nombre} se ha ido.`);else{setSujeto(c);setModal('cerrar');}}
  else if(a==='reanudar')void hacer(()=>api('/reanudar',{id:c.id}),`${c.nombre} vuelve al tablero.`);
  else if(a==='pausar')void hacer(()=>api('/pausar',{id:c.id,si:true}),`${c.nombre} en pausa.`);
  else if(a==='reanudarPausa')void hacer(()=>api('/pausar',{id:c.id,si:false}),`${c.nombre} sigue.`);
 };
 const enviarOrden=async()=>{if(!orden.trim())return;try{const r=await api('/orden',{texto:orden});setOrden('');setAviso(r.sinDestino.length?`Sin destino: ${r.sinDestino.join(' · ')}`:`Entregado a ${r.entregadas.join(', ')}.`);}catch(err){setAviso(err instanceof Error?err.message:'No ha funcionado.');}};
 const equipos=useMemo(()=>{const m=new Map<string,Consola[]>();for(const c of consolas){if(!c.equipo)continue;m.set(c.equipo,[...(m.get(c.equipo)||[]),c]);}return [...m.entries()];},[consolas]);
 const lado=useMemo(()=>({w:Math.max(1600,...consolas.map(c=>c.x+c.w+200)),h:Math.max(1000,...consolas.map(c=>c.y+c.h+200))}),[consolas]);
 const vivas=consolas.filter(c=>c.estado!=='dormida'&&c.estado!=='terminada').length;
 const props=(v?.propuestas||[]).filter(p=>!enviadas.includes(p.de+p.a+p.texto));
 const necesitan=consolas.filter(c=>c.estado==='te_necesita');
 // «@» autocomplete in the command bar
 const arroba=useMemo(()=>{const m=orden.match(/@([\wáéíóúñ-]*)$/i);if(!m)return [];const q=m[1].toLowerCase();return [...new Set([...consolas.map(c=>c.nombre),...equipos.map(([e])=>e),'todos'])].filter(n=>n.toLowerCase().startsWith(q)).slice(0,6);},[orden,consolas,equipos]);

 return (
  <section className="j-workspace ab-root">
   {/* top bar */}
   <header className="ab-top">
    <div className="ab-tabs"><span className="ab-tab is-on">Principal <b>{consolas.length}</b></span></div>
    <div className="ab-top-right">
     {necesitan.length>0&&<button className="ab-needs-pill" onClick={()=>ir(necesitan[0])}><i/>{necesitan.length} te {necesitan.length===1?'necesita':'necesitan'}</button>}
     <span className="ab-live"><i/>{vivas} en marcha</span>
     {!!v?.turnos&&<span className="ab-xp" title="Turnos que han terminado tus agentes"><Zap size={12}/>{v.turnos} turnos</span>}
     <button className="ab-icon" title="Mapa de misión" onClick={()=>setModal('mapa')}><Crosshair size={16}/></button>
    </div>
   </header>
   {/* left tool rail */}
   <nav className="ab-rail">
    <button className="is-on" title="Seleccionar"><MousePointer2 size={16}/></button>
    <button title="Nueva consola" onClick={()=>setModal('compositor')}><Plus size={16}/></button>
    <button title="Lanzar un equipo" onClick={()=>setModal('compositor')}><Rocket size={16}/></button>
    <button title="Agrupar en un equipo" onClick={()=>setModal('agrupar')}><Users size={16}/></button>
    <button title="Bucles" onClick={()=>{setSujeto(consolas.find(c=>c.id===foco)||consolas[0]||null);setModal('bucle');}} disabled={!consolas.length}><Repeat size={16}/></button>
    <button title="Mapa de misión" onClick={()=>setModal('mapa')}><Crosshair size={16}/></button>
    <span className="ab-grow"/>
    <button title="Ordenar en rejilla" onClick={()=>void hacer(async()=>{let x=40,y=40,alto=0,n=0;for(const c of consolas){if(n===3){x=40;y+=alto+40;alto=0;n=0;}await api('/mover',{id:c.id,x,y});x+=c.w+40;alto=Math.max(alto,c.h);n++;}},'Ordenado.')}><LayoutGrid size={16}/></button>
   </nav>
   {error&&<p className="ab-error" role="alert">{error}</p>}
   {/* the canvas */}
   <div className="ab-canvas" ref={lienzo} onWheel={e=>{if(e.ctrlKey||e.metaKey){e.preventDefault();setEscala(s=>Math.min(1.5,Math.max(0.35,s*(e.deltaY>0?0.92:1.08))));}}}>
    <div className="ab-plane" style={{width:lado.w*escala,height:lado.h*escala}}>
     <div className="ab-zoom" style={{transform:`scale(${escala})`,width:lado.w,height:lado.h}} onPointerDown={e=>{if(e.target===e.currentTarget)setFoco('');}}>
      {equipos.map(([eq,cs])=>{const x0=Math.min(...cs.map(c=>c.x))-24,y0=Math.min(...cs.map(c=>c.y))-56,x1=Math.max(...cs.map(c=>c.x+c.w))+24,y1=Math.max(...cs.map(c=>c.y+c.h))+24;
       const t=cs.filter(c=>c.estado==='trabajando').length,n=cs.filter(c=>c.estado==='te_necesita').length;
       return <div key={eq} className="ab-team" style={{left:x0,top:y0,width:x1-x0,height:y1-y0}}><span className="ab-team-label"><Users size={13}/>{eq.toUpperCase()}<em>{cs.length} agentes</em>{t>0&&<em className="w">{t} trabajando</em>}{n>0&&<em className="n">{n} te necesita{n>1?'n':''}</em>}</span></div>;})}
      {consolas.map(c=><div key={c.id} onPointerDown={e=>{if(!(e.target as HTMLElement).closest('button'))setFoco(c.id);}}><Tarjeta c={c} ahora={v?.ahora||Date.now()/1000} onMove={onMove} onAccion={onAccion} foco={foco===c.id} escala={escala}/></div>)}
      {!consolas.length&&<div className="ab-empty"><div className="ab-empty-crew">{['Mila','Ren','Juno','Ada'].map((n,i)=><Avatar key={n} c={{nombre:n,cli:['claude','codex','claude','gemini'][i]}} size={52}/>)}</div><h2>Pon a tus agentes en un tablero</h2><p>Claude Code, Codex y Gemini en terminales de verdad, con la cuenta que ya tienes. Monta un equipo entero de una vez.</p><button className="ab-primary big" onClick={()=>setModal('compositor')}><Rocket size={16}/>Montar un equipo</button></div>}
     </div>
    </div>
   </div>
   <div className="ab-zoomctl"><button onClick={()=>setEscala(s=>Math.max(0.35,s-0.1))}><Minus size={13}/></button><span>{Math.round(escala*100)} %</span><button onClick={()=>setEscala(s=>Math.min(1.5,s+0.1))}><Plus size={13}/></button><button title="Ajustar" onClick={()=>{const w=lienzo.current?.clientWidth||1200;setEscala(Math.min(1,Math.max(0.35,(w-40)/lado.w)));}}><Maximize2 size={13}/></button></div>
   {/* orchestrator proposals */}
   {props.length>0&&<aside className="ab-props"><h3><Avatar c={{nombre:props[0].deNombre,cli:'claude'}} size={22}/>{props[0].deNombre} propone</h3>
    {props.map(p=><div key={p.de+p.a+p.texto} className="ab-prop"><span><b>@{p.a}</b> {p.texto}</span><button onClick={()=>void hacer(async()=>{await api('/orden',{texto:`@${p.a}: ${p.texto}`});setEnviadas(x=>[...x,p.de+p.a+p.texto]);},`Enviado a ${p.a}.`)}><Send size={12}/>Enviar</button></div>)}
    {props.length>1&&<button className="ab-chip" onClick={()=>void hacer(async()=>{await api('/orden',{texto:props.map(p=>`@${p.a}: ${p.texto}`).join('\n')});setEnviadas(x=>[...x,...props.map(p=>p.de+p.a+p.texto)]);},'Enviadas.')}>Enviar todas</button>}
   </aside>}
   {/* the command bar */}
   <div className="ab-command">
    <div className="ab-quick">
     <button onClick={()=>setModal('compositor')}><Plus size={12}/>Nueva consola</button>
     <button onClick={()=>void hacer(()=>api('/lanzar',{consolas:Array.from({length:4},()=>({cli:'claude',equipo:'equipo'}))}),'4 agentes al tablero.')}><Rocket size={12}/>Lanzar 4</button>
     <button onClick={()=>setModal('agrupar')}><Users size={12}/>Agrupar</button>
     <button onClick={()=>setModal('compositor')}><Layers size={12}/>Presets</button>
     <button onClick={()=>void hacer(()=>api('/todas',{pausar:true}),'Todos en pausa.')}><Pause size={12}/>Pausar todo</button>
     <button onClick={()=>void hacer(()=>api('/todas',{pausar:false}),'Todos siguen.')}><Play size={12}/>Reanudar todo</button>
    </div>
    {arroba.length>0&&<div className="ab-at">{arroba.map(n=><button key={n} onClick={()=>{setOrden(o=>o.replace(/@[\wáéíóúñ-]*$/i,'@'+n+': '));barra.current?.focus();}}>@{n}</button>)}</div>}
    <form className="ab-bar" onSubmit={e=>{e.preventDefault();void enviarOrden();}}>
     <span className="ab-bar-orb"/>
     <textarea ref={barra} rows={1} value={orden} onChange={e=>setOrden(e.target.value)} placeholder="@ para dirigir… · @Mila: añade las pruebas · @equipo: … · @todos: …" onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();void enviarOrden();}}}/>
     <button className="ab-send" disabled={!orden.trim()}><Send size={15}/></button>
    </form>
   </div>
   {aviso&&<p className="ab-toast" role="status">{aviso}</p>}

   {modal==='mapa'&&<Mapa consolas={consolas} bucles={v?.bucles||[]} ahora={v?.ahora||0} onCerrar={()=>setModal(null)} onIr={ir} onAccion={onAccion}/>}
   {modal==='compositor'&&<Compositor max={v?.max||12} onCerrar={()=>setModal(null)} onLanzar={async filas=>{await hacer(()=>api('/lanzar',{consolas:filas}),`${filas.length} ${filas.length===1?'agente':'agentes'} al tablero.`);setModal(null);}}/>}
   {modal==='agrupar'&&<Agrupar consolas={consolas} onCerrar={()=>setModal(null)} onAgrupar={async(ids,eq)=>{await hacer(()=>api('/agrupar',{ids,equipo:eq}),`Equipo ${eq} formado.`);setModal(null);}}/>}
   {modal==='traspaso'&&sujeto&&<Traspaso de={sujeto} consolas={consolas.filter(c=>c.id!==sujeto.id&&c.estado!=='dormida'&&c.estado!=='terminada')} onCerrar={()=>setModal(null)} onPasar={async(a,ins,env)=>{await hacer(()=>api('/traspaso',{de:sujeto.id,a,instruccion:ins,enviar:env}),'Pasado.');setModal(null);}}/>}
   {modal==='bucle'&&sujeto&&<NuevoBucle c={sujeto} consolas={consolas} onCerrar={()=>setModal(null)} onCrear={async(ids,b)=>{await hacer(async()=>{for(const id of ids)await api('/bucle',{consola:id,...b});},ids.length>1?`${ids.length} bucles en marcha.`:'Bucle en marcha.');setModal(null);}}/>}
   {modal==='cerrar'&&sujeto&&<div className="ab-modal-back" onClick={()=>setModal(null)}><div className="ab-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}><div className="ab-modal-head"><Avatar c={sujeto} size={34}/><h2>¿Cerrar a {sujeto.nombre}?</h2></div><p>Sigue viva{sujeto.estado==='trabajando'?' y está trabajando':''}. Al cerrarla se corta lo que esté haciendo.</p><div className="ab-actions"><button className="ab-secondary" onClick={()=>setModal(null)}>No</button><button className="ab-danger" onClick={async()=>{await hacer(()=>api('/cerrar',{id:sujeto.id,confirmar:true}),`${sujeto.nombre} se ha ido.`);setModal(null);}}>Cerrar</button></div></div></div>}
  </section>
 );
}

/** Mission map: orchestrator → teams → agents with curved links, filters, search and a detail panel */
function Mapa({consolas,bucles,ahora,onCerrar,onIr,onAccion}:{consolas:Consola[];bucles:Bucle[];ahora:number;onCerrar:()=>void;onIr:(c:Consola)=>void;onAccion:(a:string,c:Consola)=>void}){
 const [filtro,setFiltro]=useState<'todos'|Estado>('todos'),[q,setQ]=useState(''),[sel,setSel]=useState<Consola|null>(null);
 const orq=consolas.find(c=>/orquest/i.test(c.rol+' '+c.nombre));
 const equipos=useMemo(()=>{const m=new Map<string,Consola[]>();for(const c of consolas){if(c===orq)continue;const k=c.equipo||'Sin equipo';m.set(k,[...(m.get(k)||[]),c]);}return [...m.entries()];},[consolas,orq]);
 const visible=(c:Consola)=>(filtro==='todos'||c.estado===filtro)&&(!q||c.nombre.toLowerCase().includes(q.toLowerCase())||c.rol.toLowerCase().includes(q.toLowerCase()));
 const cuenta=(e:Estado)=>consolas.filter(c=>c.estado===e).length;
 // layout: orchestrator at left, teams in the middle column, agents at right
 const filas=equipos.flatMap(([eq,cs])=>cs.filter(visible).map(c=>({eq,c})));
 const ROW=54,top=24,H=Math.max(360,filas.length*ROW+48);
 const eqY=new Map<string,number>();let acc=0;for(const [eq,cs] of equipos){const n=cs.filter(visible).length;if(!n)continue;eqY.set(eq,top+(acc+n/2)*ROW);acc+=n;}
 const orqY=H/2;
 return (
  <div className="ab-modal-back" onClick={onCerrar}><div className="ab-mapa" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <header><div className="ab-mapa-title"><Crosshair size={18}/><div><h2>Mapa de misión</h2><p>{orq?'1 orquestador · ':''}{equipos.length} equipo{equipos.length===1?'':'s'} · {consolas.length} agentes · {cuenta('trabajando')} trabajando</p></div></div><button className="ab-icon" onClick={onCerrar}><X size={16}/></button></header>
   <div className="ab-mapa-filtros">
    {([['todos','Todos',consolas.length],['trabajando','Trabajando',cuenta('trabajando')],['te_necesita','Te necesita',cuenta('te_necesita')],['en_reposo','En reposo',cuenta('en_reposo')],['terminada','Terminados',cuenta('terminada')]] as [any,string,number][]).map(([k,l,n])=><button key={k} className={`is-${k}${filtro===k?' on':''}`} onClick={()=>setFiltro(k)}><i/>{l} <b>{n}</b></button>)}
    <label className="ab-search"><Search size={13}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Busca un agente o un equipo"/></label>
   </div>
   <div className="ab-mapa-body">
    <div className="ab-tree" style={{height:H}}>
     <svg width="100%" height={H} viewBox={`0 0 760 ${H}`} preserveAspectRatio="none">
      {[...eqY.entries()].map(([eq,y])=><path key={'o'+eq} d={`M 190 ${orqY} C 260 ${orqY}, 260 ${y}, 330 ${y}`} className="ab-link"/>)}
      {filas.map(({eq,c},i)=>{const y=top+i*ROW+ROW/2,ey=eqY.get(eq)!;return <path key={c.id} d={`M 470 ${ey} C 530 ${ey}, 530 ${y}, 590 ${y}`} className={`ab-link is-${c.estado}`}/>;})}
     </svg>
     <div className="ab-node orq" style={{left:20,top:orqY-28}} onClick={()=>orq&&setSel(orq)}>{orq?<><Avatar c={orq} size={30}/><div><b>{orq.nombre}</b><small>Orquestador</small></div></>:<><span className="ab-node-ico"><Crosshair size={14}/></span><div><b>Tú</b><small>Orquestas tú</small></div></>}</div>
     {[...eqY.entries()].map(([eq,y])=>{const cs=equipos.find(e=>e[0]===eq)![1];return <div key={eq} className="ab-node team" style={{left:330,top:y-24}}><span className="ab-node-ico"><Users size={14}/></span><div><b>{eq}</b><small>{cs.length} agentes · {cs.filter(c=>c.estado==='trabajando').length} trabajando</small></div></div>;})}
     {filas.map(({c},i)=><div key={c.id} className={`ab-node agent is-${c.estado}${sel?.id===c.id?' sel':''}`} style={{left:590,top:top+i*ROW+4}} onClick={()=>setSel(c)} onDoubleClick={()=>onIr(c)}><Avatar c={c} size={26}/><div><b>{c.nombre}</b><small>{NOMBRE[c.estado]}</small></div><i className="ab-dot"/></div>)}
     {!filas.length&&<p className="ab-tree-empty">Nadie en este filtro.</p>}
    </div>
    <aside className="ab-detail">{sel?<>
     <div className="ab-detail-head"><Avatar c={sel} size={44}/><div><h3>{sel.nombre}</h3><p>{sel.rol||CLI[sel.cli]?.nombre} · {sel.equipo||'sin equipo'}</p></div></div>
     <button className="ab-primary wide" onClick={()=>onIr(sel)}><Crosshair size={14}/>Ir al agente</button>
     <div className="ab-two">{sel.estado!=='dormida'&&sel.estado!=='terminada'&&<button className="ab-secondary" onClick={()=>onAccion(sel.estado==='pausada'?'reanudarPausa':'pausar',sel)}>{sel.estado==='pausada'?<><Play size={13}/>Reanudar</>:<><Pause size={13}/>Pausar</>}</button>}<button className="ab-danger-soft" onClick={()=>onAccion('cerrar',sel)}><Square size={12}/>Cerrar</button></div>
     <dl><dt>Estado</dt><dd className={`is-${sel.estado}`}>{NOMBRE[sel.estado]}</dd><dt>Tiempo</dt><dd>{tiempo(ahora-sel.inicio)||'—'}</dd><dt>Turnos</dt><dd>{sel.turnos}</dd><dt>Agente</dt><dd>{CLI[sel.cli]?.nombre||sel.cli}</dd><dt>Carpeta</dt><dd>{sel.cwd}</dd><dt>Bucles</dt><dd>{bucles.filter(b=>b.consola===sel.id&&b.activo).length||'ninguno'}</dd></dl>
    </>:<div className="ab-detail-empty"><Crosshair size={22}/><p>Toca un agente para ver qué hace. Doble clic te lleva a él.</p></div>}</aside>
   </div>
   <footer><span><i className="w"/>Trabajando</span><span><i className="n"/>Te necesita</span><span><i className="r"/>En reposo</span><span><i className="d"/>Terminado</span></footer>
  </div></div>
 );
}

type Fila={cli:string;nombre:string;rol:string;equipo:string;cwd:string;prompt:string};
/** Composer: up to 12 slots, roles, CLI per slot, one launch */
function Compositor({max,onCerrar,onLanzar}:{max:number;onCerrar:()=>void;onLanzar:(f:Fila[])=>Promise<void>}){
 const [equipo,setEquipo]=useState('equipo'),[rol,setRol]=useState('General'),[cli,setCli]=useState('claude'),[n,setN]=useState(4),[cwd,setCwd]=useState(''),[prompt,setPrompt]=useState(''),[slots,setSlots]=useState<string[]>(Array.from({length:12},(_,i)=>i%4===3?'codex':'claude'));
 const [lanzando,setLanzando]=useState(false);
 const preset=(p:string)=>{if(p==='duo'){setN(2);setSlots(s=>['claude','codex',...s.slice(2)]);setEquipo('equipo');}if(p==='trio'){setN(3);setSlots(s=>['claude','codex','gemini',...s.slice(3)]);setEquipo('trío');}if(p==='flota'){setN(5);setSlots(s=>['claude','claude','codex','claude','codex',...s.slice(5)]);setEquipo('flota');setRol('General');setPrompt('');}};
 return (
  <div className="ab-modal-back" onClick={onCerrar}><div className="ab-modal ab-composer" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <div className="ab-modal-head"><span className="ab-node-ico big"><Users size={18}/></span><div><input className="ab-team-name" value={equipo} onChange={e=>setEquipo(e.target.value)} aria-label="Nombre del equipo"/><p>Monta el equipo y lánzalo de una vez</p></div></div>
   <div className="ab-roles">{ROLES.map(r=><button key={r} className={rol===r?'on':''} onClick={()=>setRol(r)}><i/>{r}</button>)}</div>
   <div className="ab-slots">{Array.from({length:12},(_,i)=>{const on=i<n,k=CLI[slots[i]];return <button key={i} className={`ab-slot${on?' on':''}`} style={{['--cli' as any]:k.color}} onClick={()=>{if(!on)setN(i+1);else setSlots(s=>s.map((x,j)=>j===i?(x==='claude'?'codex':x==='codex'?'gemini':'claude'):x));}}>{on?<><span className="ab-slot-ico">{k.letra}</span><small>{k.nombre}</small></>:<Plus size={14}/>}</button>;})}</div>
   <div className="ab-cli-pick"><span>Todos con</span>{(['claude','codex','gemini','shell'] as const).map(k=><button key={k} className={cli===k?'on':''} style={{['--cli' as any]:CLI[k].color}} onClick={()=>{setCli(k);setSlots(s=>s.map(()=>k));}}>{CLI[k].letra} {CLI[k].nombre}</button>)}</div>
   <div className="ab-two"><label>Carpeta<input value={cwd} onChange={e=>setCwd(e.target.value)} placeholder="~/proyecto"/></label><label>Primer mensaje (opcional)<input value={prompt} onChange={e=>setPrompt(e.target.value)} placeholder="Se envía al abrir"/></label></div>
   <div className="ab-presets"><span>Presets</span><button className="ab-chip" onClick={()=>preset('duo')}>Constructor y revisor</button><button className="ab-chip" onClick={()=>preset('trio')}>Claude, Codex y Gemini</button><button className="ab-chip" onClick={()=>preset('flota')}>Flota de 5</button></div>
   <div className="ab-actions"><div className="ab-stepper"><button onClick={()=>setN(x=>Math.max(1,x-1))}><Minus size={13}/></button><b>{n}</b><button onClick={()=>setN(x=>Math.min(max,x+1))}><Plus size={13}/></button></div><span className="ab-grow"/><button className="ab-secondary" onClick={onCerrar}>Cancelar</button>
    <button className="ab-primary" disabled={lanzando} onClick={async()=>{setLanzando(true);try{await onLanzar(Array.from({length:n},(_,i)=>({cli:slots[i],nombre:'',rol:rol==='General'?'':rol,equipo,cwd,prompt})));}finally{setLanzando(false);}}}><Rocket size={15}/>Lanzar {n}</button></div>
  </div></div>
 );
}

function Agrupar({consolas,onCerrar,onAgrupar}:{consolas:Consola[];onCerrar:()=>void;onAgrupar:(ids:string[],eq:string)=>Promise<void>}){
 const [sel,setSel]=useState<string[]>([]),[eq,setEq]=useState('equipo');
 return (
  <div className="ab-modal-back" onClick={onCerrar}><div className="ab-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <div className="ab-modal-head"><span className="ab-node-ico big"><Users size={18}/></span><h2>Agrupar en un equipo</h2></div>
   <label>Nombre del equipo<input value={eq} onChange={e=>setEq(e.target.value)}/></label>
   <div className="ab-pick">{consolas.map(c=><button key={c.id} className={sel.includes(c.id)?'on':''} onClick={()=>setSel(s=>s.includes(c.id)?s.filter(x=>x!==c.id):[...s,c.id])}><Avatar c={c} size={24}/>{c.nombre}<small>{c.equipo||'—'}</small></button>)}</div>
   <div className="ab-actions"><button className="ab-secondary" onClick={onCerrar}>Cancelar</button><button className="ab-primary" disabled={!sel.length||!eq.trim()} onClick={()=>void onAgrupar(sel,eq)}><Users size={14}/>Agrupar {sel.length}</button></div>
  </div></div>
 );
}

function Traspaso({de,consolas,onCerrar,onPasar}:{de:Consola;consolas:Consola[];onCerrar:()=>void;onPasar:(a:string,instruccion:string,enviar:boolean)=>Promise<void>}){
 const [a,setA]=useState(consolas[0]?.id||''),[instruccion,setInstruccion]=useState('Revisa lo que ha hecho y dime qué falla.'),[enviar,setEnviar]=useState(true);
 return (
  <div className="ab-modal-back" onClick={onCerrar}><div className="ab-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <div className="ab-modal-head"><Avatar c={de} size={34}/><h2>Pasar lo último de {de.nombre}</h2></div>
   {!consolas.length?<p>No hay otro agente despierto al que pasarlo.</p>:<>
    <div className="ab-pick">{consolas.map(c=><button key={c.id} className={a===c.id?'on':''} onClick={()=>setA(c.id)}><Avatar c={c} size={24}/>{c.nombre}<small>{c.rol||CLI[c.cli]?.nombre}</small></button>)}</div>
    <label>Con esta instrucción<textarea rows={3} value={instruccion} onChange={e=>setInstruccion(e.target.value)}/></label>
    <label className="ab-check"><input type="checkbox" checked={enviar} onChange={e=>setEnviar(e.target.checked)}/>Enviarlo (si no, solo se escribe y el Intro lo pulsas tú)</label>
   </>}
   <div className="ab-actions"><button className="ab-secondary" onClick={onCerrar}>Cancelar</button><button className="ab-primary" disabled={!a} onClick={()=>void onPasar(a,instruccion,enviar)}><ArrowRightLeft size={14}/>Pasar</button></div>
  </div></div>
 );
}

function NuevoBucle({c,consolas,onCerrar,onCrear}:{c:Consola;consolas:Consola[];onCerrar:()=>void;onCrear:(ids:string[],b:{mensaje:string;disparo:string;segundos:number;objetivo:string;max:number})=>Promise<void>}){
 const [mensaje,setMensaje]=useState('Sigue con lo siguiente del plan.'),[disparo,setDisparo]=useState<'inactividad'|'cada'>('inactividad'),[segundos,setSegundos]=useState(60),[objetivo,setObjetivo]=useState(''),[max,setMax]=useState(10),[todos,setTodos]=useState(false);
 const destino=todos?consolas.filter(x=>x.estado!=='dormida'&&x.estado!=='terminada').map(x=>x.id):[c.id];
 return (
  <div className="ab-modal-back" onClick={onCerrar}><div className="ab-modal ab-loops" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <div className="ab-modal-head"><span className="ab-node-ico big"><Repeat size={18}/></span><div><h2>Bucles</h2><p>Que un agente siga solo, y que pare cuando se cumpla el objetivo.</p></div></div>
   <div className="ab-templates"><span>Plantillas</span>{PLANTILLAS.map(([n,m,d,s,o])=><button key={n} className="ab-chip" onClick={()=>{setMensaje(m);setDisparo(d);setSegundos(s);setObjetivo(o);}}>{n}</button>)}</div>
   <label>Instrucción<textarea rows={2} value={mensaje} onChange={e=>setMensaje(e.target.value)}/></label>
   <div className="ab-when">
    <button className={disparo==='cada'?'on':''} onClick={()=>setDisparo('cada')}><b>Cada cierto tiempo</b><small>Le escribe cada intervalo</small></button>
    <button className={disparo==='inactividad'?'on':''} onClick={()=>setDisparo('inactividad')}><b>Cuando se queda quieto</b><small>Le escribe al terminar su turno</small></button>
   </div>
   <div className="ab-intervals">{[[30,'30 s'],[60,'1 min'],[300,'5 min'],[600,'10 min'],[900,'15 min'],[1800,'30 min'],[3600,'1 h']].map(([s,l])=><button key={s} className={segundos===s?'on':''} onClick={()=>setSegundos(s as number)}>{l}</button>)}</div>
   <div className="ab-target"><button className={!todos?'on':''} onClick={()=>setTodos(false)}><Avatar c={c} size={20}/>{c.nombre}</button><button className={todos?'on':''} onClick={()=>setTodos(true)}><Users size={14}/>Todos los agentes despiertos</button></div>
   <div className="ab-two"><label>Para cuando este comando salga bien<input value={objetivo} onChange={e=>setObjetivo(e.target.value)} placeholder="npm test"/></label><label>Como mucho (vueltas)<input type="number" min={1} max={200} value={max} onChange={e=>setMax(Number(e.target.value))}/></label></div>
   <p className="ab-note">Nunca contesta a un permiso ni interrumpe mientras trabaja.</p>
   <div className="ab-actions"><button className="ab-secondary" onClick={onCerrar}>Cancelar</button><button className="ab-primary" disabled={!mensaje.trim()||!destino.length} onClick={()=>void onCrear(destino,{mensaje,disparo,segundos,objetivo,max})}><Repeat size={14}/>Crear {destino.length>1?`${destino.length} bucles`:'bucle'}</button></div>
  </div></div>
 );
}
