'use client';
// Agentes (⌘7, 12/11/2026): the agents board. Real terminals of Claude Code, Codex, Gemini or any command, as consoles on
// one board, with a mission map (who is working, who needs you, who rests), a composer that launches up to 12 at once,
// handoffs, orders by name and loops that retire themselves. Server: local-workspace/tablero.ts (+ pty-bridge.py).
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {Terminal} from '@xterm/xterm';
import {FitAddon} from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';
import {ArrowRightLeft,Play,Plus,Repeat,Rocket,Send,Square,X} from 'lucide-react';
import './board.css';

type Estado='trabajando'|'te_necesita'|'en_reposo'|'terminada'|'dormida';
type Consola={id:string;nombre:string;cli:string;cliNombre:string;comando?:string;rol:string;equipo:string;cwd:string;x:number;y:number;w:number;h:number;estado:Estado;salida:number|null};
type Bucle={id:string;consola:string;mensaje:string;disparo:'inactividad'|'cada';segundos:number;objetivo:string;max:number;vueltas:number;activo:boolean;motivo:string};
type Propuesta={de:string;deNombre:string;a:string;texto:string};
type Vista={consolas:Consola[];bucles:Bucle[];equipos:{nombre:string;consolas:string[]}[];cuenta:Record<Estado,number>;propuestas:Propuesta[];max:number};
type Fila={cli:string;nombre:string;rol:string;equipo:string;cwd:string;prompt:string;comando:string};

const NOMBRE:Record<Estado,string>={trabajando:'Trabajando',te_necesita:'Te necesita',en_reposo:'En reposo',terminada:'Terminada',dormida:'Dormida'};
const ORDEN:Estado[]=['te_necesita','trabajando','en_reposo','terminada','dormida'];
const fila=(f:Partial<Fila>={}):Fila=>({cli:'claude',nombre:'',rol:'',equipo:'',cwd:'',prompt:'',comando:'',...f});
const PRESETS:{nombre:string;filas:()=>Fila[]}[]=[
 {nombre:'Constructor y revisor',filas:()=>[fila({cli:'claude',nombre:'constructor',rol:'Construye',equipo:'equipo'}),fila({cli:'codex',nombre:'revisor',rol:'Revisa lo que hace el constructor',equipo:'equipo'})]},
 {nombre:'Claude, Codex y Gemini',filas:()=>[fila({cli:'claude',nombre:'claude',equipo:'trio'}),fila({cli:'codex',nombre:'codex',equipo:'trio'}),fila({cli:'gemini',nombre:'gemini',equipo:'trio'})]},
 {nombre:'Orquestador y 4 agentes',filas:()=>[fila({cli:'claude',nombre:'orquestador',rol:'Reparte y comprueba',equipo:'flota',prompt:'Eres el orquestador de un equipo de agentes: agente1, agente2, agente3 y agente4, cada uno en su propia consola. Cuando te dé un objetivo, divídelo en tareas pequeñas y escribe una línea por tarea con el formato «@agenteN: tarea». Yo reviso tus líneas y las envío. No hagas tú el trabajo de los agentes.'}),...[1,2,3,4].map(i=>fila({cli:i%2?'claude':'codex',nombre:`agente${i}`,rol:'Una tarea a la vez',equipo:'flota'}))]},
];

// Two transports: inside Agent Bar the page talks to its native engine (BoardEngine.swift) through a message handler
// with replies and receives the output through window.__boardEvents; in Diego OS it uses /api/tablero over HTTP.
const nativo=()=>(window as any).webkit?.messageHandlers?.board;
async function api(path:string,body?:unknown):Promise<any>{
 const n=nativo();
 if(n){try{return await n.postMessage({path,body:body??{}});}catch(e:any){throw Error(String(e?.message||e||'No ha funcionado.'));}}
 const r=await fetch('/api/tablero'+path,body===undefined?{credentials:'same-origin'}:{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 const j:any=await r.json().catch(()=>({}));if(!r.ok)throw Error(j.error||'No ha funcionado.');return j;
}
const base=(p:string)=>p.split('/').filter(Boolean).pop()||'~';

/** one live stream for the whole board (a stream per console exhausted the browser's six connections per host): each
 *  card registers to receive its console's bytes; what arrives before its card exists waits here */
const hub=(()=>{
 const buf=new Map<string,Uint8Array[]>(),subs=new Map<string,{write:(u:Uint8Array)=>void;reset:()=>void}>();
 let es:EventSource|null=null,usuarios=0;
 const bytes=(b64:string)=>{const bin=atob(b64),u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return u;};
 const entregar=(id:string,u:Uint8Array)=>{const s=subs.get(id);if(s)s.write(u);else{const l=buf.get(id)||[];l.push(u);while(l.length>400)l.shift();buf.set(id,l);}};
 return {
  abrir(){if(usuarios++||es)return;
   if(nativo()){
    (window as any).__boardEvents=(lote:[string,string][])=>{for(const [ev,data] of lote){
     if(ev==='nueva'){subs.get(data)?.reset();buf.delete(data);}
     else if(ev==='o'){const i=data.indexOf(' ');entregar(data.slice(0,i),bytes(data.slice(i+1)));}}};
    buf.clear();for(const s of subs.values())s.reset();void api('/flujo',{});return;
   }
   es=new EventSource('/api/tablero/flujo');
   es.addEventListener('hola',()=>{buf.clear();for(const s of subs.values())s.reset();});
   es.addEventListener('nueva',(e:MessageEvent)=>{subs.get(e.data)?.reset();buf.delete(e.data);});
   es.addEventListener('o',(e:MessageEvent)=>{const i=e.data.indexOf(' ');entregar(e.data.slice(0,i),bytes(e.data.slice(i+1)));});},
  cerrar(){if(--usuarios<=0){usuarios=0;es?.close();es=null;buf.clear();}},
  registrar(id:string,s:{write:(u:Uint8Array)=>void;reset:()=>void}){subs.set(id,s);for(const u of buf.get(id)||[])s.write(u);buf.delete(id);return ()=>{if(subs.get(id)===s)subs.delete(id);};},
 };
})();


/** one console: header, the real terminal, and its own resize handle */
function Tarjeta({c,onMove,onAccion,foco}:{c:Consola;onMove:(id:string,p:Partial<Consola>,guardar:boolean)=>void;onAccion:(a:string,c:Consola)=>void;foco:boolean}){
 const caja=useRef<HTMLDivElement>(null),term=useRef<Terminal|null>(null),fit=useRef<FitAddon|null>(null);
 useEffect(()=>{
  if(!caja.current||c.estado==='dormida')return;
  const t=new Terminal({fontFamily:"'SF Mono', Menlo, monospace",fontSize:12.5,lineHeight:1.15,cursorBlink:true,allowProposedApi:false,scrollback:5000,
   theme:{background:'#0b0c10',foreground:'#e6e7ea',cursor:'#e6e7ea',selectionBackground:'#3a4150'}});
  const f=new FitAddon();t.loadAddon(f);t.open(caja.current);term.current=t;fit.current=f;
  try{f.fit();}catch{}
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
  const mov=(ev:PointerEvent)=>{const dx=ev.clientX-x0,dy=ev.clientY-y0;onMove(c.id,modo==='mover'?{x:Math.max(0,o.x+dx),y:Math.max(0,o.y+dy)}:{w:Math.max(380,o.w+dx),h:Math.max(240,o.h+dy)},false);};
  const fin=(ev:PointerEvent)=>{window.removeEventListener('pointermove',mov);window.removeEventListener('pointerup',fin);const dx=ev.clientX-x0,dy=ev.clientY-y0;onMove(c.id,modo==='mover'?{x:Math.max(0,o.x+dx),y:Math.max(0,o.y+dy)}:{w:Math.max(380,o.w+dx),h:Math.max(240,o.h+dy)},true);};
  window.addEventListener('pointermove',mov);window.addEventListener('pointerup',fin);
 };
 return (
  <article className={`tb-card is-${c.estado}${foco?' is-focus':''}`} style={{left:c.x,top:c.y,width:c.w,height:c.h}} data-id={c.id}>
   <header onPointerDown={arrastre('mover')}>
    <i className="tb-dot" title={NOMBRE[c.estado]}/>
    <strong>{c.nombre}</strong>
    <span className="tb-meta">{c.cliNombre}{c.rol?' · '+c.rol:''} · {base(c.cwd)}</span>
    <span className="tb-state">{NOMBRE[c.estado]}</span>
    <nav>
     <button title="Pasar lo último a otra consola" onClick={()=>onAccion('traspaso',c)}><ArrowRightLeft size={14}/></button>
     <button title="Bucle" onClick={()=>onAccion('bucle',c)}><Repeat size={14}/></button>
     <button title="Cerrar" onClick={()=>onAccion('cerrar',c)}><X size={14}/></button>
    </nav>
   </header>
   {c.estado==='dormida'
    ?<div className="tb-sleep"><p>Esta consola se cerró con la app.</p><button className="tb-primary" onClick={()=>onAccion('reanudar',c)}><Play size={14}/>{c.cli==='claude'||c.cli==='codex'?'Reanudar la conversación':'Volver a abrir'}</button></div>
    :<div className="tb-term" ref={caja}/>}
   <span className="tb-resize" onPointerDown={arrastre('tam')}/>
  </article>
 );
}

export function TableroView(){
 const [v,setV]=useState<Vista|null>(null),[error,setError]=useState(''),[foco,setFoco]=useState('');
 const [compositor,setCompositor]=useState<Fila[]|null>(null),[traspaso,setTraspaso]=useState<Consola|null>(null),[bucle,setBucle]=useState<Consola|null>(null),[cerrar,setCerrar]=useState<Consola|null>(null);
 const [orden,setOrden]=useState(''),[aviso,setAviso]=useState(''),[enviadas,setEnviadas]=useState<string[]>([]);
 const lienzo=useRef<HTMLDivElement>(null),moviendo=useRef<Record<string,Partial<Consola>>>({});
 const leer=useCallback(async()=>{try{const j=await api('');setV(j);setError('');}catch(e){setError(e instanceof Error?e.message:'Sin conexión con el tablero.');}},[]);
 useEffect(()=>{hub.abrir();return()=>hub.cerrar();},[]);
 useEffect(()=>{void leer();const t=setInterval(()=>void leer(),1500);return()=>clearInterval(t);},[leer]);
 useEffect(()=>{if(!aviso)return;const t=setTimeout(()=>setAviso(''),4000);return()=>clearTimeout(t);},[aviso]);
 const consolas=useMemo(()=>(v?.consolas||[]).map(c=>({...c,...moviendo.current[c.id]})),[v]);
 const hacer=async(fn:()=>Promise<unknown>,ok?:string)=>{try{await fn();if(ok)setAviso(ok);await leer();}catch(e){setAviso(e instanceof Error?e.message:'No ha funcionado.');}};
 const onMove=(id:string,p:Partial<Consola>,guardar:boolean)=>{
  moviendo.current[id]={...moviendo.current[id],...p};setV(x=>x?{...x}:x);
  if(guardar){void api('/mover',{id,...moviendo.current[id]}).then(()=>{delete moviendo.current[id];return leer();}).catch(()=>{});}
 };
 const ir=(c:Consola)=>{setFoco(c.id);lienzo.current?.scrollTo({left:Math.max(0,c.x-40),top:Math.max(0,c.y-40),behavior:'smooth'});};
 const onAccion=(a:string,c:Consola)=>{if(a==='traspaso')setTraspaso(c);else if(a==='bucle')setBucle(c);else if(a==='cerrar'){if(c.estado==='dormida'||c.estado==='terminada')void hacer(()=>api('/cerrar',{id:c.id}),'Consola quitada.');else setCerrar(c);}else if(a==='reanudar')void hacer(()=>api('/reanudar',{id:c.id}));};
 const enviarOrden=async(e:React.FormEvent)=>{e.preventDefault();if(!orden.trim())return;try{const r=await api('/orden',{texto:orden});setOrden('');setAviso(r.sinDestino.length?`Sin destino: ${r.sinDestino.join(' · ')}`:`Entregado a ${r.entregadas.join(', ')}.`);}catch(err){setAviso(err instanceof Error?err.message:'No ha funcionado.');}};
 const grupos=useMemo(()=>{const m=new Map<string,Consola[]>();for(const c of consolas){const k=c.equipo||'Sin equipo';m.set(k,[...(m.get(k)||[]),c]);}return [...m.entries()];},[consolas]);
 const lado=useMemo(()=>({w:Math.max(1200,...consolas.map(c=>c.x+c.w+80)),h:Math.max(800,...consolas.map(c=>c.y+c.h+80))}),[consolas]);
 const necesitan=consolas.filter(c=>c.estado==='te_necesita');

 return (
  <section className="j-workspace tb-root">
   <aside className="tb-mission" aria-label="Mapa de misión">
    <h2>Mapa de misión</h2>
    <div className="tb-counts">{(['te_necesita','trabajando','en_reposo'] as Estado[]).map(e=><span key={e} className={`is-${e}`}><b>{v?.cuenta[e]||0}</b>{NOMBRE[e]}</span>)}</div>
    {(()=>{const ps=(v?.propuestas||[]).filter(p=>!enviadas.includes(p.de+p.a+p.texto));return ps.length>0&&<section className="tb-props"><h3>{ps[0].deNombre} propone</h3>{ps.map(p=><div key={p.de+p.a+p.texto} className="tb-prop"><span><b>@{p.a}</b> {p.texto}</span><button onClick={()=>void hacer(async()=>{await api('/orden',{texto:`@${p.a}: ${p.texto}`});setEnviadas(x=>[...x,p.de+p.a+p.texto]);},`Enviado a ${p.a}.`)}><Send size={12}/>Enviar</button></div>)}{ps.length>1&&<button className="tb-chip" onClick={()=>void hacer(async()=>{await api('/orden',{texto:ps.map(p=>`@${p.a}: ${p.texto}`).join('\n')});setEnviadas(x=>[...x,...ps.map(p=>p.de+p.a+p.texto)]);},'Enviadas.')}>Enviar todas</button>}</section>;})()}
    {necesitan.length>0&&<section className="tb-needs"><h3>Te necesitan</h3>{necesitan.map(c=><button key={c.id} onClick={()=>ir(c)}><i className="tb-dot"/>{c.nombre}</button>)}</section>}
    {grupos.map(([g,cs])=><section key={g}><h3>{g}</h3>{[...cs].sort((a,b)=>ORDEN.indexOf(a.estado)-ORDEN.indexOf(b.estado)).map(c=><button key={c.id} className={`is-${c.estado}`} onClick={()=>ir(c)}><i className="tb-dot"/><span>{c.nombre}</span><small>{NOMBRE[c.estado]}</small></button>)}</section>)}
    {!!v?.bucles.length&&<section><h3>Bucles</h3>{v.bucles.map(b=>{const c=consolas.find(x=>x.id===b.consola);return <div key={b.id} className={'tb-loop'+(b.activo?' on':'')}><span>{c?.nombre||'—'} · {b.disparo==='cada'?`cada ${b.segundos} s`:`tras ${b.segundos} s quieta`}</span><small>{b.activo?`${b.vueltas}/${b.max} vueltas${b.objetivo?' · hasta que «'+b.objetivo+'» salga bien':''}`:b.motivo}</small>{b.activo?<button onClick={()=>void hacer(()=>api('/bucle/parar',{id:b.id}))}><Square size={12}/>Parar</button>:<button onClick={()=>void hacer(()=>api('/bucle/parar',{id:b.id,quitar:true}))}>Quitar</button>}</div>;})}</section>}
    {!consolas.length&&<p className="tb-empty-side">Sin consolas todavía.</p>}
   </aside>
   <div className="tb-main">
    <div className="tb-toolbar">
     <h1>Agentes</h1>
     <span className="tb-hint">Terminales reales con tus suscripciones. Nada se envía sin tu Intro o tu orden.</span>
     <button className="tb-secondary" onClick={()=>setCompositor([fila()])}><Plus size={15}/>Consola</button>
     <button className="tb-primary" onClick={()=>setCompositor(PRESETS[0].filas())}><Rocket size={15}/>Lanzar equipo</button>
    </div>
    {error&&<p className="tb-error" role="alert">{error}</p>}
    <div className="tb-canvas" ref={lienzo}>
     <div className="tb-plane" style={{width:lado.w,height:lado.h}} onPointerDown={e=>{if(e.target===e.currentTarget)setFoco('');}}>
      {consolas.map(c=><div key={c.id} onPointerDown={e=>{if(!(e.target as HTMLElement).closest('button'))setFoco(c.id);}}><Tarjeta c={c} onMove={onMove} onAccion={onAccion} foco={foco===c.id}/></div>)}
      {!consolas.length&&<div className="tb-empty"><h2>Pon a tus agentes en un tablero</h2><p>Claude Code, Codex y Gemini en terminales de verdad, con la cuenta que ya tienes. Lanza un equipo entero de una vez.</p><button className="tb-primary" onClick={()=>setCompositor(PRESETS[0].filas())}><Rocket size={15}/>Lanzar equipo</button></div>}
     </div>
    </div>
    <form className="tb-order" onSubmit={enviarOrden}>
     <textarea rows={1} value={orden} onChange={e=>setOrden(e.target.value)} placeholder="@constructor: añade las pruebas · @revisor: revisa cuando acabe · @equipo: … · @todos: …" onKeyDown={e=>{if(e.key==='Enter'&&!e.shiftKey&&!e.nativeEvent.isComposing){e.preventDefault();e.currentTarget.form?.requestSubmit();}}}/>
     <button className="tb-primary" disabled={!orden.trim()}><Send size={15}/>Ordenar</button>
    </form>
    {aviso&&<p className="tb-toast" role="status">{aviso}</p>}
   </div>

   {compositor&&<Compositor filas={compositor} setFilas={setCompositor} max={v?.max||12} onLanzar={async filas=>{await hacer(()=>api('/lanzar',{consolas:filas.map(f=>({...f,prompt:f.prompt||undefined}))}),`${filas.length} ${filas.length===1?'consola lanzada':'consolas lanzadas'}.`);setCompositor(null);}}/>}
   {traspaso&&<Traspaso de={traspaso} consolas={consolas.filter(c=>c.id!==traspaso.id&&c.estado!=='dormida'&&c.estado!=='terminada')} onCerrar={()=>setTraspaso(null)} onPasar={async(a,instruccion,enviar)=>{await hacer(()=>api('/traspaso',{de:traspaso.id,a,instruccion,enviar}),'Pasado.');setTraspaso(null);}}/>}
   {bucle&&<NuevoBucle c={bucle} onCerrar={()=>setBucle(null)} onCrear={async b=>{await hacer(()=>api('/bucle',{consola:bucle.id,...b}),'Bucle en marcha.');setBucle(null);}}/>}
   {cerrar&&<div className="tb-modal-back" onClick={()=>setCerrar(null)}><div className="tb-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}><h2>¿Cerrar {cerrar.nombre}?</h2><p>La consola sigue viva{cerrar.estado==='trabajando'?' y está trabajando':''}. Al cerrarla se corta lo que esté haciendo.</p><div className="tb-actions"><button className="tb-secondary" onClick={()=>setCerrar(null)}>No</button><button className="tb-danger" onClick={async()=>{await hacer(()=>api('/cerrar',{id:cerrar.id,confirmar:true}),'Consola cerrada.');setCerrar(null);}}>Cerrar consola</button></div></div></div>}
  </section>
 );
}

function Compositor({filas,setFilas,max,onLanzar}:{filas:Fila[];setFilas:(f:Fila[]|null)=>void;max:number;onLanzar:(f:Fila[])=>Promise<void>}){
 const [lanzando,setLanzando]=useState(false);
 const cambia=(i:number,p:Partial<Fila>)=>setFilas(filas.map((f,j)=>j===i?{...f,...p}:f));
 return (
  <div className="tb-modal-back" onClick={()=>setFilas(null)}>
   <div className="tb-modal wide" role="dialog" aria-modal="true" aria-label="Lanzar consolas" onClick={e=>e.stopPropagation()}>
    <h2>Lanzar consolas</h2>
    <div className="tb-presets">{PRESETS.map(p=><button key={p.nombre} className="tb-chip" onClick={()=>setFilas(p.filas())}>{p.nombre}</button>)}</div>
    <div className="tb-rows">
     <div className="tb-row head"><span>Agente</span><span>Nombre</span><span>Rol</span><span>Equipo</span><span>Carpeta</span><span>Primer mensaje (opcional)</span><span/></div>
     {filas.map((f,i)=><div className="tb-row" key={i}>
      <select value={f.cli} onChange={e=>cambia(i,{cli:e.target.value})}><option value="claude">Claude Code</option><option value="codex">Codex</option><option value="gemini">Gemini CLI</option><option value="shell">Terminal</option><option value="custom">Otro comando</option></select>
      {f.cli==='custom'?<input value={f.comando} onChange={e=>cambia(i,{comando:e.target.value})} placeholder="comando"/>:<input value={f.nombre} onChange={e=>cambia(i,{nombre:e.target.value})} placeholder="constructor"/>}
      <input value={f.rol} onChange={e=>cambia(i,{rol:e.target.value})} placeholder="Qué hace"/>
      <input value={f.equipo} onChange={e=>cambia(i,{equipo:e.target.value})} placeholder="equipo"/>
      <input value={f.cwd} onChange={e=>cambia(i,{cwd:e.target.value})} placeholder="~/proyecto"/>
      <input value={f.prompt} onChange={e=>cambia(i,{prompt:e.target.value})} placeholder="Se envía al abrir"/>
      <button className="tb-icon" aria-label="Quitar" onClick={()=>setFilas(filas.filter((_,j)=>j!==i))}><X size={14}/></button>
     </div>)}
    </div>
    <div className="tb-actions">
     <button className="tb-secondary" disabled={filas.length>=max} onClick={()=>setFilas([...filas,fila({equipo:filas[filas.length-1]?.equipo||'',cwd:filas[filas.length-1]?.cwd||''})])}><Plus size={14}/>Otra ({filas.length}/{max})</button>
     <span className="tb-grow"/>
     <button className="tb-secondary" onClick={()=>setFilas(null)}>Cancelar</button>
     <button className="tb-primary" disabled={!filas.length||lanzando} onClick={async()=>{setLanzando(true);try{await onLanzar(filas);}finally{setLanzando(false);}}}><Rocket size={15}/>Lanzar {filas.length}</button>
    </div>
   </div>
  </div>
 );
}

function Traspaso({de,consolas,onCerrar,onPasar}:{de:Consola;consolas:Consola[];onCerrar:()=>void;onPasar:(a:string,instruccion:string,enviar:boolean)=>Promise<void>}){
 const [a,setA]=useState(consolas[0]?.id||''),[instruccion,setInstruccion]=useState('Revisa lo que ha hecho y dime qué falla.'),[enviar,setEnviar]=useState(true);
 return (
  <div className="tb-modal-back" onClick={onCerrar}><div className="tb-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <h2>Pasar lo último de {de.nombre}</h2>
   {!consolas.length?<p>No hay otra consola viva a la que pasarlo.</p>:<>
    <label>A<select value={a} onChange={e=>setA(e.target.value)}>{consolas.map(c=><option key={c.id} value={c.id}>{c.nombre} · {c.cliNombre}</option>)}</select></label>
    <label>Con esta instrucción<textarea rows={3} value={instruccion} onChange={e=>setInstruccion(e.target.value)}/></label>
    <label className="tb-check"><input type="checkbox" checked={enviar} onChange={e=>setEnviar(e.target.checked)}/>Enviarlo (si no, solo se escribe y el Intro lo pulsas tú)</label>
   </>}
   <div className="tb-actions"><button className="tb-secondary" onClick={onCerrar}>Cancelar</button><button className="tb-primary" disabled={!a} onClick={()=>void onPasar(a,instruccion,enviar)}><ArrowRightLeft size={14}/>Pasar</button></div>
  </div></div>
 );
}

function NuevoBucle({c,onCerrar,onCrear}:{c:Consola;onCerrar:()=>void;onCrear:(b:{mensaje:string;disparo:string;segundos:number;objetivo:string;max:number})=>Promise<void>}){
 const [mensaje,setMensaje]=useState('Sigue con la siguiente tarea.'),[disparo,setDisparo]=useState('inactividad'),[segundos,setSegundos]=useState(60),[objetivo,setObjetivo]=useState(''),[max,setMax]=useState(10);
 return (
  <div className="tb-modal-back" onClick={onCerrar}><div className="tb-modal" role="dialog" aria-modal="true" onClick={e=>e.stopPropagation()}>
   <h2>Bucle en {c.nombre}</h2>
   <label>Mensaje<textarea rows={2} value={mensaje} onChange={e=>setMensaje(e.target.value)}/></label>
   <div className="tb-two"><label>Cuándo<select value={disparo} onChange={e=>setDisparo(e.target.value)}><option value="inactividad">Cuando se quede quieta</option><option value="cada">Cada cierto tiempo</option></select></label>
   <label>Segundos<input type="number" min={10} value={segundos} onChange={e=>setSegundos(Number(e.target.value))}/></label>
   <label>Como mucho<input type="number" min={1} max={200} value={max} onChange={e=>setMax(Number(e.target.value))}/></label></div>
   <label>Objetivo: para solo cuando este comando salga bien (opcional)<input value={objetivo} onChange={e=>setObjetivo(e.target.value)} placeholder="npm test"/></label>
   <p className="tb-note">Nunca contesta a un permiso ni interrumpe mientras trabaja.</p>
   <div className="tb-actions"><button className="tb-secondary" onClick={onCerrar}>Cancelar</button><button className="tb-primary" disabled={!mensaje.trim()} onClick={()=>void onCrear({mensaje,disparo,segundos,objetivo,max})}><Repeat size={14}/>Empezar</button></div>
  </div></div>
 );
}
