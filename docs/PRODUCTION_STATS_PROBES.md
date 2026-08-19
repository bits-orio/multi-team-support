# Production Stats — Probe Evidence

Raw in-game measurements backing docs/PRODUCTION_STATS_PLAN.md.
Captured 2026-08-18 on the MTS test save (base 2.0.77, 29 mods, force team-9).
Probe source blocks are reproduced below the output; they were compiled with a real
Lua parser before use and paste both multi-line and collapsed (no '--' comments).

## Raw output (grep "MTS|" factorio-current.log)

```
MTS| PROBE1 ENVIRONMENT =========================
MTS| MODS AdvancedAssembler=1.0.1, Brighter-Lamps=2.0.0, DamageIndicator=1.3.1, FasterStart=2.0.3, Gearery=1.1.3, Quality-Plus-Plus=0.1.2, QualityAssurance=1.4.10, RateCalculator=3.3.8, Science_pack_glow=1.0.2, TurboBelt=1.1.0, aai-containers=0.3.2, aai-loaders=0.2.11, base=2.0.77, elevated-rails=2.0.77, faster-robots=0.0.6, flib=0.16.5, land-title-registry=0.1.12, mech-armor=1.0.1, multi-team-support=0.4.65, negative_space=0.2.3, open-discord-bridge=0.1.12, quality=2.0.77, rz-quality-labs=0.1.0, saplib=0.0.3, solar-productivity=2.1.14, squeak-through-2=0.1.5, um-standalone-big-mining-drill=1.0.2, um-standalone-electromagnetic-plant=1.1.0, um-standalone-space-age-lib=1.1.1
MTS| feature_flags_readable=true
MTS| FLAGS expansion_shaders=true, freezing=true, quality=true, rail_bridges=true, segmented_units=true, space_travel=true, spoiling=true
MTS| Q normal           level=0    hidden=false hid_fp=false order=a        next=uncommon       prob=0.1    color_r=0.69999998807907
MTS| Q uncommon         level=1    hidden=false hid_fp=false order=b        next=rare           prob=0.1    color_r=0.16862745583057
MTS| Q rare             level=2    hidden=false hid_fp=false order=c        next=epic           prob=0.1    color_r=0.098039217293262
MTS| Q epic             level=3    hidden=false hid_fp=false order=d        next=legendary      prob=0.1    color_r=0.53725492954254
MTS| Q legendary        level=5    hidden=false hid_fp=false order=e        next=mythical       prob=0.1    color_r=0.69803923368454
MTS| Q mythical         level=6    hidden=false hid_fp=false order=f        next=masterwork     prob=0.1    color_r=0.839215695858
MTS| Q masterwork       level=7    hidden=false hid_fp=false order=g        next=wondrous       prob=0.1    color_r=0.90196079015732
MTS| Q wondrous         level=8    hidden=false hid_fp=false order=h        next=artifactual    prob=0.1    color_r=0.85098040103912
MTS| Q artifactual      level=10   hidden=false hid_fp=false order=i        next=nil            prob=0      color_r=0.38431373238564
MTS| Q quality-unknown  level=0    hidden=true  hid_fp=true  order=z        next=nil            prob=0      color_r=1
MTS| quality_total=10
MTS| normal_exists=true
MTS| CHAIN=normal > uncommon > rare > epic > legendary > mythical > masterwork > wondrous > artifactual  chain_len=9
MTS| is_quality_unlocked(normal) ok=true ret=true
MTS| is_quality_unlocked(uncommon) ok=true ret=true
MTS| is_quality_unlocked(rare) ok=true ret=true
MTS| is_quality_unlocked(epic) ok=true ret=true
MTS| is_quality_unlocked(legendary) ok=true ret=false
MTS| is_quality_unlocked(mythical) ok=true ret=false
MTS| is_quality_unlocked(masterwork) ok=true ret=false
MTS| is_quality_unlocked(wondrous) ok=true ret=false
MTS| is_quality_unlocked(artifactual) ok=true ret=false
MTS| sprite_path fluid/water ok=true valid=true
MTS| sprite_path quality/normal ok=true valid=true
MTS| sprite_path quality/legendary ok=true valid=true
MTS| sprite_path item/iron-plate ok=true valid=true
MTS| PROBE2A FLUIDS =========================
MTS| fluids_total=19 visible=18 hidden=1
MTS| VISIBLE=crude-oil, heavy-oil, light-oil, lubricant, parameter-0, parameter-1, parameter-2, parameter-3, parameter-4, parameter-5, parameter-6, parameter-7, parameter-8, parameter-9, petroleum-gas, steam, sulfuric-acid, water
MTS| HIDDEN=fluid-unknown
MTS| TILE_FLUIDS=water x6
MTS| PROBE2B RECIPES =========================
MTS| MIXED_no_main_product=7 EX=empty-water-barrel, empty-crude-oil-barrel, empty-petroleum-gas-barrel, empty-light-oil-barrel, empty-heavy-oil-barrel, empty-lubricant-barrel, empty-sulfuric-acid-barrel
MTS| main_product nil=209 empty=0 fluid=2
MTS| hidden_from_flow_stats=0 EX=
MTS| PROBE3A SEED =========================
MTS| seed normal 7 ok=true err=nil
MTS| seed uncommon 100 ok=true err=nil
MTS| seed water 250 ok=true err=nil
MTS| surface=team-9-nauvis force=team-9
MTS| PROBE3Bi ITEM ====================
MTS| A1flat   ok=true  val=208
MTS| A2bare   ok=true  val=108
MTS| A3norm   ok=true  val=108
MTS| A4unc    ok=true  val=100
MTS| B1bare   ok=true  val=108
MTS| B2norm   ok=true  val=108
MTS| B3unc    ok=true  val=100
MTS| C1q21    ok=false val=LuaFlowStatistics doesn't contain key input_quality_counts.
MTS| PROBE3Bii FLUID ====================
MTS| D1bare   ok=true  val=956.31867647171
MTS| D2flow   ok=true  val=956.31868910789
MTS| D3flat   ok=true  val=956.31867647171
MTS| D4qual   ok=false val=value for required field 'amount' is missing
MTS| D5amt    ok=true  val=956.31867647171
```

## Probe 4 (rich text — visual, from screenshot)

All six rendered as icons: `[fluid=water]`, `[quality=rare]`, `[item=iron-plate,quality=rare]`
(quality-badged), `[item=iron-plate]`, `[img=fluid/water]`, `[img=quality/rare]`.
The `[type=name]` forms emit an icon plus a text label; `[img=path]` emits the bare icon.

## Probe source

```
================================================================
MTS PRODUCTION STATS — FACTORIO CONSOLE PROBES
Every probe writes to factorio-current.log, prefixed "MTS| ".
Afterwards, from a shell:
  grep 'MTS|' ~/.factorio/factorio-current.log
Your active log is ~/.factorio/factorio-current.log (most recent).
If you run from a different install, try instead:
  grep -h 'MTS|' ~/.factorio/factorio-current.log \
       ~/factorio-2.0/factorio-current.log \
       ~/factorio-dev/factorio-headless/factorio-current.log 2>/dev/null
No "--" comments are used anywhere, so each block is safe to paste
either as multiple lines OR collapsed onto a single line.
================================================================


=== PROBE 1 — ENVIRONMENT + QUALITY CHAIN (read-only, safe on any save) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE1 ENVIRONMENT =========================")
local okm,mods=pcall(function() return script.active_mods end)
if okm and mods then local ml={} for k,v in pairs(mods) do ml[#ml+1]=k.."="..v end table.sort(ml) P("MODS "..table.concat(ml,", ")) end
local okf,ff=pcall(function() return script.feature_flags end)
P("feature_flags_readable="..tostring(okf))
if okf and ff then local fl={} for k,v in pairs(ff) do fl[#fl+1]=k.."="..tostring(v) end table.sort(fl) P("FLAGS "..table.concat(fl,", ")) end
local n=0
for name,q in pairs(prototypes.quality) do n=n+1
local c=q.color or {}
local cr=c.r or c[1] or 0
P(string.format("Q %-16s level=%-4s hidden=%-5s hid_fp=%-5s order=%-8s next=%-14s prob=%-6s color_r=%s",name,tostring(q.level),tostring(q.hidden),tostring(q.hidden_in_factoriopedia),tostring(q.order),tostring(q.next and q.next.name),tostring(q.next_probability),tostring(cr)))
end
P("quality_total="..n)
local root=prototypes.quality["normal"]
P("normal_exists="..tostring(root~=nil))
local chain,seen={},{}
local cur=root
while cur and not seen[cur.name] do seen[cur.name]=true chain[#chain+1]=cur.name cur=cur.next end
P("CHAIN="..table.concat(chain," > ").."  chain_len="..#chain)
local f=(game.player and game.player.force) or game.forces["player"]
if f then for _,qn in ipairs(chain) do local ok,v=pcall(function() return f.is_quality_unlocked(qn) end) P("is_quality_unlocked("..qn..") ok="..tostring(ok).." ret="..tostring(v)) end end
for _,sp in ipairs({"fluid/water","quality/normal","quality/legendary","item/iron-plate"}) do local ok,v=pcall(function() return helpers.is_valid_sprite_path(sp) end) P("sprite_path "..sp.." ok="..tostring(ok).." valid="..tostring(v)) end
log("\n"..table.concat(o,"\n"))
game.print("PROBE1 written to factorio-current.log")


=== PROBE 2 — FLUID SET + RECIPE AUDIT (read-only, safe on any save) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE2 FLUIDS+RECIPES =========================")
local vis,hid,nf={},{},0
for name,fp in pairs(prototypes.fluid) do nf=nf+1
if fp.hidden or fp.hidden_in_factoriopedia then hid[#hid+1]=name.."(h="..tostring(fp.hidden)..",hfp="..tostring(fp.hidden_in_factoriopedia)..")" else vis[#vis+1]=name end
end
table.sort(vis) table.sort(hid)
P("fluids_total="..nf.."  visible="..#vis.."  hidden="..#hid)
P("VISIBLE_FLUIDS="..table.concat(vis,", "))
P("HIDDEN_FLUIDS="..table.concat(hid,", "))
local seed={"crude-oil","petroleum-gas","sulfuric-acid","light-oil","heavy-oil","lubricant","water","steam"}
for _,s in ipairs(seed) do local p=prototypes.fluid[s] P("seed "..s.." exists="..tostring(p~=nil)..(p and (" hidden="..tostring(p.hidden).." hid_fp="..tostring(p.hidden_in_factoriopedia)) or "")) end
local tf={}
for tn,tp in pairs(prototypes.tile) do local fl=tp.fluid if fl then tf[fl.name]=(tf[fl.name] or 0)+1 end end
local tl={} for k,v in pairs(tf) do tl[#tl+1]=k.." x"..v end table.sort(tl)
P("TILE_FLUIDS(offshore sources)="..table.concat(tl,", "))
local mixed,ex,hidstat,hidex,mpempty,mpnil,mpfluid=0,{},0,{},0,0,0
for rn,r in pairs(prototypes.recipe) do
local ni,nfl=0,0
for _,p in pairs(r.products) do if p.type=="item" then ni=ni+1 elseif p.type=="fluid" then nfl=nfl+1 end end
local mp=r.main_product
if mp==nil then mpnil=mpnil+1 elseif type(mp)=="table" and mp.name=="" then mpempty=mpempty+1 elseif type(mp)=="table" and mp.type=="fluid" then mpfluid=mpfluid+1 end
if ni>=1 and nfl>=1 and mp==nil then mixed=mixed+1 if #ex<15 then ex[#ex+1]=rn.."(i"..ni.."f"..nfl..")" end end
if r.hidden_from_flow_stats then hidstat=hidstat+1 if #hidex<15 then hidex[#hidex+1]=rn end end
end
P("MIXED_item+fluid_no_main_product="..mixed)
P("MIXED_EXAMPLES="..table.concat(ex,", "))
P("main_product: nil="..mpnil.."  empty_name="..mpempty.."  is_fluid="..mpfluid)
P("recipes_hidden_from_flow_stats="..hidstat)
P("HIDDEN_FROM_STATS_EXAMPLES="..table.concat(hidex,", "))
log("\n"..table.concat(o,"\n"))
game.print("PROBE2 written to factorio-current.log")


=== PROBE 3A — SEED THE STATISTICS (DESTRUCTIVE: SCRATCH SAVE ONLY) ===
This calls clear() on the current surface's production statistics.
Do NOT run on a save you care about. Game must be RUNNING (not paused).

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE3A SEED =========================")
local pl=game.player or game.connected_players[1]
if not pl then log("MTS| ERROR no player - run in singleplayer") return end
local s=pl.force.get_item_production_statistics(pl.surface)
s.clear()
local ok1,e1=pcall(function() s.on_flow("iron-plate",7) end)
P("seed normal(bare,7) ok="..tostring(ok1).." err="..tostring(e1))
local ok2,e2=pcall(function() s.on_flow({name="iron-plate",quality="uncommon"},100) end)
P("seed uncommon(pair,100) ok="..tostring(ok2).." err="..tostring(e2))
local fs=pl.force.get_fluid_production_statistics(pl.surface)
fs.clear()
local ok3,e3=pcall(function() fs.on_flow("water",250) end)
P("seed water(250) ok="..tostring(ok3).." err="..tostring(e3))
P("surface="..pl.surface.name.." force="..pl.force.name)
log("\n"..table.concat(o,"\n"))
game.print("PROBE3A seeded. LET THE GAME RUN ~3 SECONDS, then run PROBE3B.")


=== PROBE 3B — READ IT BACK (run a few seconds after 3A) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE3B READBACK =========================")
local pl=game.player or game.connected_players[1]
if not pl then log("MTS| ERROR no player - run in singleplayer") return end
local s=pl.force.get_item_production_statistics(pl.surface)
local fs=pl.force.get_fluid_production_statistics(pl.surface)
local function R(lbl,fn) local ok,v=pcall(fn) P(string.format("%-42s ok=%-5s val=%s",lbl,tostring(ok),tostring(v))) end
R("A1 alltime input_counts[iron-plate]",function() return s.input_counts["iron-plate"] end)
R("A2 alltime get_input_count(bare)",function() return s.get_input_count("iron-plate") end)
R("A3 alltime get_input_count(normal)",function() return s.get_input_count{name="iron-plate",quality="normal"} end)
R("A4 alltime get_input_count(uncommon)",function() return s.get_input_count{name="iron-plate",quality="uncommon"} end)
local p=defines.flow_precision_index.one_minute
R("B1 1m flow bare count=true",function() return s.get_flow_count{name="iron-plate",category="input",precision_index=p,count=true} end)
R("B2 1m flow normal count=true",function() return s.get_flow_count{name={name="iron-plate",quality="normal"},category="input",precision_index=p,count=true} end)
R("B3 1m flow uncommon count=true",function() return s.get_flow_count{name={name="iron-plate",quality="uncommon"},category="input",precision_index=p,count=true} end)
R("B4 1m flow bare count=false(rate)",function() return s.get_flow_count{name="iron-plate",category="input",precision_index=p,count=false} end)
R("C1 input_quality_counts exists(2.1)",function() return type(s.input_quality_counts) end)
R("D1 fluid alltime bare",function() return fs.get_input_count("water") end)
R("D2 fluid 1m flow",function() return fs.get_flow_count{name="water",category="input",precision_index=p,count=true} end)
R("D3 fluid input_counts[water]",function() return fs.input_counts["water"] end)
R("D4 fluid + quality (should reject)",function() return fs.get_input_count{name="water",quality="uncommon"} end)
R("D5 fluid Fluid-table id (amount)",function() return fs.get_input_count{name="water",amount=1} end)
log("\n"..table.concat(o,"\n"))
game.print("PROBE3B written to factorio-current.log")


=== PROBE 4 — RICH TEXT (VISUAL — must be eyeballed, cannot be logged) ===
Run it, then look at the chat area. Report which render as ICONS and
which render as literal text.

/c game.print("1[fluid=water] 2[quality=rare] 3[item=iron-plate,quality=rare] 4[item=iron-plate] 5[img=fluid/water] 6[img=quality/rare]")

================================================================
HOW TO READ PROBE 3B
================================================================
Seeded: iron-plate normal=7, iron-plate uncommon=100, water=250.

Judge by COMPARING readings, never by absolute numbers -- the timed
values depend on exactly when you ran 3B relative to 3A.

--- Q1: does the flat read merge across qualities? ---
Compare A2 (bare) against A3 (normal) and A4 (uncommon).
  A2 == A3, and A4 separate   ->  flat read is NORMAL-ONLY.
        MTS under-reports today. Merged mode must sum the chain,
        and this becomes a correctness fix, not just a feature.
  A2 == A3 + A4               ->  flat read MERGES.
        MTS is already correct; quality work is a pure feature.
  A1 should track A2. If it does not, say so -- that is undocumented.

--- Q2: are the timed buffers quality-partitioned? ---  <<< THE BIG ONE
Compare B2 (normal) against B3 (uncommon).
  B3 clearly larger than B2   ->  PARTITIONED (ratio should approach
        100:7). Quality selector + tooltip breakdown work on every
        time period. The full design is viable.
  B2 == B3 == B1              ->  NOT partitioned; quality is ignored
        for timed reads. Per-quality numbers exist ONLY on All-time,
        so the quality selector must grey out on 1m/10m/1h/10h.
        THIS IS THE ANSWER THAT RESHAPES THE DESIGN.

  If B1, B2 and B3 are ALL 0, on_flow did not reach the sample
  buffers at all. In that case ignore Q2 here and instead: hand-craft
  a few iron plates at two different qualities in-game, let it run a
  few seconds, and re-run PROBE 3B on its own. Do not run 3A again.

--- Q3: which branch / fast path ---
  C1 val="table"  ->  2.1; input_quality_counts collapses per-column cost.
  C1 ok=false     ->  2.0 as expected; use the chain-sum path.

--- Q4: fluid ID strictness ---
  D4/D5 ok=false  ->  fluids must be bare strings, as the docs imply.
  D4/D5 ok=true   ->  a surplus quality/amount field is silently ignored.

Also worth reporting: anything in PROBE 1 where hidden=true on a
quality you would expect to be visible, and the CHAIN line -- that
drives how the quality selector is built for YOUR modpack.
================================================================

=== PROBE 2A — FLUID SET (read-only, safe) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE2A FLUIDS =========================")
local vis,hid,nf={},{},0
for name,fp in pairs(prototypes.fluid) do nf=nf+1
if fp.hidden or fp.hidden_in_factoriopedia then hid[#hid+1]=name else vis[#vis+1]=name end
end
table.sort(vis) table.sort(hid)
P("fluids_total="..nf.." visible="..#vis.." hidden="..#hid)
P("VISIBLE="..table.concat(vis,", "))
P("HIDDEN="..table.concat(hid,", "))
local tf={}
for tn,tp in pairs(prototypes.tile) do local fl=tp.fluid if fl then tf[fl.name]=(tf[fl.name] or 0)+1 end end
local tl={} for k,v in pairs(tf) do tl[#tl+1]=k.." x"..v end table.sort(tl)
P("TILE_FLUIDS="..table.concat(tl,", "))
log("\n"..table.concat(o,"\n"))
game.print("PROBE2A done")


=== PROBE 2B — RECIPE AUDIT (read-only, safe) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE2B RECIPES =========================")
local mixed,ex,hs,hx,mpe,mpn,mpf=0,{},0,{},0,0,0
for rn,r in pairs(prototypes.recipe) do
local ni,nf=0,0
for _,p in pairs(r.products) do if p.type=="item" then ni=ni+1 elseif p.type=="fluid" then nf=nf+1 end end
local mp=r.main_product
if mp==nil then mpn=mpn+1 elseif type(mp)=="table" and mp.name=="" then mpe=mpe+1 elseif type(mp)=="table" and mp.type=="fluid" then mpf=mpf+1 end
if ni>=1 and nf>=1 and mp==nil then mixed=mixed+1 if #ex<12 then ex[#ex+1]=rn end end
if r.hidden_from_flow_stats then hs=hs+1 if #hx<12 then hx[#hx+1]=rn end end
end
P("MIXED_no_main_product="..mixed.." EX="..table.concat(ex,", "))
P("main_product nil="..mpn.." empty="..mpe.." fluid="..mpf)
P("hidden_from_flow_stats="..hs.." EX="..table.concat(hx,", "))
log("\n"..table.concat(o,"\n"))
game.print("PROBE2B done")

RUN IN THIS ORDER. 2B is safe anywhere. 3A/3B are SCRATCH SAVE ONLY.
Read results with:  grep 'MTS|' ~/.factorio/factorio-current.log

=== 2B — RECIPE AUDIT (read-only, safe on your normal save) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE2B RECIPES =========================")
local mixed,ex,hs,hx,mpe,mpn,mpf=0,{},0,{},0,0,0
for rn,r in pairs(prototypes.recipe) do
local ni,nf=0,0
for _,p in pairs(r.products) do if p.type=="item" then ni=ni+1 elseif p.type=="fluid" then nf=nf+1 end end
local mp=r.main_product
if mp==nil then mpn=mpn+1 elseif type(mp)=="table" and mp.name=="" then mpe=mpe+1 elseif type(mp)=="table" and mp.type=="fluid" then mpf=mpf+1 end
if ni>=1 and nf>=1 and mp==nil then mixed=mixed+1 if #ex<12 then ex[#ex+1]=rn end end
if r.hidden_from_flow_stats then hs=hs+1 if #hx<12 then hx[#hx+1]=rn end end
end
P("MIXED_no_main_product="..mixed.." EX="..table.concat(ex,", "))
P("main_product nil="..mpn.." empty="..mpe.." fluid="..mpf)
P("hidden_from_flow_stats="..hs.." EX="..table.concat(hx,", "))
log("\n"..table.concat(o,"\n"))
game.print("PROBE2B done")


=== 3A — SEED  (DESTRUCTIVE: wipes production stats for your current
    surface. SCRATCH SAVE ONLY. Game must be RUNNING, not paused.) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
P("PROBE3A SEED =========================")
local pl=game.player or game.connected_players[1]
if not pl then log("MTS| ERROR no player") return end
local s=pl.force.get_item_production_statistics(pl.surface)
s.clear()
local a,ea=pcall(function() s.on_flow("iron-plate",7) end)
P("seed normal 7 ok="..tostring(a).." err="..tostring(ea))
local b,eb=pcall(function() s.on_flow({name="iron-plate",quality="uncommon"},100) end)
P("seed uncommon 100 ok="..tostring(b).." err="..tostring(eb))
local fs=pl.force.get_fluid_production_statistics(pl.surface)
fs.clear()
local c,ec=pcall(function() fs.on_flow("water",250) end)
P("seed water 250 ok="..tostring(c).." err="..tostring(ec))
P("surface="..pl.surface.name.." force="..pl.force.name)
log("\n"..table.concat(o,"\n"))
game.print("PROBE3A seeded. LET IT RUN ~3s, then run 3Bi and 3Bii.")


=== 3Bi — ITEM READBACK (run ~3s after 3A) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
local pl=game.player or game.connected_players[1]
if not pl then log("MTS| ERROR no player") return end
local s=pl.force.get_item_production_statistics(pl.surface)
local p=defines.flow_precision_index.one_minute
local function R(l,f) local ok,v=pcall(f) P(string.format("%-8s ok=%-5s val=%s",l,tostring(ok),tostring(v))) end
P("PROBE3Bi ITEM ====================")
R("A1flat",function() return s.input_counts["iron-plate"] end)
R("A2bare",function() return s.get_input_count("iron-plate") end)
R("A3norm",function() return s.get_input_count{name="iron-plate",quality="normal"} end)
R("A4unc",function() return s.get_input_count{name="iron-plate",quality="uncommon"} end)
R("B1bare",function() return s.get_flow_count{name="iron-plate",category="input",precision_index=p,count=true} end)
R("B2norm",function() return s.get_flow_count{name={name="iron-plate",quality="normal"},category="input",precision_index=p,count=true} end)
R("B3unc",function() return s.get_flow_count{name={name="iron-plate",quality="uncommon"},category="input",precision_index=p,count=true} end)
R("C1q21",function() return type(s.input_quality_counts) end)
log("\n"..table.concat(o,"\n"))
game.print("PROBE3Bi done")


=== 3Bii — FLUID READBACK (run right after 3Bi) ===

/c local o={} local function P(s) o[#o+1]="MTS| "..tostring(s) end
local pl=game.player or game.connected_players[1]
if not pl then log("MTS| ERROR no player") return end
local fs=pl.force.get_fluid_production_statistics(pl.surface)
local p=defines.flow_precision_index.one_minute
local function R(l,f) local ok,v=pcall(f) P(string.format("%-8s ok=%-5s val=%s",l,tostring(ok),tostring(v))) end
P("PROBE3Bii FLUID ====================")
R("D1bare",function() return fs.get_input_count("water") end)
R("D2flow",function() return fs.get_flow_count{name="water",category="input",precision_index=p,count=true} end)
R("D3flat",function() return fs.input_counts["water"] end)
R("D4qual",function() return fs.get_input_count{name="water",quality="uncommon"} end)
R("D5amt",function() return fs.get_input_count{name="water",amount=1} end)
log("\n"..table.concat(o,"\n"))
game.print("PROBE3Bii done")
```
