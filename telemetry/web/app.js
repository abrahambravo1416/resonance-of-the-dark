"use strict";

const $ = id => document.getElementById(id);
const appConfig = window.RESONANCE_ARCHIVE_CONFIG || {mode:"local"};
const teamMode = appConfig.mode === "team";
const Replay = ResonanceReplay;
const sampleKinds = Replay.samples;
const playerSampleKinds = Replay.playerSamples;
const enemyColors = {patrol:"#a8a1df", investigate:"#d8b879", chase:"#ed8f85"};
const enemyStates = {patrol:"Patrulla", investigate:"Investiga", chase:"Persigue"};
const labels = {
  session_started:"Comienza la partida", session_ended:"Termina la partida", level_started:"Entra al nivel",
  level_completed:"Nivel completado", player_damaged:"Recibe daño", player_healed:"Recupera vida",
  player_died:"El jugador ha muerto", player_death:"El jugador ha muerto", player_respawned:"Vuelve a aparecer",
  item_collected:"Recoge un objeto", collectible_collected:"Recoge un coleccionable", pumpkin_collected:"Recoge una calabaza",
  bone_collected:"Recoge restos", altar_activated:"Enciende un altar", ritual_completed:"Completa un ritual",
  mission_completed:"Misión completada", quest_completed:"Misión completada", mission_started:"Comienza una misión",
  npc_interacted:"Habla con un personaje", npc_dialogue:"Conversación", npc_talked:"Habla con un personaje",
  hiding_started:"Entra a un escondite", hiding_ended:"Sale del escondite", hide_started:"Entra a un escondite", hide_ended:"Sale del escondite",
  crouch_started:"Se agacha", crouch_ended:"Se incorpora", sprint_started:"Empieza a correr", sprint_ended:"Deja de correr",
  flashlight_toggled:"Cambia la linterna", flashlight_on:"Enciende la linterna", flashlight_off:"Apaga la linterna",
  item_used:"Usa un objeto", battery_used:"Recarga la linterna", healing_used:"Usa una curación",
  enemy_state_changed:"Un enemigo cambia de conducta", enemy_attack:"Ataque enemigo", player_attacked:"El jugador ataca",
  paused:"Pausa la partida", resumed:"Reanuda la partida", menu_skipped:"Salta el menú", menu_started:"Abre el menú",
  ambient_event:"Suceso ambiental", world_event:"Suceso en el nivel", collectible_found:"Encuentra un coleccionable",
  position_sample:"Posición del jugador", position:"Posición del jugador", player_position:"Posición del jugador", movement_sample:"Posición del jugador",
  intro_skipped:"Salta la introducción", intro_shown:"Lee la introducción", intro_finished:"Termina la introducción",
  damage_taken:"Recibe daño", health_restored:"Recupera vida", relic_picked_up:"Levanta restos para el ritual",
  relic_released:"Suelta los restos", relic_delivered:"Entrega restos para el ritual", exit_unlocked:"Abre el portón de salida", jumped:"Salta", campaign_completed:"Completa la campaña",
  hiding_zone_entered:"Entra en una zona de ocultación", hiding_zone_left:"Sale de una zona de ocultación",
  hide_exit_completed:"Termina de salir del escondite", enemy_position_sample:"Posición del enemigo", enemy_removed:"El enemigo deja el nivel",
  memory_collected:"Encuentra un recuerdo", npc_spoken:"Habla con un personaje",
};
const outcomeNames = {victory:"Campaña completada",quit:"Salida del juego",finished:"Partida terminada",completed:"Completada",game_over:"Fin de la partida",window_closed:"Ventana cerrada",application_closed:"Juego cerrado",returned_to_menu:"Regresó al menú",new_run:"Inició otra partida",verification_complete:"Verificación terminada"};
const state = {sessions:[], selected:null, record:null, cursor:0, followEnd:true, playing:false, shown:100, zoom:1, pan:{x:0,y:0}, dragging:null, bounds:null, refreshBusy:false, comparisonKey:"", comparisonRevision:"", comparisonUpdatedAt:0, heatmap:null, heatmapBusy:false};
let accessToken = teamMode ? sessionStorage.getItem("resonance-team-dashboard-token") || "" : "";
const node = (tag, className, text) => {const el = document.createElement(tag);if(className)el.className=className;if(text!==undefined)el.textContent=text;return el;};
const label = kind => labels[kind] || kind.replaceAll("_", " ").replace(/^./, c => c.toUpperCase());
const date = stamp => new Date(stamp*1000);
const formatDate = stamp => date(stamp).toLocaleDateString("es-MX", {day:"2-digit",month:"short",year:"numeric"});
const formatHour = stamp => date(stamp).toLocaleTimeString("es-MX", {hour:"2-digit",minute:"2-digit",hour12:false});
const platformName = value => value === "pc" ? "PC" : value === "mobile" ? "Móvil" : "Desconocido";
function clock(seconds){const n=Math.max(0,Math.floor(seconds));return n>=3600?`${Math.floor(n/3600)}:${String(Math.floor(n/60)%60).padStart(2,"0")}:${String(n%60).padStart(2,"0")}`:`${String(Math.floor(n/60)).padStart(2,"0")}:${String(n%60).padStart(2,"0")}`;}
function duration(seconds){return seconds>=3600?`${Math.floor(seconds/3600)} h ${Math.floor(seconds/60)%60} min`:seconds>=60?`${Math.floor(seconds/60)} min ${Math.floor(seconds)%60} s`:`${Math.floor(seconds)} s`;}
const getAttempt = event => String(event.data?.attempt ?? 0);
function setConnection(online,source="Archivo"){$("connection").classList.toggle("offline",!online);$("connection").replaceChildren(node("i"),document.createTextNode(online?`${source} conectado`:"Sin conexión"));}
async function readResponse(response){let body={};try{body=await response.json();}catch{}if(!response.ok){const error=Error(body.error||"No se pudo consultar el archivo de partidas.");error.status=response.status;throw error;}return body;}
async function api(action,payload={}){
  if(!teamMode){
    const paths={health:"/api/health",sessions:"/api/sessions"};
    const path=action==="session"?`/api/sessions/${encodeURIComponent(payload.session_id)}`:action==="heatmap"?`/api/heatmap?level=${encodeURIComponent(payload.level)}&sessions=${encodeURIComponent(payload.session_ids.join(","))}`:action==="comparison"?`/api/comparison?sessions=${encodeURIComponent(payload.session_ids.join(","))}`:paths[action];
    if(!path)throw Error("Acción de archivo desconocida.");
    return readResponse(await fetch(path,{cache:"no-store"}));
  }
  if(!accessToken)throw Object.assign(Error("Inicia sesión para consultar el archivo."),{status:401});
  const response=await fetch(appConfig.dashboardApiUrl,{method:"POST",cache:"no-store",headers:{"Content-Type":"application/json","apikey":appConfig.publishableKey},body:JSON.stringify({action,session_token:accessToken,...payload})});
  return readResponse(response);
}
async function accountRequest(body,token=""){
  const headers={"Content-Type":"application/json","apikey":appConfig.publishableKey};
  return readResponse(await fetch(appConfig.accountApiUrl,{method:"POST",cache:"no-store",headers,body:JSON.stringify(token?{...body,session_token:token}:body)}));
}
function showLogin(message=""){
  $("auth-screen").hidden=!teamMode;
  $("workspace").hidden=true;
  $("logout").hidden=true;
  $("refresh").hidden=teamMode;
  if(teamMode){
    $("connection").classList.remove("offline");
    $("connection").replaceChildren(node("i"),document.createTextNode("Acceso del equipo"));
  }
  $("login-error").textContent=message;
  $("login-error").hidden=!message;
}
function showWorkspace(){
  $("auth-screen").hidden=true;
  $("workspace").hidden=false;
  $("logout").hidden=!teamMode;
  $("refresh").hidden=false;
}
function endTeamSession(){accessToken="";sessionStorage.removeItem("resonance-team-dashboard-token");}
function showError(message){$("error").textContent=message;$("error").hidden=!message;}
async function refresh(){
  if(teamMode&&!accessToken)return;
  if(state.refreshBusy)return;
  state.refreshBusy=true;
  try {
    const [result,health]=await Promise.all([api("sessions"),api("health")]);
    state.sessions=result.sessions;
    setConnection(health.ok,teamMode?"Archivo del equipo":health.database==="Supabase Postgres"?"Supabase central":"Archivo local");
    const shared=health.database==="Supabase Postgres";
    $("footer-source").textContent=shared?"Archivo compartido · sincronización automática":"Archivo local · guardado en esta computadora";
    showError(health.rejected_lines?`${health.rejected_lines} línea(s) del registro no pudieron importarse. Los eventos válidos siguen disponibles.`:health.ingestion_error?"La importación encontró un problema. Revisa la terminal del servidor.":"");
    if(!state.selected && state.sessions.length)state.selected=state.sessions[0].session_id;
    renderSessions();
    if(state.selected)await loadSelected(false);
    else {$("welcome").hidden=false;$("detail").hidden=true;}
  } catch(error){
    setConnection(false);
    if(teamMode&&(error.status===401||error.status===403)){endTeamSession();showLogin(error.message);return;}
    showError(error.message);
  }
  finally{state.refreshBusy=false;}
}
function renderSessions(){
  $("session-count").textContent=String(state.sessions.length);
  const knownPlayers=new Set(state.sessions.map(item=>item.player_id).filter(Boolean));
  $("player-count").textContent=`${knownPlayers.size} ${knownPlayers.size===1?"instalación reconocida":"instalaciones reconocidas"}`;
  const query=$("search").value.trim().toLocaleLowerCase();
  const platformFilter=$("platform-filter").value;
  const sessions=state.sessions.filter(item=>{
    const platform=item.platform||"unknown";
    const matchesPlatform=platformFilter==="all"||platform===platformFilter;
    const searchable=`${item.player_name} ${item.player_id||""} ${item.session_id} ${formatDate(item.started_at)} ${platformName(platform)}`.toLocaleLowerCase();
    return matchesPlatform&&searchable.includes(query);
  });
  const fragment=document.createDocumentFragment();
  for(const session of sessions){
    const button=node("button",`session-card${session.session_id===state.selected?" selected":""}`);button.type="button";button.setAttribute("aria-pressed",String(session.session_id===state.selected));
    const top=node("span","card-top");top.append(node("span",null,formatDate(session.started_at)),node("span",`status-dot ${session.status}`,session.status==="active"?"● En curso":session.status==="finished"?"Finalizada":"Sin actividad"));
    const playerTag=session.player_id?`Jugador ${session.player_id.slice(0,8)}`:"Jugador antiguo";
    button.append(top,node("span",`device-chip ${session.platform||"unknown"}`,platformName(session.platform)),node("strong",null,session.player_name||"Explorador"),node("small",null,`${playerTag} · ${formatHour(session.started_at)} · ${duration(session.duration)} · ${session.action_count} acciones`));
    button.addEventListener("click",async()=>{state.selected=session.session_id;state.record=null;state.playing=false;state.followEnd=true;state.shown=100;renderSessions();try{await loadSelected(true);}catch(error){showError(error.message);}});
    fragment.append(button);
  }
  if(!sessions.length)fragment.append(node("p","no-results",query?"No hay partidas que coincidan.":"Aquí aparecerán tus partidas."));
  $("sessions").replaceChildren(fragment);
}
function fillSelect(element,entries,emptyLabel,preferred){
  const old=preferred ?? element.value;
  element.replaceChildren(node("option",null,emptyLabel));element.firstChild.value="all";
  for(const [value,title] of entries){const option=node("option",null,title);option.value=String(value);element.append(option);}
  element.value=[...element.options].some(option=>option.value===String(old))?String(old):"all";
}
async function loadSelected(reset){
  const selected=state.selected;
  const result=await api("session",{session_id:selected});
  if(selected!==state.selected)return;
  const first=state.record===null || reset;
  const unchanged=!first && state.record.session.event_count===result.session.event_count && state.record.session.last_seen===result.session.last_seen && state.record.session.status===result.session.status;
  const s=result.session;
  const comparisonSessions=s.player_id?state.sessions.filter(item=>item.player_id===s.player_id).slice(0,30):[s];
  if(!comparisonSessions.some(item=>item.session_id===s.session_id)){comparisonSessions.pop();comparisonSessions.unshift(s);}
  const comparisonKey=comparisonSessions.map(item=>item.session_id).join("|");
  const comparisonRevision=comparisonSessions.map(item=>`${item.session_id}:${item.event_count||0}:${item.last_seen||0}:${item.status}`).join("|");
  const comparisonDue=Date.now()-state.comparisonUpdatedAt>=30000;
  const shouldLoadComparison=first||comparisonKey!==state.comparisonKey||(comparisonRevision!==state.comparisonRevision&&comparisonDue);
  const requestComparison=()=>{
    state.comparisonKey=comparisonKey;state.comparisonRevision=comparisonRevision;state.comparisonUpdatedAt=Date.now();
    if(first)renderAttemptComparison([],s,{loading:true});else $("comparison-count").textContent="Actualizando…";
    loadAttemptComparison(s).catch(error=>{
      if(selected!==state.selected)return;
      state.comparisonKey="";state.comparisonUpdatedAt=0;
      if(first)renderAttemptComparison([],s,{error:error.message||"No se pudieron cargar los intentos."});
      else $("comparison-count").textContent="No se pudo actualizar";
    });
  };
  if(unchanged){
    if(shouldLoadComparison)requestComparison();
    return;
  }
  state.record=result;
  // Keep expanded event details and keyboard focus while nothing has changed.
  $("welcome").hidden=true;$("detail").hidden=false;
  $("session-date").textContent=`PARTIDA DEL ${formatDate(s.started_at).toLocaleUpperCase()} · ${formatHour(s.started_at)}`;
  $("session-title").textContent=s.player_name||"Explorador";
  const matchingSessions=s.player_id?state.sessions.filter(item=>item.player_id===s.player_id).length:1;
  const playerMeta=s.player_id?`ID de instalación: ${s.player_id} · ${matchingSessions} ${matchingSessions===1?"partida":"partidas"} con este ID`:"Identidad de instalación no disponible en esta partida";
  $("session-meta").textContent=`${playerMeta} · Último registro: ${formatHour(s.last_seen)} · Partida ${s.session_id}`;
  $("session-status").textContent=s.status==="active"?"● En curso":s.status==="finished"?(outcomeNames[s.outcome]||"Finalizada"):"Sin actividad reciente";
  $("session-status").className=`badge ${s.status}`;
  $("duration").textContent=duration(s.duration);$("distance").textContent=`${s.distance.toLocaleString("es-MX",{maximumFractionDigits:1})} m`;
  $("actions").textContent=s.action_count.toLocaleString("es-MX");$("levels").textContent=String(s.level_count);
  $("session-platform").textContent=platformName(s.platform);
  renderSessionOutcome(s,result.events);
  renderObjectiveProgress(result.events);
  if(shouldLoadComparison)requestComparison();
  if(first){state.heatmap=null;setHeatmapMessage("Elige un nivel y genera el mapa para comparar partidas.");}
  $("export").href=teamMode?"#":`/api/export/${encodeURIComponent(s.session_id)}?format=csv`;
  const levels=[...new Set(result.events.map(event=>event.level).filter(level=>level>0))].sort((a,b)=>a-b);
  if(first){const activeLevel=[...result.events].reverse().find(event=>event.kind==="level_started")?.level;if(Number(activeLevel)>0)$("heatmap-level").value=String(activeLevel);}
  fillSelect($("level"),levels.map(level=>[level,`Nivel ${level}`]),"Todos los niveles",first?"all":undefined);
  fillAttempts(first);
  const kinds=[...new Set(result.events.map(event=>event.kind))].filter(kind=>!sampleKinds.has(kind)).sort((a,b)=>label(a).localeCompare(label(b)));
  fillSelect($("kind"),kinds.map(kind=>[kind,label(kind)]),"Todas las acciones",first?"all":undefined);
  $("cursor").max=String(Math.max(s.duration,.1));
  if(state.followEnd)state.cursor=s.duration;
  if(first){state.zoom=1;state.pan={x:0,y:0};}
  updateCursor();renderTimeline();drawMap();
}
async function loadAttemptComparison(session){
  const candidates=session.player_id?state.sessions.filter(item=>item.player_id===session.player_id).slice(0,30):[session];
  const selectedIndex=candidates.findIndex(item=>item.session_id===session.session_id);
  if(selectedIndex<0){candidates.pop();candidates.unshift(session);}
  const ids=candidates.map(item=>item.session_id);
  const result=await api("comparison",{session_ids:ids});
  if(state.selected!==session.session_id)return;
  renderAttemptComparison(result.events||[],session,{sessions:candidates,truncated:result.truncated});
}
function groupLevelAttempts(events,sessions){
  const groups=new Map(),latestByLevel=new Map(),sessionById=new Map(sessions.map(session=>[session.session_id,session]));
  const sorted=[...events].sort((a,b)=>String(a.session_id).localeCompare(String(b.session_id))||Number(a.seq)-Number(b.seq));
  for(const event of sorted){
    const level=Number(event.level||0);if(level<1)continue;
    const sessionId=String(event.session_id||"");const attempt=getAttempt(event);const levelKey=`${sessionId}:${level}`;let key;
    if(event.kind==="level_started"){
      key=attempt!=="0"?`${levelKey}:${attempt}`:`${levelKey}:legacy:${event.seq??groups.size}`;
      if(!groups.has(key))groups.set(key,{level,attempt,session_id:sessionId,session:sessionById.get(sessionId),events:[],initial:{},started_seq:Number(event.seq)||0});
      latestByLevel.set(levelKey,key);
    }else{
      key=attempt!=="0"?`${levelKey}:${attempt}`:latestByLevel.get(levelKey);
      if(!key)continue;
    }
    if(!groups.has(key))groups.set(key,{level,attempt,session_id:sessionId,session:sessionById.get(sessionId),events:[],initial:{},started_seq:Number(event.seq)||0});
    const group=groups.get(key);group.events.push(event);
    if(event.kind==="level_started"&&event.data?.mission_progress&&typeof event.data.mission_progress==="object")group.initial=event.data.mission_progress;
  }
  const ordered=[...groups.values()].sort((a,b)=>Number(a.session?.started_at||0)-Number(b.session?.started_at||0)||a.level-b.level||a.started_seq-b.started_seq);
  const ordinals=new Map();
  for(const group of ordered){const key=`${group.session_id}:${group.level}`;const ordinal=(ordinals.get(key)||0)+1;ordinals.set(key,ordinal);group.attempt_number=ordinal;}
  return ordered;
}
function renderAttemptComparison(events,session,{sessions=[session],truncated=false,loading=false,error=""}={}){
  const groups=groupLevelAttempts(events,sessions),body=$("comparison-rows");
  const uniqueSessions=new Set(groups.map(group=>group.session_id));
  $("comparison-count").textContent=loading?"Cargando…":`${uniqueSessions.size} ${uniqueSessions.size===1?"partida":"partidas"} · ${groups.length} ${groups.length===1?"intento":"intentos"}`;
  if(loading||!groups.length){
    body.replaceChildren();const row=node("tr");const cell=node("td","comparison-empty",loading?"Cargando intentos recientes…":error||"No hay intentos de nivel registrados todavía.");cell.colSpan=7;row.append(cell);body.append(row);return;
  }
  const rows=groups.map(group=>{
    const scoped=group.events;
    const start=scoped.find(event=>event.kind==="level_started");
    const firstElapsed=start?.elapsed??Math.min(...scoped.map(event=>event.elapsed));
    const lastElapsed=Math.max(...scoped.map(event=>event.elapsed));
    const levelEnd=scoped.find(event=>event.kind==="level_completed");
    const seconds=Math.max(0,(levelEnd?.elapsed??lastElapsed)-firstElapsed);
    const deaths=scoped.filter(event=>["player_died","player_death"].includes(event.kind)).length;
    const positions=scoped.filter(event=>playerSampleKinds.has(event.kind)&&event.position).sort((a,b)=>a.elapsed-b.elapsed||a.seq-b.seq);
    let distance=0,previous=null;
    for(const event of positions){
      if(previous&&event.elapsed-previous.elapsed<=8){const delta=Math.hypot(event.position.x-previous.position.x,event.position.z-previous.position.z);if(delta<25)distance+=delta;}
      previous=event;
    }
    const specs=objectiveFallbacks[group.level]||[];
    const objectiveTotals=specs.reduce((totals,spec)=>{const result=objectiveCounts(group,spec);totals.completed+=result.completed;totals.required+=result.total;return totals;},{completed:0,required:0});
    const progress=objectiveTotals.required?Math.round(objectiveTotals.completed/objectiveTotals.required*100):0;
    return {group,seconds,distance,deaths,progress,completed:!!levelEnd};
  });
  body.replaceChildren(...rows.map(({group,seconds,distance,deaths,progress,completed})=>{
    const row=node("tr",completed?"comparison-row is-complete":"comparison-row");
    const runLabel=group.session?`${formatDate(group.session.started_at)} · ${formatHour(group.session.started_at)}`:group.session_id.slice(0,12)||"Partida";
    row.append(node("td","comparison-run",runLabel),node("td","comparison-level",`Nivel ${group.level}`),node("td","comparison-attempt",`#${group.attempt_number}`),node("td","comparison-value",duration(seconds)),node("td","comparison-value",`${distance.toLocaleString("es-MX",{maximumFractionDigits:1})} m`),node("td",`comparison-deaths${deaths?" has-deaths":""}`,String(deaths)));
    const progressCell=node("td","comparison-progress");const track=node("span","comparison-track");const fill=node("span");fill.style.width=`${progress}%`;track.append(fill);progressCell.append(node("strong",null,`${progress}%`),track);row.append(progressCell);return row;
  }));
  if(truncated){const row=node("tr");const cell=node("td","comparison-empty","Se alcanzó el límite de eventos; se priorizaron las partidas más recientes.");cell.colSpan=7;row.append(cell);body.append(row);}
}
function setHeatmapMessage(message){$("heatmap-status").textContent=message;}
async function generateHeatmap(){
  if(state.heatmapBusy)return;
  const level=Number($("heatmap-level").value);
  const recent=state.sessions.slice(0,30).map(session=>session.session_id);
  if(state.selected&&!recent.includes(state.selected)){recent.pop();recent.unshift(state.selected);}
  if(!recent.length){setHeatmapMessage("No hay partidas registradas para comparar.");return;}
  state.heatmapBusy=true;$("heatmap-run").disabled=true;$("heatmap-run").textContent="Calculando…";
  setHeatmapMessage(`Analizando hasta ${recent.length} partidas recientes del Nivel ${level}…`);
  try{
    state.heatmap=await api("heatmap",{level,session_ids:recent});
    state.heatmap.level=level;
    drawHeatmap();
  }catch(error){state.heatmap=null;setHeatmapMessage(error.message||"No se pudo generar el mapa de calor.");drawHeatmap();}
  finally{state.heatmapBusy=false;$("heatmap-run").disabled=false;$("heatmap-run").textContent="Generar mapa";}
}
function rounded(value){return Math.round(Number(value||0)*100)/100;}
function mapLayoutSignature(event){
  const data=event.data||{},bounds=data.map_bounds||{},geometry=data.map_geometry||{};
  if(!Object.hasOwn(data,"map_geometry"))return null;
  const obstacles=(Array.isArray(geometry.obstacles)?geometry.obstacles:[]).map(item=>[rounded(item.x),rounded(item.z),rounded(item.width),rounded(item.depth),rounded(item.yaw)]).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const altars=(Array.isArray(geometry.altars)?geometry.altars:[]).map(item=>[rounded(item.x),rounded(item.z)]).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
  const mapBounds=[bounds.min_x,bounds.max_x,bounds.min_z,bounds.max_z].map(rounded);
  return JSON.stringify([event.level,mapBounds,obstacles,altars]);
}
function heatEventsForCategory(events,category){
  return events.filter(event=>{
    const data=event.data||{},kind=event.kind;
    const playerPoint=playerSampleKinds.has(kind), enemyPoint=kind==="enemy_position_sample";
    if(category==="movement")return playerPoint;
    if(category==="deaths")return ["player_died","player_death"].includes(kind);
    if(category==="chases")return (kind==="enemy_state_changed"&&String(data.state||"").toLowerCase().includes("chase"))||(enemyPoint&&String(data.state||"").toLowerCase().includes("chase"));
    if(category==="hiding")return Replay.hideKinds.has(kind)||data.hiding===true||data.hidden===true;
    if(category==="objectives")return ["pumpkin_collected","altar_activated","relic_delivered","health_skull_collected","skull_collected","item_collected","collectible_collected"].includes(kind);
    return playerPoint||enemyPoint||["player_died","player_death","enemy_state_changed","pumpkin_collected","altar_activated","relic_delivered","health_skull_collected","skull_collected","item_collected","collectible_collected"].includes(kind)||Replay.hideKinds.has(kind);
  }).filter(event=>event.position&&Number.isFinite(event.position.x)&&Number.isFinite(event.position.z));
}
function drawHeatmap(){
  const canvas=$("heatmap-canvas"),rect=canvas.getBoundingClientRect();if(!rect.width||!rect.height)return;
  const dpr=window.devicePixelRatio||1;canvas.width=Math.round(rect.width*dpr);canvas.height=Math.round(rect.height*dpr);
  const ctx=canvas.getContext("2d");ctx.scale(dpr,dpr);const w=rect.width,h=rect.height;
  ctx.clearRect(0,0,w,h);ctx.fillStyle="#0d1712";ctx.fillRect(0,0,w,h);
  const result=state.heatmap,level=Number($("heatmap-level").value),category=$("heatmap-kind").value;
  if(!result||Number(result.level)!==level){$("heatmap-empty").hidden=false;$("heatmap-sample-count").textContent="";return;}
  const allEvents=result.events||[];
  const starts=allEvents.filter(event=>event.kind==="level_started");
  const candidates=allEvents.filter(event=>Number(event.level)===level);
  const levelStarts=starts.filter(event=>Number(event.level)===level);
  const selectedStarts=levelStarts.filter(event=>event.session_id===state.selected).sort((a,b)=>Number(a.seq)-Number(b.seq));
  const selectedStart=selectedStarts.at(-1)||levelStarts.reduce((latest,event)=>!latest||Number(event.ts)>Number(latest.ts)?event:latest,null);
  if(!selectedStart){$("heatmap-empty").hidden=false;setHeatmapMessage("No hay datos de diseño de mapa para estas partidas.");return;}
  const signature=mapLayoutSignature(selectedStart);
  const matchingStarts=signature===null?[selectedStart]:starts.filter(event=>mapLayoutSignature(event)===signature);
  const compatibleKeys=new Set(matchingStarts.map(event=>`${event.session_id}:${getAttempt(event)}`));
  const compatible= candidates.filter(event=>compatibleKeys.has(`${event.session_id}:${getAttempt(event)}`));
  const points=heatEventsForCategory(compatible,category);
  const mapData=selectedStart.data||{},bounds=mapData.map_bounds||{};
  let minX=Number(bounds.min_x),maxX=Number(bounds.max_x),minZ=Number(bounds.min_z),maxZ=Number(bounds.max_z);
  if(![minX,maxX,minZ,maxZ].every(Number.isFinite)&&points.length){const limits=points.reduce((value,event)=>({minX:Math.min(value.minX,event.position.x),maxX:Math.max(value.maxX,event.position.x),minZ:Math.min(value.minZ,event.position.z),maxZ:Math.max(value.maxZ,event.position.z)}),{minX:Infinity,maxX:-Infinity,minZ:Infinity,maxZ:-Infinity});minX=limits.minX;maxX=limits.maxX;minZ=limits.minZ;maxZ=limits.maxZ;}
  if(![minX,maxX,minZ,maxZ].every(Number.isFinite)){minX=minZ=-10;maxX=maxZ=10;}
  const pad=2;minX-=pad;maxX+=pad;minZ-=pad;maxZ+=pad;
  const scale=Math.min((w-60)/(maxX-minX),(h-50)/(maxZ-minZ));
  const mapW=(maxX-minX)*scale,mapH=(maxZ-minZ)*scale,offsetX=(w-mapW)/2,offsetY=(h-mapH)/2;
  const xy=p=>({x:offsetX+(p.x-minX)*scale,y:offsetY+(p.z-minZ)*scale});
  ctx.strokeStyle="#20392c";ctx.lineWidth=1;
  for(let x=offsetX;x<=offsetX+mapW;x+=Math.max(24,scale*2)){ctx.beginPath();ctx.moveTo(x,offsetY);ctx.lineTo(x,offsetY+mapH);ctx.stroke();}
  for(let y=offsetY;y<=offsetY+mapH;y+=Math.max(24,scale*2)){ctx.beginPath();ctx.moveTo(offsetX,y);ctx.lineTo(offsetX+mapW,y);ctx.stroke();}
  const geometry=mapData.map_geometry||{};
  for(const obstacle of geometry.obstacles||[]){if(![obstacle.x,obstacle.z,obstacle.width,obstacle.depth].every(Number.isFinite))continue;const p=xy(obstacle);ctx.save();ctx.translate(p.x,p.y);ctx.rotate(-(Number(obstacle.yaw)||0));ctx.fillStyle="#2a423455";ctx.fillRect(-obstacle.width*scale/2,-obstacle.depth*scale/2,obstacle.width*scale,obstacle.depth*scale);ctx.restore();}
  for(const altar of geometry.altars||[]){const p=xy(altar);ctx.beginPath();ctx.arc(p.x,p.y,4,0,Math.PI*2);ctx.fillStyle="#b49e63";ctx.fill();}
  const bins=new Map(),resolution=1.3;
  for(const event of points){const x=Math.floor(event.position.x/resolution),z=Math.floor(event.position.z/resolution),key=`${x},${z}`;bins.set(key,(bins.get(key)||0)+1);}
  const maximum=Math.max(1,[...bins.values()].reduce((max,value)=>Math.max(max,value),0));
  for(const [key,count] of bins){const [bx,bz]=key.split(",").map(Number),p=xy({x:(bx+.5)*resolution,z:(bz+.5)*resolution});const intensity=Math.log1p(count)/Math.log1p(maximum);const color=intensity>.72?"255,75,58":intensity>.45?"255,173,57":intensity>.23?"195,217,83":"70,194,176";const radius=Math.max(10,Math.min(30,scale*1.4));const gradient=ctx.createRadialGradient(p.x,p.y,0,p.x,p.y,radius);gradient.addColorStop(0,`rgba(${color},${.48*intensity+.12})`);gradient.addColorStop(1,`rgba(${color},0)`);ctx.fillStyle=gradient;ctx.beginPath();ctx.arc(p.x,p.y,radius,0,Math.PI*2);ctx.fill();}
  $("heatmap-empty").hidden=points.length>0;
  const runCount=new Set(matchingStarts.map(event=>event.session_id)).size;
  const eventCounts={deaths:compatible.filter(event=>["player_died","player_death"].includes(event.kind)).length,chases:compatible.filter(event=>event.kind==="enemy_state_changed"&&String(event.data?.state||"").toLowerCase().includes("chase")).length,hides:compatible.filter(event=>Replay.hideKinds.has(event.kind)).length,objectives:compatible.filter(event=>["pumpkin_collected","altar_activated","relic_delivered","health_skull_collected","skull_collected","item_collected","collectible_collected"].includes(event.kind)).length};
  const kindName={all:"toda la actividad",movement:"recorridos",deaths:"derrotas",chases:"persecuciones",hiding:"escondites",objectives:"objetivos"}[category]||"actividad";
  const layoutNote=mapLayoutSignature(selectedStart)===null?" · mapa antiguo sin geometría; solo se compara esta partida":"";
  setHeatmapMessage(`${runCount} partidas compatibles · ${points.length.toLocaleString("es-MX")} puntos de ${kindName}${layoutNote}${result.truncated?" · consulta limitada a los eventos más recientes":""}.`);
  $("heatmap-sample-count").textContent=`${eventCounts.deaths} derrotas · ${eventCounts.chases} cambios a persecución · ${eventCounts.hides} cambios de escondite · ${eventCounts.objectives} objetivos`;
}
function renderSessionOutcome(session,events){
  const campaign=[...events].reverse().find(event=>event.kind==="campaign_completed");
  const deaths=events.filter(event=>event.kind==="player_died"||event.kind==="player_death").length;
  const completedLevelSet=new Set(events.filter(event=>event.kind==="level_completed"&&event.level>0).map(event=>Number(event.level)));
  for(const level of inferredPriorLevels(events))completedLevelSet.add(level);
  const completedLevels=[...completedLevelSet].sort((a,b)=>a-b);
  const outcome=session.status==="active"?"Partida en curso":outcomeNames[session.outcome]||"Partida finalizada";
  const victory=session.outcome==="victory"||!!campaign;
  const badge=$("outcome-badge");badge.textContent=victory?"CAMPAÑA COMPLETADA":session.status==="active"?"EN CURSO":session.outcome==="game_over"?"GAME OVER":"RECORRIDO CERRADO";
  badge.className=`outcome-badge ${victory?"is-victory":session.status==="active"?"is-active":"is-ended"}`;
  const finalScore=campaign?.data?.final_score;
  const hasFinalScore=finalScore!==undefined&&finalScore!==null&&Number.isFinite(Number(finalScore));
  const scoreText=hasFinalScore?Number(finalScore).toLocaleString("es-MX"):"—";
  const cards=[
    ["Resultado",outcome,victory?"El jugador llegó al final de la campaña.":session.status==="active"?"La sesión todavía está registrando actividad.":"Estado guardado al cerrar esta sesión."],
    ["Muertes",deaths.toLocaleString("es-MX"),deaths===1?"Una penalización registrada.":"Penalizaciones registradas en esta sesión."],
    ["Niveles completados",`${completedLevels.length} / 4`,completedLevels.length?`Superados: ${completedLevels.map(level=>`N${level}`).join(" · ")}`:"Todavía no hay niveles escapados."],
    ["Puntuación final",scoreText,hasFinalScore?`${Number(campaign.data.penalty_points||0).toLocaleString("es-MX")} puntos descontados por derrotas.`:"Se muestra al completar el Nivel 4."],
  ];
  const grid=$("outcome-grid");
  grid.replaceChildren(...cards.map(([title,value,note])=>{
    const card=node("article","outcome-stat");card.append(node("span","outcome-label",title),node("strong","outcome-value",value),node("small","outcome-detail",note));return card;
  }));
  const priorLevels=inferredPriorLevels(events);
  const continuationNote=priorLevels.length?` Esta sesión continúa una partida guardada; Nivel${priorLevels.length===1?"":"es"} ${priorLevels.join(", ")} ya estaba${priorLevels.length===1?"":"n"} completado${priorLevels.length===1?"":"s"}. Sus recorridos están en sesiones anteriores.`:"";
  $("outcome-note").textContent=(victory?`${Number(campaign?.data?.deaths??deaths)} ${Number(campaign?.data?.deaths??deaths)===1?"muerte":"muertes"} · puntuación de campaña calculada con las penalizaciones aplicadas.`:"El resultado y las muertes corresponden únicamente a esta sesión.")+continuationNote;
}
function inferredPriorLevels(events){
  const load=[...events].reverse().find(event=>event.kind==="saved_game_loaded");
  const currentLevel=Number(load?.data?.level||1);
  return Number.isInteger(currentLevel)?Array.from({length:Math.max(0,Math.min(4,currentLevel)-1)},(_,index)=>index+1):[];
}
const objectiveFallbacks={
  1:[{key:"altars",name:"Altares encendidos",icon:"✧",total:2}],
  2:[{key:"altars",name:"Altares encendidos",icon:"✧",total:4}],
  3:[{key:"pumpkins",name:"Calabazas recolectadas",icon:"●",total:7},{key:"altars",name:"Altares encendidos",icon:"✧",total:4}],
  4:[{key:"pumpkins",name:"Calabazas recolectadas",icon:"●",total:4},{key:"relics",name:"Restos entregados",icon:"t",total:2},{key:"altars",name:"Altares encendidos",icon:"✧",total:4}],
};
function renderObjectiveProgress(events){
  const groups=new Map(),latestByLevel=new Map();
  for(const event of events){
    const level=Number(event.level||0);if(level<1)continue;
    const attempt=getAttempt(event);let key;
    if(event.kind==="level_started"){
      key=attempt!=="0"?`${level}:${attempt}`:`${level}:legacy:${event.seq??groups.size}`;
      if(!groups.has(key))groups.set(key,{level,attempt,events:[],initial:{}});
      latestByLevel.set(level,key);
    }else{
      key=attempt!=="0"?`${level}:${attempt}`:latestByLevel.get(level);
      if(!key){key=`${level}:${attempt}`;if(!groups.has(key))groups.set(key,{level,attempt,events:[],initial:{}});}
    }
    const group=groups.get(key);if(!group)continue;group.events.push(event);
    if(event.kind==="level_started"&&event.data?.mission_progress&&typeof event.data.mission_progress==="object")group.initial=event.data.mission_progress;
  }
  const ordered=[...groups.values()];
  const loadedLevels=inferredPriorLevels(events);
  for(const level of loadedLevels){
    const existing=ordered.find(group=>group.level===level);
    if(existing&&existing.events.some(event=>event.kind==="level_completed"))continue;
    const totals={altars:level===1?2:4};
    const initial={altars:{lit:totals.altars,required:totals.altars,done:true},escape_unlocked:true};
    if(level===3)initial.pumpkins={completed:7,required:7,done:true};
    if(level===4){initial.pumpkins={completed:4,required:4,done:true};initial.absolute_ritual={delivered:2,required:2,done:true};}
    const savedProgress={level,attempt:"guardado",events:[],initial,carriedOver:true};
    if(existing)ordered[ordered.indexOf(existing)]=savedProgress;else ordered.push(savedProgress);
  }
  ordered.sort((a,b)=>a.level-b.level||String(a.attempt).localeCompare(String(b.attempt),"es",{numeric:true}));
  $("objective-attempt-count").textContent=`${ordered.length} ${ordered.length===1?"nivel":"niveles"} mostrados`;
  const container=$("objective-progress");
  if(!ordered.length){container.replaceChildren(node("p","no-results","Todavía no hay progreso de niveles en esta partida."));return;}
  container.replaceChildren(...ordered.map(renderObjectiveCard));
}
function objectiveCounts(group,spec){
  const aliases={altars:"altars",pumpkins:"pumpkins",relics:"absolute_ritual"};
  const initial=group.initial?.[aliases[spec.key]]||{};
  const initialCount=spec.key==="altars"?initial.lit:spec.key==="relics"?initial.delivered:initial.completed;
  let total=Number(initial.required)||spec.total,completed=Number(initialCount)||0,done=Boolean(initial.done);
  for(const event of group.events){
    const data=event.data||{};
    if(spec.key==="altars"&&event.kind==="altar_activated")completed=Math.max(completed,Number(data.completed)||completed+1);
    if(spec.key==="pumpkins"&&event.kind==="pumpkin_collected")completed=Math.max(completed,Number(data.collected)||completed+1);
    if(spec.key==="relics"&&event.kind==="relic_delivered")completed=Math.max(completed,Number(data.completed)||completed+1);
    if((event.kind==="mission_completed"||event.kind==="quest_completed")&&data.mission===spec.key)done=true;
    if(Number(data.required)>0&&((spec.key==="altars"&&event.kind==="altar_activated")||(spec.key==="pumpkins"&&event.kind==="pumpkin_collected")||(spec.key==="relics"&&event.kind==="relic_delivered")))total=Number(data.required);
  }
  if(done)completed=total;
  return {completed:Math.min(total,completed),total,done:done||completed>=total};
}
function renderObjectiveCard(group){
  const card=node("article","objective-card");
  const levelDone=group.carriedOver||group.events.some(event=>event.kind==="level_completed");
  const exitOpen=Boolean(group.initial?.escape_unlocked)||group.events.some(event=>event.kind==="exit_unlocked");
  const status=node("span",`objective-status ${levelDone?"is-complete":exitOpen?"is-open":"is-active"}`,group.carriedOver?"Superado antes":levelDone?"Escapó":exitOpen?"Salida abierta":"En progreso");
  const header=node("div","objective-card-heading");header.append(node("div","objective-card-title",`Nivel ${group.level}`),node("span","objective-attempt",group.carriedOver?"Progreso guardado":`Intento ${group.attempt==="0"?"—":group.attempt}`),status);card.append(header);
  const missions=objectiveFallbacks[group.level]||[];
  for(const spec of missions){
    const counts=objectiveCounts(group,spec);const percent=counts.total>0?Math.round(counts.completed/counts.total*100):0;
    const row=node("div",`objective-row key-${spec.key} ${counts.done?"is-complete":""}`);
    const line=node("div","objective-line");line.append(node("span","objective-icon",spec.icon),node("span","objective-name",spec.name),node("span","objective-count",`${counts.completed} / ${counts.total}`));
    const track=node("div","objective-track");const fill=node("span");fill.style.width=`${percent}%`;track.append(fill);
    row.append(line,track,node("small","objective-hint",counts.done?"Completado":"Progreso registrado"));card.append(row);
  }
  const escape=node("div",`objective-escape ${levelDone?"is-complete":exitOpen?"is-open":""}`);
  const escapeEvents=group.events.filter(event=>event.kind==="exit_unlocked"||event.kind==="level_completed");
  const escapeEvent=escapeEvents.at(-1);
  const escapeStatus=levelDone?"Salida cruzada":exitOpen?"Portón abierto":"Pendiente";
  escape.append(node("span",null,"Salida"),node("strong",null,group.carriedOver?"Cruzada en sesión anterior":escapeStatus),node("small",null,escapeEvent?clock(escapeEvent.elapsed):group.carriedOver?"Antes de esta sesión":"Completa los objetivos del nivel"));card.append(escape);
  return card;
}
function fillAttempts(reset=false){
  if(!state.record)return;
  const matching=state.record.events.filter(event=>$("level").value==="all"||String(event.level)===$("level").value);
  const attempts=[...new Set(matching.map(getAttempt))].filter(attempt=>attempt!=="0").sort((a,b)=>Number(a)-Number(b));
  fillSelect($("attempt"),attempts.map(attempt=>[attempt,`Intento ${attempt}`]),"Todos los intentos",reset?"all":undefined);
}
function filteredEvents(){return (state.record?.events||[]).filter(event=>($("level").value==="all"||String(event.level)===$("level").value)&&($("attempt").value==="all"||getAttempt(event)===$("attempt").value));}
function activityEvents(){return filteredEvents().filter(event=>($("samples").checked||!sampleKinds.has(event.kind))&&($("kind").value==="all"||event.kind===$("kind").value));}
function describe(event){
  const d=event.data||{};
  if(event.kind==="session_started")return d.game_version?`Versión ${d.game_version}`:"";
  if(event.kind==="session_ended")return outcomeNames[d.outcome]||d.outcome||"";
  if(event.kind==="level_started")return d.title||d.scene||"";
  if(event.kind==="enemy_state_changed" || event.kind==="enemy_position_sample")return `${d.enemy||d.enemy_id||"Enemigo"} · ${enemyStates[d.state]||d.state||""}`;
  if(event.kind==="mission_completed")return {pumpkins:"Reunir calabazas",altars:"Encender los altares",relics:"Llevar restos al ritual"}[d.mission]||d.mission||"";
  if(sampleKinds.has(event.kind))return [d.running?"Corriendo":"Caminando",d.hidden?"Oculto":"",d.crouching?"Agachado":"",d.health!==undefined?`Vida ${d.health}`:""].filter(Boolean).join(" · ");
  return [d.item||d.item_name||d.npc||d.npc_name||d.title||d.name||d.node||d.object||d.cover||"",d.message||d.text||d.dialogue||d.line||"",d.collected!==undefined?`Reunidos: ${d.collected}${d.required!==undefined?` / ${d.required}`:""}`:"",d.amount!==undefined?`Cantidad: ${d.amount}`:"",d.damage!==undefined?`Daño: ${d.damage}`:"",d.health!==undefined?`Vida: ${d.health}`:""].filter(Boolean).map(String).join(" · ");
}
function symbol(kind){if(kind.includes("damage")||kind.includes("died")||kind.includes("death"))return"×";if(kind.includes("collect")||kind.includes("item"))return"◇";if(kind.includes("altar")||kind.includes("ritual"))return"✧";if(kind.includes("npc")||kind.includes("dialogue"))return"◌";if(kind.includes("hide")||kind.includes("hiding"))return"◐";if(sampleKinds.has(kind))return"·";return"↗";}
function renderTimeline(){
  const events=activityEvents();
  $("event-count").textContent=`${events.length.toLocaleString("es-MX")} registros`;
  const fragment=document.createDocumentFragment();
  for(const event of events.slice(0,state.shown)){
    const row=node("article","event-row");const timeButton=node("button","event-time",clock(event.elapsed));timeButton.title="Ver este momento en el recorrido";
    timeButton.addEventListener("click",()=>{state.followEnd=false;state.playing=false;state.cursor=event.elapsed;updateCursor();drawMap();});
    const copy=node("div","event-copy");copy.append(node("strong",null,label(event.kind)));const description=describe(event);if(description)copy.append(node("p",null,description));
    const detail=node("details");detail.append(node("summary",null,"Ver datos del evento"),node("pre",null,JSON.stringify({tipo:event.kind,posicion:event.position,datos:event.data},null,2)));copy.append(detail);
    row.append(timeButton,node("span","event-symbol",symbol(event.kind)),copy,node("span","event-level",event.level?`NIVEL ${event.level}`:"MENÚ"));fragment.append(row);
  }
  if(!events.length)fragment.append(node("p","no-results","No hay acciones para estos filtros. Prueba otro nivel o actividad."));
  $("timeline").replaceChildren(fragment);$("more").hidden=events.length<=state.shown;
}
function updateCursor(){
  $("cursor").value=String(state.cursor);$("cursor-time").textContent=clock(state.cursor);$("total-time").textContent=clock(state.record?.session.duration||0);
  $("play").textContent=state.playing?"Ⅱ":"▶";$("play").setAttribute("aria-label",state.playing?"Pausar recorrido":"Reproducir recorrido");
}
function mapBounds(events){
  const starts=events.filter(event=>event.kind==="level_started"&&event.data?.map_bounds);
  let minX=Infinity,maxX=-Infinity,minZ=Infinity,maxZ=-Infinity;
  for(const event of starts){const b=event.data.map_bounds;if([b.min_x,b.max_x,b.min_z,b.max_z].every(Number.isFinite)){minX=Math.min(minX,b.min_x);maxX=Math.max(maxX,b.max_x);minZ=Math.min(minZ,b.min_z);maxZ=Math.max(maxZ,b.max_z);}}
  for(const event of events){if(sampleKinds.has(event.kind)&&event.position){minX=Math.min(minX,event.position.x);maxX=Math.max(maxX,event.position.x);minZ=Math.min(minZ,event.position.z);maxZ=Math.max(maxZ,event.position.z);}}
  if(!Number.isFinite(minX))return {minX:-10,maxX:10,minZ:-10,maxZ:10};
  const pad=Math.max(2,Math.max(maxX-minX,maxZ-minZ)*.08);return {minX:minX-pad,maxX:maxX+pad,minZ:minZ-pad,maxZ:maxZ+pad};
}
function drawMap(){
  const canvas=$("map");const rect=canvas.getBoundingClientRect();if(!rect.width||!rect.height)return;
  const dpr=window.devicePixelRatio||1;canvas.width=Math.round(rect.width*dpr);canvas.height=Math.round(rect.height*dpr);
  const ctx=canvas.getContext("2d");ctx.scale(dpr,dpr);
  const replay=Replay.at(state.record?.events||[],state.cursor,{level:$("level").value,attempt:$("attempt").value});
  const w=rect.width,h=rect.height,events=replay.events,samples=events.filter(event=>playerSampleKinds.has(event.kind)&&event.position);
  const b=mapBounds(events);state.bounds=b;
  const scale=Math.min((w-66)/Math.max(b.maxX-b.minX,1),(h-56)/Math.max(b.maxZ-b.minZ,1))*state.zoom;
  const centerX=(b.minX+b.maxX)/2,centerZ=(b.minZ+b.maxZ)/2;
  const xy=p=>({x:w/2+(p.x-centerX)*scale+state.pan.x,y:h/2+(p.z-centerZ)*scale+state.pan.y});
  $("map-empty").hidden=!!replay.player || replay.enemies.length>0;
  $("map-points").textContent=`${samples.length} ${samples.length===1?"posición":"posiciones"} del jugador`;
  $("map-context").textContent=replay.context?`Nivel ${replay.context.level} · Intento ${replay.context.attempt}${replay.paused?" · En pausa":""}`:"Sin nivel en este momento";
  const hidden=replay.player?.hidden;
  $("player-state").classList.toggle("is-hidden",!!hidden);
  $("player-state").textContent=replay.player?(hidden?"◐ Oculto":"● Visible"):"Sin posición";
  $("player-state").title=hidden?(replay.player.cover||"Oculto en el escenario"):"";
  $("map").setAttribute("aria-label",`${$("map-context").textContent}. Jugador ${replay.player?(hidden?"oculto":"visible"):"sin posición registrada"}. ${replay.enemies.length} enemigos registrados en este momento.`);
  renderEnemyList(replay);
  renderHiddenIntervals(replay.hiddenIntervals);
  const rawGrid=Math.max((b.maxX-b.minX)/12,1), magnitude=Math.pow(10,Math.floor(Math.log10(rawGrid)));
  const grid=magnitude*([1,2,5,10].find(step=>step*magnitude>=rawGrid)||10);
  ctx.lineWidth=1;ctx.strokeStyle="#25433470";
  for(let x=Math.ceil(b.minX/grid)*grid;x<=b.maxX;x+=grid){const p=xy({x,z:centerZ});ctx.beginPath();ctx.moveTo(p.x,0);ctx.lineTo(p.x,h);ctx.stroke();}
  for(let z=Math.ceil(b.minZ/grid)*grid;z<=b.maxZ;z+=grid){const p=xy({x:centerX,z});ctx.beginPath();ctx.moveTo(0,p.y);ctx.lineTo(w,p.y);ctx.stroke();}
  const metadata=events.findLast(event=>event.kind==="level_started"&&event.data?.map_geometry);
  if(metadata){
    for(const obstacle of metadata.data.map_geometry.obstacles||[]){if(![obstacle.x,obstacle.z,obstacle.width,obstacle.depth].every(Number.isFinite))continue;const p=xy(obstacle);ctx.save();ctx.translate(p.x,p.y);ctx.rotate(-(Number(obstacle.yaw)||0));ctx.fillStyle="#2b443480";ctx.strokeStyle="#52634a70";ctx.fillRect(-obstacle.width*scale/2,-obstacle.depth*scale/2,obstacle.width*scale,obstacle.depth*scale);ctx.strokeRect(-obstacle.width*scale/2,-obstacle.depth*scale/2,obstacle.width*scale,obstacle.depth*scale);ctx.restore();}
    for(const altar of metadata.data.map_geometry.altars||[]){const p=xy(altar);ctx.beginPath();ctx.arc(p.x,p.y,6,0,Math.PI*2);ctx.strokeStyle="#8e845780";ctx.lineWidth=1;ctx.stroke();ctx.fillStyle="#a99b68";ctx.font="8px ui-sans-serif, sans-serif";ctx.fillText(altar.name||"Altar",p.x+10,p.y+3);}
  }
  // Draw only the history already reached by the cursor. Hidden portions remain distinct.
  ctx.lineJoin="round";ctx.lineCap="round";ctx.lineWidth=2.2;
  for(let i=1;i<replay.route.length;i++){
    const previous=replay.route[i-1],next=replay.route[i],a=xy(previous.position),b=xy(next.position);
    ctx.strokeStyle=previous.hidden?"#8bcde1":"#c5c98d";ctx.setLineDash(previous.hidden?[4,4]:[]);
    ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();
  }
  ctx.setLineDash([]);
  const actions=events.filter(event=>!sampleKinds.has(event.kind)&&event.position&&($("kind").value==="all"||event.kind===$("kind").value));
  for(const event of actions){const p=xy(event.position);ctx.save();ctx.translate(p.x,p.y);ctx.rotate(Math.PI/4);ctx.fillStyle=event.kind.includes("enemy")?"#a071655e":"#c6a96a99";ctx.fillRect(-2.5,-2.5,5,5);ctx.restore();}
  function dot(point,color,radius,glow=false){if(!point)return;const p=xy(point.position);ctx.beginPath();ctx.arc(p.x,p.y,radius,0,Math.PI*2);ctx.fillStyle=color;if(glow){ctx.shadowColor=color;ctx.shadowBlur=15;}ctx.fill();ctx.shadowBlur=0;ctx.lineWidth=2;ctx.strokeStyle="#11221a";ctx.stroke();}
  dot(samples[0],"#81c6a9",4);
  if($("enemies").checked)for(const enemy of replay.enemies){
    const p=xy(enemy.position),color=enemyColors[enemy.state]||enemyColors.patrol;
    ctx.save();ctx.translate(p.x,p.y);ctx.rotate(-enemy.yaw);
    ctx.fillStyle=color;ctx.strokeStyle="#11191a";ctx.lineWidth=2;
    ctx.beginPath();ctx.moveTo(0,-8);ctx.lineTo(6,6);ctx.lineTo(0,3);ctx.lineTo(-6,6);ctx.closePath();ctx.fill();ctx.stroke();ctx.restore();
    ctx.font="bold 10px ui-sans-serif, sans-serif";ctx.lineWidth=3;ctx.strokeStyle="#0e1813";ctx.strokeText(enemy.label,p.x+10,p.y+3);ctx.fillStyle=color;ctx.fillText(enemy.label,p.x+10,p.y+3);
  }
  dot(replay.player,hidden?"#8bcde1":"#ebefd2",5,true);
  if(hidden){
    const p=xy(replay.player.position);ctx.strokeStyle="#8bcde1";ctx.lineWidth=1.5;ctx.setLineDash([3,3]);ctx.beginPath();ctx.arc(p.x,p.y,11,0,Math.PI*2);ctx.stroke();ctx.setLineDash([]);
    ctx.font="bold 9px ui-sans-serif, sans-serif";ctx.textAlign="center";ctx.strokeStyle="#0e1813";ctx.lineWidth=3;ctx.strokeText("OCULTO",p.x,p.y-18);ctx.fillStyle="#a5dceb";ctx.fillText("OCULTO",p.x,p.y-18);ctx.textAlign="left";
  }
  ctx.fillStyle="#647f6c";ctx.font="8px ui-monospace, monospace";ctx.fillText(`${Math.round(b.minX)}, ${Math.round(b.minZ)}`,12,18);
}
function renderEnemyList(replay){
  const visible=$("enemies").checked;$("enemy-list").hidden=!visible;
  const hasEnemyRecording=state.record?.events.some(event=>event.kind==="enemy_position_sample");
  $("enemy-count").textContent=replay.enemySamples?`${replay.enemies.length} enemigos en este momento${visible?"":" · Ocultos en el plano"}`:hasEnemyRecording?"Aún no hay posiciones enemigas hasta este momento.":"Esta partida no contiene posiciones enemigas; las partidas antiguas no las registraban.";
  const fragment=document.createDocumentFragment();
  for(const enemy of replay.enemies){const item=node("span",`enemy-chip ${["patrol","investigate","chase"].includes(enemy.state)?enemy.state:"patrol"}`,`${enemy.label} · ${enemy.name} · ${enemyStates[enemy.state]||enemy.state}`);item.title=enemy.id;fragment.append(item);}
  $("enemy-list").replaceChildren(fragment);
}
function renderHiddenIntervals(intervals){
  const total=Math.max(state.record?.session.duration||0,.1),fragment=document.createDocumentFragment();
  for(const interval of intervals){const item=node("span");item.style.left=`${interval.start/total*100}%`;item.style.width=`${Math.max(.15,(interval.end-interval.start)/total*100)}%`;item.title=`Oculto ${clock(interval.start)}–${clock(interval.end)}`;fragment.append(item);}
  $("hide-periods").replaceChildren(fragment);
  $("hide-periods").setAttribute("aria-label",intervals.length?intervals.map(interval=>`Oculto de ${clock(interval.start)} a ${clock(interval.end)}`).join(". "):"Sin ocultación en el tramo reproducido");
}

function csvValue(value){
  let text=value===null||value===undefined?"":String(value);
  if(/^[=+\-@\t\r]/.test(text))text="'"+text;
  return `"${text.replaceAll('"','""')}"`;
}
function downloadTeamCsv(event){
  if(!teamMode)return;
  event.preventDefault();
  if(!state.record)return;
  const columns=["event_id","session_id","seq","kind","ts","elapsed","level","x","y","z","data_json"];
  const lines=[columns.map(csvValue).join(",")];
  for(const item of state.record.events){
    const pos=item.position||{};
    const values=[item.event_id,item.session_id,item.seq,item.kind,item.ts,item.elapsed,item.level,pos.x,pos.y,pos.z,JSON.stringify(item.data||{})];
    lines.push(values.map(csvValue).join(","));
  }
  const blob=new Blob(["\uFEFF",lines.join("\r\n")],{type:"text/csv;charset=utf-8"});
  const url=URL.createObjectURL(blob),link=document.createElement("a");
  link.href=url;link.download="resonance-partida.csv";document.body.append(link);link.click();link.remove();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
}
async function signIn(event){
  event.preventDefault();
  const submit=$("login-submit"),username=$("login-username").value.trim().toLowerCase(),password=$("login-password").value;
  submit.disabled=true;submit.textContent="CONECTANDO…";$("login-error").hidden=true;
  try{
    const result=await accountRequest({action:"login",username,password});
    const token=result.session?.session_token;
    if(typeof token!=="string")throw Error("No se recibió una sesión válida.");
    accessToken=token;
    await api("health");
    sessionStorage.setItem("resonance-team-dashboard-token",token);
    $("login-password").value="";showWorkspace();showError("");await refresh();
  }catch(error){
    accessToken="";
    const message=error.status===403?"La cuenta inició sesión, pero todavía no está autorizada para ver el archivo del equipo. Pide al administrador que habilite este ID.":error.message;
    showLogin(message);
  }finally{submit.disabled=false;submit.textContent="INICIAR SESIÓN";}
}
async function signOut(){
  const token=accessToken;
  try{if(token)await accountRequest({action:"logout"},token);}catch{}
  endTeamSession();state.sessions=[];state.selected=null;state.record=null;renderSessions();showLogin();
  setConnection(false,"Archivo del equipo");
}
async function initializeArchive(){
  if(!teamMode){showWorkspace();await refresh();return;}
  showLogin();
  if(!accessToken)return;
  try{await api("health");showWorkspace();await refresh();}
  catch(error){
    if(error.status===401||error.status===403)endTeamSession();
    showLogin(error.status===403?"Esta cuenta no tiene acceso autorizado al archivo del equipo.":error.status===401?"La sesión caducó. Inicia sesión de nuevo.":"No se pudo conectar. Comprueba tu conexión e inicia sesión.");
  }
}

$("refresh").addEventListener("click",refresh);$("search").addEventListener("input",renderSessions);$("platform-filter").addEventListener("change",renderSessions);
$("login-form").addEventListener("submit",signIn);$("logout").addEventListener("click",signOut);$("export").addEventListener("click",downloadTeamCsv);
$("level").addEventListener("change",()=>{fillAttempts(true);state.shown=100;state.zoom=1;state.pan={x:0,y:0};renderTimeline();drawMap();});
$("attempt").addEventListener("change",()=>{state.shown=100;state.zoom=1;state.pan={x:0,y:0};renderTimeline();drawMap();});
for(const id of ["kind","samples"])$(id).addEventListener("change",()=>{state.shown=100;renderTimeline();drawMap();});
$("enemies").addEventListener("change",drawMap);
$("heatmap-run").addEventListener("click",generateHeatmap);
$("heatmap-level").addEventListener("change",()=>{state.heatmap=null;setHeatmapMessage("Genera de nuevo el mapa para este nivel.");drawHeatmap();});
$("heatmap-kind").addEventListener("change",drawHeatmap);
$("more").addEventListener("click",()=>{state.shown+=100;renderTimeline();});
$("cursor").addEventListener("input",()=>{state.followEnd=false;state.playing=false;state.cursor=Number($("cursor").value);updateCursor();drawMap();});
$("play").addEventListener("click",()=>{state.playing=!state.playing;state.followEnd=false;if(state.cursor>=(state.record?.session.duration||0))state.cursor=0;updateCursor();});
$("live").addEventListener("click",()=>{state.followEnd=true;state.playing=false;state.cursor=state.record?.session.duration||0;updateCursor();drawMap();});
function zoom(factor){state.zoom=Math.min(12,Math.max(.6,state.zoom*factor));drawMap();}
$("zoom-in").addEventListener("click",()=>zoom(1.3));$("zoom-out").addEventListener("click",()=>zoom(1/1.3));
$("fit").addEventListener("click",()=>{state.zoom=1;state.pan={x:0,y:0};drawMap();});
$("map").addEventListener("wheel",event=>{event.preventDefault();zoom(event.deltaY<0?1.12:1/1.12);},{passive:false});
$("map").addEventListener("pointerdown",event=>{state.dragging={x:event.clientX,y:event.clientY};$("map").setPointerCapture(event.pointerId);});
$("map").addEventListener("pointermove",event=>{if(!state.dragging)return;state.pan.x+=event.clientX-state.dragging.x;state.pan.y+=event.clientY-state.dragging.y;state.dragging={x:event.clientX,y:event.clientY};drawMap();});
$("map").addEventListener("pointerup",()=>{state.dragging=null;});$("map").addEventListener("pointercancel",()=>{state.dragging=null;});
new ResizeObserver(drawMap).observe($("map"));
new ResizeObserver(drawHeatmap).observe($("heatmap-canvas"));
setInterval(()=>{if(!state.playing||!state.record)return;state.cursor=Math.min(state.cursor+.25,state.record.session.duration);if(state.cursor>=state.record.session.duration)state.playing=false;updateCursor();drawMap();},100);
setInterval(()=>{if(!document.hidden)refresh();},5000);
document.addEventListener("visibilitychange",()=>{if(!document.hidden)refresh();});
initializeArchive();
