import { withSupabase } from "npm:@supabase/server@1";
import bcrypt from "npm:bcryptjs@2.4.3";

const MAX_REQUEST_BYTES = 96 * 1024;
const MAX_SAVE_BYTES = 64 * 1024;
const SESSION_DAYS = 90;
const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/;
const DUMMY_HASH_PROMISE = bcrypt.hash("invalid-account-login", 10);

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

function normalizeUsername(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const username = value.trim().toLowerCase();
  return USERNAME_PATTERN.test(username) ? username : null;
}

function normalizePassword(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const byteLength = new TextEncoder().encode(value).byteLength;
  if (byteLength < 8 || byteLength > 72) return null;
  return value;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function bearerToken(request: Request, body?: unknown): string {
	const tokenFromBody = isRecord(body) && typeof body.session_token === "string" ? body.session_token : "";
	const token = request.headers.get("x-game-session") ?? tokenFromBody;
	return /^[a-f0-9]{64}$/i.test(token) ? token : "";
}

function validSlot(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > 3) return null;
  return value;
}

async function rateLimit(request: Request, username: string, admin: any): Promise<boolean> {
  const forwarded = request.headers.get("x-forwarded-for") ?? request.headers.get("x-real-ip") ?? "unknown";
  const ip = forwarded.split(",")[0].trim().slice(0, 80);
  const keys = [await sha256(`name:${username}:${ip}`), await sha256(`ip:${ip}`)];
  for (const key of keys) {
    const { data, error } = await admin.rpc("consume_game_auth_attempt", { p_rate_key: key });
    if (error || data !== true) return false;
  }
  return true;
}

async function createSession(admin: any, account: { id: string; username: string }): Promise<JsonRecord | null> {
  const token = randomToken();
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const tokenHash = await sha256(token);
  const { error } = await admin.from("game_account_sessions").insert({
    token_hash: tokenHash,
    account_id: account.id,
    expires_at: expiresAt,
  });
  if (error) return null;
  return {
    account_id: account.id,
    username: account.username,
    session_token: token,
    expires_at: expiresAt,
  };
}

async function authenticate(request: Request, admin: any, body?: unknown): Promise<{ accountId: string; tokenHash: string } | null> {
	const token = bearerToken(request, body);
  if (!token) return null;
  const tokenHash = await sha256(token);
  const { data, error } = await admin
    .from("game_account_sessions")
    .select("account_id")
    .eq("token_hash", tokenHash)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (error || !data?.account_id) return null;
  return { accountId: String(data.account_id), tokenHash };
}

async function handleRequest(request: Request, admin: any): Promise<Response> {
  if (request.method !== "POST") return jsonResponse({ ok: false, error: "Método no permitido." }, 405);
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_REQUEST_BYTES) return jsonResponse({ ok: false, error: "La solicitud es demasiado grande." }, 413);

  let body: unknown;
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ ok: false, error: "La solicitud es demasiado grande." }, 413);
    }
    body = JSON.parse(raw);
  } catch {
    return jsonResponse({ ok: false, error: "JSON inválido." }, 400);
  }
  if (!isRecord(body) || typeof body.action !== "string") {
    return jsonResponse({ ok: false, error: "Acción no válida." }, 400);
  }

  const action = body.action;
  if (action === "register" || action === "login") {
    const username = normalizeUsername(body.username);
    const password = normalizePassword(body.password);
    if (!username) {
      return jsonResponse({ ok: false, error: "El ID debe tener 3–20 caracteres: letras, números o guion bajo." }, 400);
    }
    if (!password) {
      return jsonResponse({ ok: false, error: "La contraseña debe tener entre 8 y 72 bytes." }, 400);
    }
    if (!await rateLimit(request, username, admin)) {
      return jsonResponse({ ok: false, error: "Demasiados intentos. Espera 15 minutos y vuelve a probar." }, 429);
    }

    if (action === "register") {
      const passwordHash = await bcrypt.hash(password, 12);
      const { data: account, error } = await admin
        .from("game_accounts")
        .insert({ username, password_hash: passwordHash })
        .select("id,username")
        .single();
      if (error?.code === "23505") {
        return jsonResponse({ ok: false, error: "Ese ID ya está ocupado. Elige otro." }, 409);
      }
      if (error || !account) {
        console.error("Account registration failed", error?.message ?? "missing account");
        return jsonResponse({ ok: false, error: "No se pudo crear la cuenta. Inténtalo de nuevo." }, 503);
      }
      const session = await createSession(admin, { id: String(account.id), username: String(account.username) });
      if (!session) return jsonResponse({ ok: false, error: "La cuenta se creó, pero no se pudo iniciar sesión. Prueba a entrar." }, 503);
      return jsonResponse({ ok: true, session });
    }

    const { data: account } = await admin
      .from("game_accounts")
      .select("id,username,password_hash")
      .eq("username", username)
      .maybeSingle();
    const hashToCheck = account?.password_hash ?? await DUMMY_HASH_PROMISE;
    const passwordMatches = await bcrypt.compare(password, String(hashToCheck));
    if (!account || !passwordMatches) {
      return jsonResponse({ ok: false, error: "ID o contraseña incorrectos." }, 401);
    }
    const session = await createSession(admin, { id: String(account.id), username: String(account.username) });
    if (!session) return jsonResponse({ ok: false, error: "No se pudo iniciar sesión. Inténtalo de nuevo." }, 503);
    return jsonResponse({ ok: true, session });
  }

  const auth = await authenticate(request, admin, body);
  if (!auth) return jsonResponse({ ok: false, error: "La sesión caducó. Inicia sesión de nuevo." }, 401);

  if (action === "logout") {
    const { error } = await admin.from("game_account_sessions").delete().eq("token_hash", auth.tokenHash);
    if (error) return jsonResponse({ ok: false, error: "No se pudo cerrar la sesión." }, 503);
    return jsonResponse({ ok: true });
  }

  if (action === "list_saves") {
    const { data, error } = await admin
      .from("game_account_saves")
      .select("account_id,slot,save_name,level,score,save_data,updated_at")
      .eq("account_id", auth.accountId)
      .order("slot", { ascending: true });
    if (error) return jsonResponse({ ok: false, error: "No se pudieron cargar las partidas." }, 503);
    return jsonResponse({ ok: true, saves: data ?? [] });
  }

  if (action === "load_save") {
    const slot = validSlot(body.slot);
    if (!slot) return jsonResponse({ ok: false, error: "Espacio de guardado inválido." }, 400);
    const { data, error } = await admin
      .from("game_account_saves")
      .select("account_id,slot,save_name,level,score,save_data,updated_at")
      .eq("account_id", auth.accountId)
      .eq("slot", slot)
      .maybeSingle();
    if (error) return jsonResponse({ ok: false, error: "No se pudo cargar la partida." }, 503);
    if (!data) return jsonResponse({ ok: false, error: "No se encontró esa partida." }, 404);
    return jsonResponse({ ok: true, save: data });
  }

  if (action === "create_save" || action === "save_checkpoint") {
    const slot = validSlot(body.slot);
    if (!slot) return jsonResponse({ ok: false, error: "Espacio de guardado inválido." }, 400);
    const isCheckpoint = action === "save_checkpoint";
    const snapshot: unknown = isCheckpoint ? body.save_data : {
      level: 1,
      score: 0,
      penalties_count: 0,
      campaign_completed: false,
    };
    if (!isRecord(snapshot) || new TextEncoder().encode(JSON.stringify(snapshot)).byteLength > MAX_SAVE_BYTES) {
      return jsonResponse({ ok: false, error: "Los datos de la partida no son válidos." }, 400);
    }
    const levelValue = isCheckpoint ? snapshot.level : 1;
    const scoreValue = isCheckpoint ? snapshot.score : 0;
    if (typeof levelValue !== "number" || !Number.isInteger(levelValue) || levelValue < 1 || levelValue > 4) {
      return jsonResponse({ ok: false, error: "Nivel guardado inválido." }, 400);
    }
    if (typeof scoreValue !== "number" || !Number.isSafeInteger(scoreValue)) {
      return jsonResponse({ ok: false, error: "Puntuación inválida." }, 400);
    }
    const saveName = `Partida ${slot}`;
    const { error } = await admin.from("game_account_saves").upsert({
      account_id: auth.accountId,
      slot,
      save_name: saveName,
      level: levelValue,
      score: scoreValue,
      save_data: snapshot,
      updated_at: new Date().toISOString(),
    }, { onConflict: "account_id,slot" });
    if (error) {
      console.error("Account save failed", error.message);
      return jsonResponse({ ok: false, error: "No se pudo guardar la partida." }, 503);
    }
    return jsonResponse({ ok: true });
  }

  if (action === "delete_save") {
    const slot = validSlot(body.slot);
    if (!slot) return jsonResponse({ ok: false, error: "Espacio de guardado inválido." }, 400);
    const { error } = await admin
      .from("game_account_saves")
      .delete()
      .eq("account_id", auth.accountId)
      .eq("slot", slot);
    if (error) return jsonResponse({ ok: false, error: "No se pudo borrar la partida." }, 503);
    return jsonResponse({ ok: true });
  }

  return jsonResponse({ ok: false, error: "Acción desconocida." }, 400);
}

export default {
  fetch: withSupabase({ auth: "publishable" }, async (request, context) => {
    try {
      return await handleRequest(request, context.supabaseAdmin);
    } catch (error) {
      console.error("Account API request failed", error instanceof Error ? error.message : "unknown error");
      return jsonResponse({ ok: false, error: "Error interno. Inténtalo de nuevo." }, 500);
    }
  }),
};
