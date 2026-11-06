local root=assert(debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/Scripts/[^/]+$'))
local D={version='0.1.0',root=root,active=true,queue={},plans={},attempts={},errors={}}
function D.valid(o)return o and o:IsValid()end
function D.log(s)print('[Beyond Detours] '..tostring(s)..'\n')end
function D.enqueue(f)if D.active and not D.travelling and #D.queue<64 then D.queue[#D.queue+1]=f end end
D.json=dofile(root..'/Scripts/json.lua');D.planner=dofile(root..'/Scripts/planner.lua')
D.storage=dofile(root..'/Scripts/storage.lua')(D);D.native=dofile(root..'/Scripts/native.lua')(D)
D.network=dofile(root..'/Scripts/network.lua')(D)
local G=StaticFindObject('/Script/Engine.Default__GameplayStatics')
function D.dropRoads()
 local keys={};for k in pairs(D.native.records)do keys[#keys+1]=k end
 for _,k in ipairs(keys)do D.native.remove(D.ctx,k)end
end
local function reset(destroy)
 if destroy then D.dropRoads()end
 D.ctx=nil;D.plans={};D.attempts={};D.queue={};D.native.records={};D.native.pool={};D.native.byPath={};D.native.signature=nil;D.network.reset()
end
local function range(plan,targets,distance)
 for _,at in ipairs(targets)do
  for _,q in ipairs(plan.points)do local w=D.native.worldPoint(plan,q)
   if (w.x-at.X)^2+(w.y-at.Y)^2<distance^2 then return true end
  end
 end
 return false
end
function D.tick()
 if D.travelling or not D.active then return end
 local ctx=D.native.context()
 if not ctx then return end
 if D.ctx and(D.ctx.world~=ctx.world or D.ctx.seed~=ctx.seed)then reset(false)end
 D.ctx=ctx
 if not D.native.signature then D.native.loadPool();D.network.install();D.log('World seed '..ctx.seed..'; standalone '..(ctx.host and'host'or'guest'))end
 local tasks=D.queue;D.queue={};for _,f in ipairs(tasks)do local ok,e=pcall(f);if not ok then D.log(e)end end
 D.network.tick()
 local now=G:GetTimeSeconds(ctx.player)
 local targets={ctx.player:K2_GetActorLocation()}
 if ctx.host then
  for _,pc in ipairs(FindAllOf('PlayerController')or{})do
   if D.valid(pc)and D.valid(pc.PlayerControlled)and D.valid(pc:GetWorld())and pc:GetWorld():GetAddress()==ctx.worldAddress and not pc:IsLocalPlayerController()then targets[#targets+1]=pc.PlayerControlled:K2_GetActorLocation()end
  end
 end
 local roads={}
 for _,r in ipairs(FindAllOf('PRRoad')or{})do
  if D.valid(r)and D.valid(r:GetWorld())and r:GetWorld():GetAddress()==ctx.worldAddress then roads[#roads+1]=r end
 end
 table.sort(roads,function(a,b)return a.RoadIndex<b.RoadIndex end)
 local source
 for _,r in ipairs(roads)do if D.valid(r)and r.IsRoadInitialized and #r.SplineMeshComponents>0 and D.valid(r.SplineMeshComponents[1])then source=r.SplineMeshComponents[1];break end end
 if not source then return end
 if ctx.host then
  local surveyed=false
  for _,road in ipairs(roads)do
   if D.valid(road)and road.IsRoadInitialized then
    local junction=D.planner.junction(ctx.seed,road.RoadIndex)
    if junction then
     for _,side in ipairs(junction.sides)do
      local key=road.RoadIndex..'_'..(side==1 and'R'or'L')
      if not D.plans[key]and not surveyed and now>=(D.attempts[key]or 0)then
       local origin=D.native.anchor(road,junction.t)
       local close=false
       if origin then for _,at in ipairs(targets)do if (origin.x-at.X)^2+(origin.y-at.Y)^2<90000^2 then close=true;break end end end
       if close then
        surveyed=true
        local cachedOk,plan=pcall(D.storage.read,ctx.seed,key,D.native.signature)
        if not cachedOk then D.log('Cache rejected: '..tostring(plan));plan=nil end
        if plan and ((plan.origin.x-origin.x)^2+(plan.origin.y-origin.y)^2>100^2 or math.abs(plan.origin.z-origin.z)>100)then plan=nil end
        local why
        if not plan then plan,why=D.native.plan(ctx,road,junction.t,side)end
        if plan then
         D.storage.write(plan);D.plans[key]=plan
         D.log('Planned '..key..': '..math.floor(plan.length/100)..' m, '..#plan.pois..' native POI(s)')
        else
         D.attempts[key]=now+(why=='pending'and 5 or 60)
         D.log('Deferred '..key..': '..tostring(why))
        end
       end
      end
     end
    end
   end
  end
 end
 if ctx.host or D.network.ready then
  local built=false
  local expired={}
  for key,plan in pairs(D.plans)do
   local visible=range(plan,targets,120000)
   if visible and not D.native.records[key]and not built then
    D.native.build(ctx,plan,source);built=true;D.log('Built detour '..key)
   elseif not visible and D.native.records[key]then D.native.remove(ctx,key)end
   if visible and D.native.records[key]and ctx.host and now>=(D.native.records[key].poiAt or 0)then
    D.native.records[key].poiAt=now+6;D.native.spawnPOIs(ctx,plan)
   end
   if not visible and not range(plan,targets,250000)then expired[#expired+1]=key end
  end
  for _,key in ipairs(expired)do D.plans[key]=nil end
 end
end
D.timer=LoopInGameThreadWithDelay(500,function()
 if not D.active then return end
 local ok,e=xpcall(D.tick,debug.traceback)
 if not ok and not D.errors[e]then D.errors[e]=true;D.log(e)end
end)
RegisterLoadMapPreHook(function()D.travelling=true;reset(false)end)
RegisterLoadMapPostHook(function()D.travelling=false end)
_G.BeyondDetours=D
D.log('Standalone '..D.version..' loaded')
return D
