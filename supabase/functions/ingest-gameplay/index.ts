import { withSupabase } from "npm:@supabase/server@1";

const MAX_BODY_BYTES = 1024 * 1024;
const MAX_EVENTS = 100;
const MAX_EVENT_JSON_BYTES = 512 * 1024;

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function validateEvent(value: unknown): Record<string, unknown> | null {
  if (!isRecord(value)) return null;
  const { event_id, session_id, seq, kind, ts, elapsed, level, position, data } = value;
  if (typeof event_id !== "string" || event_id.length < 1 || event_id.length > 200) return null;
  if (typeof session_id !== "string" || session_id.length < 1 || session_id.length > 200) return null;
  if (typeof seq !== "number" || !Number.isSafeInteger(seq) || seq < 0) return null;
  if (typeof kind !== "string" || kind.length < 1 || kind.length > 100) return null;
  if (!isFiniteNumber(ts) || ts < 0 || !isFiniteNumber(elapsed) || elapsed < 0) return null;
  if (typeof level !== "number" || !Number.isSafeInteger(level) || level < 0 || level > 100000) return null;
  if (!isRecord(data)) return null;
  if (new TextEncoder().encode(JSON.stringify(data)).byteLength > MAX_EVENT_JSON_BYTES) return null;

  let safePosition: Record<string, number> | null = null;
  if (position !== undefined && position !== null) {
    if (!isRecord(position)) return null;
    const x = position.x;
    const y = position.y;
    const z = position.z;
    if (!isFiniteNumber(x) || !isFiniteNumber(y) || !isFiniteNumber(z)) return null;
    safePosition = { x, y, z };
  }

  return {
    event_id,
    session_id,
    seq,
    kind,
    ts,
    elapsed,
    level,
    position: safePosition,
    data,
  };
}

export default {
  fetch: withSupabase({ auth: "publishable" }, async (request, context) => {
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_BODY_BYTES) return jsonResponse({ error: "Payload too large" }, 413);

    let body: unknown;
    try {
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) return jsonResponse({ error: "Payload too large" }, 413);
      body = JSON.parse(raw);
    } catch {
      return jsonResponse({ error: "Invalid JSON" }, 400);
    }
    if (!isRecord(body) || !Array.isArray(body.events) || body.events.length < 1 || body.events.length > MAX_EVENTS) {
      return jsonResponse({ error: `events must contain 1 to ${MAX_EVENTS} entries` }, 400);
    }

    const events: Record<string, unknown>[] = [];
    for (const item of body.events) {
      const event = validateEvent(item);
      if (!event) return jsonResponse({ error: "Invalid event payload" }, 400);
      events.push(event);
    }

    const { data, error } = await context.supabaseAdmin.rpc("ingest_gameplay_batch", { p_events: events });
    if (error) {
      console.error("Gameplay batch insert failed", error.message);
      return jsonResponse({ error: "Could not store gameplay batch" }, 503);
    }
    return jsonResponse({ ok: true, accepted: Number(data?.accepted ?? 0) });
  }),
};
