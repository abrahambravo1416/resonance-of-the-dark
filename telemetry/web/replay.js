/* Pure replay state: the browser and Node regression tests share this reducer. */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ResonanceReplay = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";
  const playerSamples = new Set(["position_sample", "position", "player_position", "movement_sample"]);
  const samples = new Set([...playerSamples, "enemy_position_sample"]);
  const hideKinds = new Set(["hide_started", "hide_ended", "hide_exit_completed", "hiding_started", "hiding_ended", "hiding_zone_entered", "hiding_zone_left"]);
  const attempt = event => String(event.data?.attempt ?? 0);
  const context = event => `${event.level}:${attempt(event)}`;
  const validPosition = position => position && Number.isFinite(position.x) && Number.isFinite(position.z);
  const initialHidden = () => ({hidden:false, hiding:false, hidden_by_zone:false, cover:"", cover_type:""});

  function hiddenAfter(previous, event) {
    const value = {...previous}, data = event.data || {};
    if (event.kind === "hide_started" || event.kind === "hiding_started") value.hiding = true;
    if (["hide_ended", "hiding_ended", "hide_exit_completed"].includes(event.kind)) value.hiding = false;
    if (event.kind === "hiding_zone_entered") value.hidden_by_zone = true;
    if (event.kind === "hiding_zone_left") value.hidden_by_zone = false;
    for (const name of ["hiding", "hidden_by_zone"]) if (typeof data[name] === "boolean") value[name] = data[name];
    if (typeof data.hidden === "boolean") value.hidden = data.hidden;
    else if (hideKinds.has(event.kind) || typeof data.hiding === "boolean" || typeof data.hidden_by_zone === "boolean") value.hidden = value.hiding || value.hidden_by_zone;
    if (data.cover !== undefined) value.cover = String(data.cover || "");
    if (data.cover_type !== undefined) value.cover_type = String(data.cover_type || "");
    if (!value.hidden) {value.cover = ""; value.cover_type = "";}
    return value;
  }

  function at(events, cursor, filter = {}) {
    // Sequence is the tie breaker for transitions captured in the same frame.
    const past = events.filter(event => event.elapsed <= cursor && event.level > 0 &&
      (!filter.level || filter.level === "all" || String(event.level) === String(filter.level)) &&
      (!filter.attempt || filter.attempt === "all" || attempt(event) === String(filter.attempt)))
      .sort((a,b) => a.elapsed - b.elapsed || a.seq - b.seq);
    const current = past.findLast(event => event.kind === "level_started") || past.at(-1);
    if (!current) return {context:null, events:[], player:null, enemies:[], route:[], hiddenIntervals:[], enemySamples:0, paused:false};
    const key = context(current);
    const scoped = past.filter(event => context(event) === key);
    let hidden = initialHidden(), player = null, intervalStart = null, paused = false;
    const route = [], hiddenIntervals = [], enemies = new Map(), identities = new Map();
    let enemySamples = 0;
    for (const event of scoped) {
      const data = event.data || {};
      if (event.kind === "paused") paused = true;
      if (event.kind === "resumed") paused = false;
      if (playerSamples.has(event.kind) || hideKinds.has(event.kind)) {
        const wasHidden = hidden.hidden;
        hidden = hiddenAfter(hidden, event);
        if (!wasHidden && hidden.hidden) intervalStart = event.elapsed;
        if (wasHidden && !hidden.hidden && intervalStart !== null) {
          hiddenIntervals.push({start:intervalStart, end:event.elapsed}); intervalStart = null;
        }
        // Transitions update the marker immediately, including while standing still.
        const position = validPosition(event.position) ? event.position : player?.position;
        if (position) {
          player = {position, elapsed:event.elapsed, ...hidden};
          route.push({...player});
        }
      }
      const id = String(data.enemy_id || data.enemy || "");
      if (event.kind === "enemy_position_sample" && id && validPosition(event.position)) {
        enemySamples++;
        if (!identities.has(id)) identities.set(id, identities.size + 1);
        enemies.set(id, {id, label:`E${identities.get(id)}`, name:data.enemy || id.split("/").at(-1), position:event.position,
          state:data.state || "patrol", yaw:Number(data.yaw) || 0, elapsed:event.elapsed});
      } else if (event.kind === "enemy_removed") enemies.delete(id);
      else if (event.kind === "enemy_state_changed" && enemies.has(id)) enemies.get(id).state = data.state || enemies.get(id).state;
    }
    if (intervalStart !== null) hiddenIntervals.push({start:intervalStart, end:cursor});
    return {context:{level:current.level, attempt:attempt(current)}, events:scoped, player,
      enemies:[...enemies.values()], route, hiddenIntervals, enemySamples, paused};
  }
  return {at, playerSamples, samples, hideKinds, hiddenAfter, attempt, context};
});
