import { withSupabase } from "npm:@supabase/server@1";

const PAGE_SIZE = 1000;
const MAX_REQUEST_BYTES = 4096;
const MAX_HEATMAP_SESSIONS = 30;
const MAX_HEATMAP_EVENTS = 20000;
const SAMPLE_KINDS = new Set([
  "position", "position_sample", "player_position", "movement_sample", "enemy_position_sample",
]);
const HEATMAP_KINDS = [
  ...SAMPLE_KINDS, "level_started", "player_died", "player_death", "enemy_state_changed",
  "hiding_started", "hiding_ended", "hiding_zone_entered", "hiding_zone_left",
  "hide_started", "hide_ended", "hide_exit_completed", "pumpkin_collected",
  "altar_activated", "relic_delivered", "health_skull_collected", "skull_collected",
  "item_collected", "collectible_collected",
];
const COMPARISON_KINDS = [
  "position", "position_sample", "player_position", "movement_sample", "level_started",
  "level_completed", "player_died", "player_death", "pumpkin_collected", "altar_activated",
  "relic_delivered", "item_collected", "collectible_collected", "mission_completed",
  "quest_completed", "exit_unlocked",
];

type JsonRecord = Record<string, unknown>;

function jsonResponse(body: JsonRecord, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function authorize(body: JsonRecord, admin: any): Promise<boolean> {
  const token = typeof body.session_token === "string" ? body.session_token : "";
  if (!/^[a-f0-9]{64}$/i.test(token)) return false;

  const tokenHash = await sha256(token);
  const { data: session, error: sessionError } = await admin
    .from("game_account_sessions")
    .select("account_id")
    .eq("token_hash", tokenHash)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (sessionError || !session?.account_id) return false;

  const { data: viewer, error: viewerError } = await admin
    .from("game_dashboard_viewers")
    .select("account_id")
    .eq("account_id", session.account_id)
    .maybeSingle();
  return !viewerError && Boolean(viewer?.account_id);
}

async function fetchAll(makeQuery: (start: number, end: number) => any): Promise<JsonRecord[]> {
  const rows: JsonRecord[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error } = await makeQuery(offset, offset + PAGE_SIZE - 1);
    if (error) throw new Error("No se pudo consultar el archivo de partidas.");
    const page = (data ?? []) as JsonRecord[];
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

function withStatus(row: JsonRecord): JsonRecord {
  const endedAt = row.ended_at;
  const lastSeen = Number(row.last_seen ?? 0);
  const status = endedAt !== null
    ? "finished"
    : (Date.now() / 1000 - lastSeen < 45 ? "active" : "inactive");
  return { ...row, status };
}

async function health(admin: any): Promise<JsonRecord> {
  const [sessions, events] = await Promise.all([
    admin.from("game_session_summary").select("session_id", { count: "exact", head: true }),
    admin.from("game_events").select("event_id", { count: "exact", head: true }),
  ]);
  if (sessions.error || events.error) throw new Error("No se pudo consultar el archivo de partidas.");
  return {
    ok: true,
    database: "Supabase Postgres",
    schema_version: 1,
    session_count: sessions.count ?? 0,
    event_count: events.count ?? 0,
    rejected_lines: 0,
    ingestion_error: null,
  };
}

async function getSessions(admin: any): Promise<JsonRecord[]> {
  const rows = await fetchAll((start, end) => admin
    .from("game_session_summary")
    .select("*")
    .order("started_at", { ascending: false })
    .range(start, end));
  return rows.map(withStatus);
}

async function getSession(admin: any, sessionId: string): Promise<JsonRecord | null> {
  const { data: summary, error } = await admin
    .from("game_session_summary")
    .select("*")
    .eq("session_id", sessionId)
    .maybeSingle();
  if (error) throw new Error("No se pudo consultar la partida.");
  if (!summary) return null;

  const rows = await fetchAll((start, end) => admin
    .from("game_events")
    .select("event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data")
    .eq("session_id", sessionId)
    .order("seq", { ascending: true })
    .order("ts", { ascending: true })
    .range(start, end));
  const events = rows.map((row) => ({
    event_id: row.event_id,
    session_id: row.session_id,
    seq: row.seq,
    kind: row.kind,
    ts: row.ts,
    elapsed: row.elapsed,
    level: row.level,
    position: row.x !== null && row.y !== null && row.z !== null
      ? { x: row.x, y: row.y, z: row.z }
      : null,
    data: row.data ?? {},
  }));
  const session = withStatus(summary);
  session.action_count = events.filter((event) => !SAMPLE_KINDS.has(String(event.kind))).length;
  return { session, events };
}

async function getHeatmapEvents(admin: any, sessionIds: string[], level: number): Promise<JsonRecord> {
  const events: JsonRecord[] = [];
  let offset = 0;
  while (events.length <= MAX_HEATMAP_EVENTS) {
    const limit = Math.min(PAGE_SIZE, MAX_HEATMAP_EVENTS + 1 - events.length);
    const { data, error } = await admin
      .from("game_events")
      .select("event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data")
      .in("session_id", sessionIds)
      .eq("level", level)
      .in("kind", HEATMAP_KINDS)
      .order("session_id", { ascending: false })
      .order("seq", { ascending: true })
      .order("ts", { ascending: true })
      .range(offset, offset + limit - 1);
    if (error) throw new Error("No se pudieron consultar los datos para el mapa de calor.");
    const page = (data ?? []) as JsonRecord[];
    events.push(...page);
    if (page.length < limit) break;
    offset += page.length;
  }
  const truncated = events.length > MAX_HEATMAP_EVENTS;
  return {
    truncated,
    events: events.slice(0, MAX_HEATMAP_EVENTS).map((row) => ({
      event_id: row.event_id,
      session_id: row.session_id,
      seq: row.seq,
      kind: row.kind,
      ts: row.ts,
      elapsed: row.elapsed,
      level: row.level,
      position: row.x !== null && row.y !== null && row.z !== null
        ? { x: row.x, y: row.y, z: row.z }
        : null,
      data: row.data ?? {},
    })),
  };
}

async function getComparisonEvents(admin: any, sessionIds: string[]): Promise<JsonRecord> {
  const events: JsonRecord[] = [];
  let offset = 0;
  while (events.length <= MAX_HEATMAP_EVENTS) {
    const limit = Math.min(PAGE_SIZE, MAX_HEATMAP_EVENTS + 1 - events.length);
    const { data, error } = await admin
      .from("game_events")
      .select("event_id,session_id,seq,kind,ts,elapsed,level,x,y,z,data")
      .in("session_id", sessionIds)
      .in("kind", COMPARISON_KINDS)
      .order("session_id", { ascending: false })
      .order("seq", { ascending: true })
      .order("ts", { ascending: true })
      .range(offset, offset + limit - 1);
    if (error) throw new Error("No se pudieron consultar los intentos del jugador.");
    const page = (data ?? []) as JsonRecord[];
    events.push(...page);
    if (page.length < limit) break;
    offset += page.length;
  }
  const truncated = events.length > MAX_HEATMAP_EVENTS;
  return {
    truncated,
    events: events.slice(0, MAX_HEATMAP_EVENTS).map((row) => ({
      event_id: row.event_id,
      session_id: row.session_id,
      seq: row.seq,
      kind: row.kind,
      ts: row.ts,
      elapsed: row.elapsed,
      level: row.level,
      position: row.x !== null && row.y !== null && row.z !== null
        ? { x: row.x, y: row.y, z: row.z }
        : null,
      data: row.data ?? {},
    })),
  };
}

async function handleRequest(request: Request, admin: any): Promise<Response> {
  if (request.method !== "POST") return jsonResponse({ ok: false, error: "Método no permitido." }, 405);
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_REQUEST_BYTES) return jsonResponse({ ok: false, error: "Solicitud demasiado grande." }, 413);

  let body: unknown;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ ok: false, error: "Solicitud demasiado grande." }, 413);
    }
    body = JSON.parse(raw);
  } catch {
    return jsonResponse({ ok: false, error: "JSON inválido." }, 400);
  }
  if (!isRecord(body) || typeof body.action !== "string") {
    return jsonResponse({ ok: false, error: "Acción no válida." }, 400);
  }

  if (!await authorize(body, admin)) {
    return jsonResponse({ ok: false, error: "La sesión no tiene permiso para consultar el archivo del equipo." }, 403);
  }

  if (body.action === "health") return jsonResponse(await health(admin));
  if (body.action === "sessions") return jsonResponse({ sessions: await getSessions(admin) });
  if (body.action === "heatmap") {
    const rawIds = body.session_ids;
    const level = Number(body.level);
    if (!Array.isArray(rawIds) || rawIds.length < 1 || rawIds.length > MAX_HEATMAP_SESSIONS ||
      rawIds.some((value) => typeof value !== "string" || !/^[A-Za-z0-9_-]{1,100}$/.test(value))) {
      return jsonResponse({ ok: false, error: "Selecciona hasta 30 partidas válidas." }, 400);
    }
    if (!Number.isInteger(level) || level < 1 || level > 4) {
      return jsonResponse({ ok: false, error: "Nivel inválido para el mapa de calor." }, 400);
    }
    return jsonResponse(await getHeatmapEvents(admin, [...new Set(rawIds)], level));
  }
  if (body.action === "comparison") {
    const rawIds = body.session_ids;
    if (!Array.isArray(rawIds) || rawIds.length < 1 || rawIds.length > MAX_HEATMAP_SESSIONS ||
      rawIds.some((value) => typeof value !== "string" || !/^[A-Za-z0-9_-]{1,100}$/.test(value))) {
      return jsonResponse({ ok: false, error: "Selecciona hasta 30 partidas válidas." }, 400);
    }
    return jsonResponse(await getComparisonEvents(admin, [...new Set(rawIds)]));
  }
  if (body.action === "session") {
    if (typeof body.session_id !== "string" || body.session_id.length < 1 || body.session_id.length > 200) {
      return jsonResponse({ ok: false, error: "Identificador de partida inválido." }, 400);
    }
    const record = await getSession(admin, body.session_id);
    return record ? jsonResponse(record) : jsonResponse({ error: "La partida no existe." }, 404);
  }
  return jsonResponse({ ok: false, error: "Acción desconocida." }, 400);
}

export default {
  fetch: withSupabase({ auth: "publishable" }, async (request, context) => {
    try {
      return await handleRequest(request, context.supabaseAdmin);
    } catch (error) {
      console.error("Team dashboard request failed", error instanceof Error ? error.message : "unknown error");
      return jsonResponse({ ok: false, error: "No se pudo consultar el archivo del equipo." }, 503);
    }
  }),
};
