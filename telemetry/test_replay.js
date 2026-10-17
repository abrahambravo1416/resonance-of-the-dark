"use strict";
// Run: node --test telemetry/test_replay.js
const test = require("node:test");
const assert = require("node:assert/strict");
const Replay = require("./web/replay.js");
let sequence = 0;
const event = (elapsed, kind, data={}, position=null, level=1) => ({seq:++sequence, elapsed, kind, level, data:{attempt:1,...data}, position});
const pos = x => ({x,y:0,z:0});
const enemy = (time,x,state="patrol",data={}) => event(time,"enemy_position_sample",{enemy_id:"World/Enemy_1",enemy:"Enemy_1",state,...data},pos(x));

test("enemy playback never reads future positions, and backwards scrubbing rebuilds state",()=>{
  const events=[event(0,"level_started"),event(.2,"position_sample",{},pos(1)),enemy(1,10),enemy(2,20,"chase")];
  assert.equal(Replay.at(events,.9).enemies.length,0);
  assert.equal(Replay.at(events,1.9).enemies[0].position.x,10);
  assert.equal(Replay.at(events,2).enemies[0].state,"chase");
  assert.equal(Replay.at(events,1).enemies[0].state,"patrol");
  assert.equal(Replay.at(events,.1).player,null);
  assert.equal(Replay.at(events,2).route.length,1);
});

test("pause gaps hold the last recorded positions without extrapolating",()=>{
  const events=[event(0,"level_started"),enemy(1,10),event(2,"paused"),event(15,"resumed"),enemy(16,14)];
  assert.equal(Replay.at(events,10).enemies[0].position.x,10);
  assert.equal(Replay.at(events,10).paused,true);
  assert.equal(Replay.at(events,15.5).enemies[0].position.x,10);
  assert.equal(Replay.at(events,15.5).paused,false);
  assert.equal(Replay.at(events,16).enemies[0].position.x,14);
});

test("level and attempt reset clears old actors, positions and hiding",()=>{
  const events=[event(0,"level_started"),enemy(1,10),event(2,"position_sample",{hidden:true},pos(1)),
    event(3,"level_started",{attempt:2}),event(4,"position_sample",{attempt:2,hidden:false},pos(90)),
    event(5,"level_started",{attempt:3},null,2),event(6,"enemy_position_sample",{attempt:3,enemy_id:"World/Enemy_1"},pos(200),2)];
  assert.equal(Replay.at(events,2).player.hidden,true);
  assert.equal(Replay.at(events,3).enemies.length,0);
  assert.equal(Replay.at(events,3).player,null);
  assert.deepEqual(Replay.at(events,4).context,{level:1,attempt:"2"});
  assert.equal(Replay.at(events,4).hiddenIntervals.length,0);
  assert.deepEqual(Replay.at(events,6).context,{level:2,attempt:"3"});
  assert.equal(Replay.at(events,6).enemies[0].position.x,200);
  assert.equal(Replay.at(events,6).player,null);
  assert.equal(Replay.at(events,3,{level:2}).context,null);
  assert.equal(Replay.at(events,6,{level:1,attempt:1}).enemies[0].position.x,10);
});

test("stationary hiding starts immediately, remains during exit and ends at completion",()=>{
  const events=[event(0,"level_started"),event(1,"position_sample",{hidden:false},pos(2)),
    event(2,"hide_started",{hidden:true,hiding:true,hidden_by_zone:false,cover:"Grave_04",cover_type:"grave"}),
    event(5,"hide_ended",{hidden:true,hiding:false,hidden_by_zone:false}),
    event(5.3,"hide_exit_completed",{hidden:false,hiding:false,hidden_by_zone:false})];
  const hidden=Replay.at(events,3);
  assert.equal(hidden.player.hidden,true);
  assert.equal(hidden.player.position.x,2);
  assert.equal(hidden.player.cover,"Grave_04");
  assert.deepEqual(hidden.hiddenIntervals,[{start:2,end:3}]);
  assert.equal(Replay.at(events,5.1).player.hidden,true);
  assert.equal(Replay.at(events,5.3).player.hidden,false);
  assert.deepEqual(Replay.at(events,6).hiddenIntervals,[{start:2,end:5.3}]);
  assert.equal(Replay.at(events,1).player.hidden,false);
});

test("zone cover overlaps hiding and stays authoritative until both sources end",()=>{
  const events=[event(0,"level_started"),event(1,"position_sample",{},pos(1)),
    event(2,"hiding_zone_entered",{hidden:true,hiding:false,hidden_by_zone:true}),
    event(3,"hide_started",{hidden:true,hiding:true,hidden_by_zone:true}),
    event(4,"hide_exit_completed",{hidden:true,hiding:false,hidden_by_zone:true}),
    event(5,"hiding_zone_left",{hidden:false,hiding:false,hidden_by_zone:false})];
  assert.equal(Replay.at(events,4).player.hidden,true);
  assert.equal(Replay.at(events,4).player.hidden_by_zone,true);
  assert.equal(Replay.at(events,5).player.hidden,false);
  assert.deepEqual(Replay.at(events,6).hiddenIntervals,[{start:2,end:5}]);
});

test("legacy logs infer hide transitions, accept hidden samples and require no enemies",()=>{
  const events=[event(0,"level_started",{attempt:0}),event(1,"position",{attempt:0},pos(1)),
    event(2,"hide_started",{attempt:0}),event(3,"hide_ended",{attempt:0}),
    event(4,"position_sample",{attempt:0,hidden:true},pos(2)),event(5,"position_sample",{attempt:0,hidden:false},pos(3))];
  assert.equal(Replay.at(events,2).player.hidden,true);
  assert.equal(Replay.at(events,3).player.hidden,false);
  assert.equal(Replay.at(events,4).player.hidden,true);
  assert.equal(Replay.at(events,5).enemySamples,0);
  assert.equal(Replay.at(events,5).enemies.length,0);
  assert.deepEqual(Replay.at(events,5).hiddenIntervals,[{start:2,end:3},{start:4,end:5}]);
});

test("stable enemy identities survive state changes and removed actors disappear",()=>{
  const events=[event(0,"level_started"),enemy(1,10),enemy(1.2,30,"patrol",{enemy_id:"World/Enemy_2"}),
    event(2,"enemy_state_changed",{enemy_id:"World/Enemy_1",state:"investigate"}),
    event(3,"enemy_removed",{enemy_id:"World/Enemy_1"})];
  assert.equal(Replay.at(events,2).enemies[0].state,"investigate");
  assert.deepEqual(Replay.at(events,2).enemies.map(e=>e.label),["E1","E2"]);
  assert.equal(Replay.at(events,3).enemies.length,1);
  assert.equal(Replay.at(events,3).enemies[0].label,"E2");
});

test("same-frame transitions use sequence order and samples do not inflate actions",()=>{
  const events=[event(0,"level_started"),event(1,"position_sample",{},pos(1)),
    event(2,"hide_started",{hidden:true}),event(2,"hide_exit_completed",{hidden:false})];
  assert.equal(Replay.at(events,2).player.hidden,false);
  assert.equal(Replay.samples.has("enemy_position_sample"),true);
  assert.equal(Replay.playerSamples.has("enemy_position_sample"),false);
});
