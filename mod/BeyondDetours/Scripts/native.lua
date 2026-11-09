return function(D)
 -- SM_Road_A5 UV 0..1 spans +/-452.238 cm. Bounds include deep gravel skirts.
 local N={pavedHalf=452.238,pool={},byPath={},records={},metrics={builds=0,removes=0,poiAttempts=0}};local P=D.planner;local valid=D.valid
 local G=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local S=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local M=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
 local color={R=0,G=0,B=0,A=0}
 local function vec(q)return {X=q.x,Y=q.y,Z=q.z}end
 local function point(q)return {x=q.X,y=q.Y,z=q.Z}end
 local function identity(pos,yaw)
  local h=(yaw or 0)*.5
  return {Translation=pos or{X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=math.sin(h),W=math.cos(h)},Scale3D={X=1,Y=1,Z=1}}
 end
 N.identity=identity
 local function copyTransform(t)
  local q=t.Rotation
  return {Translation=vec(point(t.Translation)),Rotation={X=q.X,Y=q.Y,Z=q.Z,W=q.W},Scale3D=vec(point(t.Scale3D))}
 end
 function N.context()
  local engine=FindFirstOf('GameEngine');if not valid(engine)or not valid(engine.GameViewport)then return end
  local pc=G:GetPlayerController(engine.GameViewport,0)
  if not valid(pc)or not pc:IsLocalPlayerController()then return end
  local p=pc.PlayerControlled
  if not valid(p)or not p.IsLoaded or not p.IsInitialized then return end
  local gs=G:GetGameState(p);if not valid(gs)then return end
  local world=gs:GetWorld();if not valid(world)then return end
  local manager=D.ctx and D.ctx.worldAddress==world:GetAddress()and D.ctx.manager
  if not valid(manager)then
  for _,m in ipairs(FindAllOf('RoadManager')or{})do
   if valid(m)and valid(m:GetWorld())and m:GetWorld():GetAddress()==world:GetAddress()then manager=m;break end
  end
  end
  if not valid(gs)or not valid(manager)or not valid(manager.Landscape)or not valid(gs.LSLevelSpawner)then return end
  return {pc=pc,player=p,gs=gs,manager=manager,land=manager.Landscape,spawner=gs.LSLevelSpawner,seed=gs.Seed,host=pc:HasAuthority(),world=gs:GetFullName()..':'..gs:GetAddress(),worldAddress=world:GetAddress()}
 end
 function N.density(ctx)
  -- Same native field used by PRRoad::GetTransformArray for roadside POI chance.
  if not valid(ctx.spawner.DBHSaveGame)then return nil end
  local helper=StaticFindObject('/Script/DriveBeyondHorizons.Default__DBHHelper')
  local d=helper:GetDifficultyDenormalized();local bounds=helper:GetDifficultySaveGame().DifficultyValue.LevelSpawn
  -- Native LevelSpawn is an inverse spacing multiplier (6 -> .2 in this
  -- build), not a 0..1 chance. Recover the actual slider position from its range.
  local span=bounds.Y-bounds.X
  if math.abs(span)<.000001 then return 1 end
  return math.max(0,math.min(1,(d.LevelSpawn-bounds.X)/span))
 end
 function N.loadPool()
  local pool=LoadAsset('/Game/BP/DataAssets/Roads/DARoadLevelTest_3.DARoadLevelTest_3')
  assert(valid(pool),'Native roadside POI pool unavailable')
  N.pool={};N.byPath={};N.maximum=math.max(1,pool.MaximumSpawn);N.sideOffset=pool.SideOffset
  pool.Levels:ForEach(function(_,raw)
   local e=raw:get();local path=S:Conv_SoftObjectReferenceToString(e.Level.World):ToString()
   if path~=''then
    -- ForEach exposes borrowed struct storage. Keep only owned Lua values across ticks.
    local level=e.Level;local tr=level.Transform;local q=tr.Rotation
    local template={AlwaysVisible=level.AlwaysVisible,UseCustomSideOffset=level.UseCustomSideOffset,CustomSideOffset=level.CustomSideOffset,CreationTime=level.CreationTime,Transform={Translation=vec(point(tr.Translation)),Rotation={X=q.X,Y=q.Y,Z=q.Z,W=q.W},Scale3D=vec(point(tr.Scale3D))}}
    local item={path=path,weight=e.RandomWeight,minDistance=e.MinSpawnDistance,minHeight=e.MinSpawnHeight,maxHeight=e.MaxSpawnHeight,minSlope=e.MinSlopeAngle,maxSlope=e.MaxSlopeAngle,once=e.SpawnOneTimeAtDistance,template=template}
    N.pool[#N.pool+1]=item;N.byPath[path]=item
   end
  end)
  table.sort(N.pool,function(a,b)return a.path<b.path end)
  assert(#N.pool>0,'Native POI pool is empty')
  local signature={};for _,e in ipairs(N.pool)do signature[#signature+1]=e.path..':'..e.weight..':'..e.template.CustomSideOffset end
  N.signature=tostring(P.hash(table.concat(signature,'|')))
  N.footprints=dofile(D.root..'/Scripts/footprints.lua')
  local roadMesh=LoadAsset('/Game/StaticMeshes/Road/SM_Road_A5.SM_Road_A5')
  if valid(roadMesh)then local box=roadMesh:GetBoundingBox();N.roadHalf=(box.Max.Y-box.Min.Y)*.5 end
  D.log('Read '..#N.pool..' native POI entries; original data asset unchanged')
 end
 function N.worldPoint(plan,q)
  local c,s=math.cos(plan.yaw),math.sin(plan.yaw);local y=q.y*plan.side
  return {x=plan.origin.x+c*q.x-s*y,y=plan.origin.y+s*q.x+c*y,z=plan.origin.z+q.z}
 end
 function N.anchor(road,t)
  if not valid(road)or not road.IsRoadInitialized or #road.SplineMeshComponents<1 then return end
  local source=road.SplineMeshComponents[1];if not valid(source)or not valid(source.StaticMesh)then return end
  local a,b=point(source:GetStartPosition()),point(source:GetEndPosition())
  local ta,tb=point(source:GetStartTangent()),point(source:GetEndTangent())
  local localPoint=P.hermite(a,b,ta,tb,t)
  local ahead=P.hermite(a,b,ta,tb,math.min(t+.001,1))
  local transform=source:K2_GetComponentToWorld()
  local at=M:TransformLocation(transform,vec(localPoint));local nextAt=M:TransformLocation(transform,vec(ahead))
  return point(at),math.atan(nextAt.Y-at.Y,nextAt.X-at.X),source
 end
 function N.sample(ctx,world,includeTraffic)
  local hit={}
  -- Ignore our generated road meshes. Terrain is queried before adding its influencer.
  local ignored={ctx.player};for _,r in pairs(N.records)do if valid(r.actor)then ignored[#ignored+1]=r.actor end end
  for _,r in ipairs(ctx.surveyRoads or{})do if valid(r)then ignored[#ignored+1]=r end end
  local ok,comp
  for attempt=1,8 do
   ok=S:LineTraceSingle(ctx.player,{X=world.x,Y=world.y,Z=world.z+16000},{X=world.x,Y=world.y,Z=world.z-16000},0,false,ignored,0,hit,true,color,color,0)
   if not ok then break end;comp=hit.Component:Get()
   if valid(comp)and N.proceduralFoliage(comp)then ignored[#ignored+1]=comp:GetOwner()
   elseif valid(comp)and not includeTraffic and not comp:GetFullName():match('^ProceduralMeshComponent ')then
    local owner=comp:GetOwner()
    if comp:GetCollisionObjectType()==6 or(valid(owner)and owner:IsA(StaticFindObject('/Script/Engine.Pawn')))then ignored[#ignored+1]=owner else break end
   else break end
  end
  if not ok then return nil,'pending'end
  if not valid(comp)then return nil,'pending'end
  -- Refuse roofs/props: never pave over a POI. Native terrain uses procedural meshes.
  local name=comp:GetFullName()
  if not(name:match('^ProceduralMeshComponent ')and name:find('SantorLandscape',1,true))then N.lastObstacle=name;return nil,'obstacle'end
  if hit.ImpactNormal.Z<.89 then return nil,'steep'end
  return hit.ImpactPoint.Z
 end
 function N.proceduralFoliage(c)
  local name=c:GetFullName()
  return name:match('^HierarchicalInstancedStaticMeshComponent ')and name:find(':PersistentLevel.SLLandscapePCG_',1,true)
 end
 function N.clearFoliage(ctx,plan,batch)
  local pts,widths=N.shape(plan);local world={};for i,p in ipairs(pts)do world[i]=N.worldPoint(plan,p)end
  local actors=batch and batch.actors or FindAllOf('SLLandscapePCG')or{}
  if batch and not batch.actors then batch.actors=actors;batch.index=1 end
  local first=batch and batch.index or 1;local last=batch and math.min(#actors,first+15)or #actors
  local removed=0
  for actorIndex=first,last do local actor=actors[actorIndex]
   if valid(actor)and valid(actor:GetWorld())and actor:GetWorld():GetAddress()==ctx.worldAddress then
    local origin,extent={},{};actor:GetActorBounds(false,origin,extent,false)
    local segments={}
    for i=1,#world-1 do local a,b=world[i],world[i+1];local margin=N.pavedHalf*math.max(widths[i],widths[i+1])+100
     if math.max(a.x,b.x)+margin>=origin.X-extent.X and math.min(a.x,b.x)-margin<=origin.X+extent.X and math.max(a.y,b.y)+margin>=origin.Y-extent.Y and math.min(a.y,b.y)-margin<=origin.Y+extent.Y then
      segments[#segments+1]={Min={X=math.min(a.x,b.x)-margin,Y=math.min(a.y,b.y)-margin,Z=math.min(a.z,b.z)-2500},Max={X=math.max(a.x,b.x)+margin,Y=math.max(a.y,b.y)+margin,Z=math.max(a.z,b.z)+3500},IsValid=1}
     end
    end
    if #segments>0 then
    for _,rawComponent in ipairs(actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.HierarchicalInstancedStaticMeshComponent')))do
     local c=rawComponent:get()
     if valid(c)and N.proceduralFoliage(c)and valid(c.StaticMesh)then
     local bounds=c.StaticMesh:GetBoundingBox();local half=math.max(bounds.Max.X-bounds.Min.X,bounds.Max.Y-bounds.Min.Y)*.5
     local indices,seen={},{}
     for _,box in ipairs(segments)do
     for _,raw in ipairs(c:GetInstancesOverlappingBox(box,true))do
      local index=type(raw)=='number'and raw or raw:get();local tr={}
      if not seen[index]and c:GetInstanceTransform(index,tr,true)then
       seen[index]=true
       local at=point(tr.Translation);local extent=half*math.max(math.abs(tr.Scale3D.X),math.abs(tr.Scale3D.Y))
       for i=1,#world-1 do
        if P.segmentDistance(at,world[i],world[i+1])<N.pavedHalf*math.max(widths[i],widths[i+1])+extent+100 then indices[#indices+1]=index;break end
       end
      end
     end
     end
     if #indices>0 then table.sort(indices);assert(c:RemoveInstances(indices),'Native foliage corridor could not be cleared');removed=removed+#indices end
     end
    end
    end
   end
  end
  N.metrics.foliageRemoved=(N.metrics.foliageRemoved or 0)+removed
  if batch then batch.index=last+1 end
  return removed,last>=#actors
 end
 function N.plan(ctx,road,t,side,roads,connect)
  ctx.surveyRoads=roads
  local origin,yaw=N.anchor(road,t);if not origin then return nil,'pending'end
  local frame={origin=origin,yaw=yaw,side=side}
  local function sample(x,y,z)
   local q=N.worldPoint(frame,{x=x,y=y,z=z});local h,why=N.sample(ctx,q)
   if not h then return nil,why end
   return h-origin.z+80 -- Match the native road's terrain/render clearance.
  end
  local function clear(q,n)
   if n<3 then return true end
   local w=N.worldPoint(frame,q);local nearest={}
   ctx.manager:GetDistanceToClosestSpline(vec(w),nearest)
   if not nearest.X or (w.x-nearest.X)^2+(w.y-nearest.Y)^2<=2000^2 then return false end
   for _,other in pairs(D.plans)do
    local pts={};for i,p in ipairs(other.points)do pts[i]=N.worldPoint(other,p)end
    if P.roadDistance(w,pts)<2000 and P.flatDistance(w,origin)>3000 then return false end
   end
   return true
  end
  local plan,why
  local function finish(p)
   p.origin=origin;p.yaw=yaw;p.pool=N.signature
   local ok,reason=N.conform(ctx,p);if not ok then return nil,reason end
   local altitude=origin.z-ctx.land:GetHeightOffset()
   if not P.placeStops(p,N.pool,altitude,ctx.land.TerrainMaxHeight,(road.RoadIndex+t)*ctx.manager.RoadStep,function(e,node,s,stops)return N.placePOI(ctx,p,e,node,s,stops)end)then return nil,'insufficient safe POI space'end
   return P.validate(p)
  end
  if connect then
   local lastReason
   for _,ahead in ipairs({2,1})do
   local targetRoad
   for _,r in ipairs(roads or{})do if r.RoadIndex==road.RoadIndex+ahead and r.IsRoadInitialized then targetRoad=r;break end end
   if not targetRoad then return nil,'pending'end
   local target,targetYaw=N.anchor(targetRoad,t)
   if not target then return nil,'pending'end
   local dx,dy=target.x-origin.x,target.y-origin.y;local c,s=math.cos(yaw),math.sin(yaw)
   local localTarget={x=c*dx+s*dy,y=(-s*dx+c*dy)*side,z=target.z-origin.z,index=targetRoad.RoadIndex,t=t,yaw=targetYaw}
   for _,r in ipairs(roads or{})do if ahead==2 and r.RoadIndex==road.RoadIndex+1 then
    local mid=N.anchor(r,t);if mid then localTarget.midY=(-s*(mid.x-origin.x)+c*(mid.y-origin.y))*side end
   end end
   for variant=1,3 do
    plan,why=P.connect(ctx.seed,road.RoadIndex,side,localTarget,sample,clear,variant)
    if plan then plan,why=finish(plan);if plan then return plan end end
    if why=='pending'then break end
   end
   lastReason=why
   end
   return nil,lastReason
  else plan,why=P.make(ctx.seed,road.RoadIndex,side,sample,clear)end
  if not plan then return nil,why end
  return finish(plan)
 end
 function N.conform(ctx,plan)
  -- Do not excavate terrain below existing foliage, poles or player structures.
  plan.rolls={};for i=1,#plan.points do plan.rolls[i]=0 end
  for i=2,#plan.points do
   if not(plan.ending=='connection'and i==#plan.points)then
    local q=plan.points[i];local z,why=N.sample(ctx,N.worldPoint(plan,q))
    if not z then return nil,why end;q.z=z-plan.origin.z+80
   end
   local a,b=plan.points[i-1],plan.points[i]
   if not plan.legacy and math.abs(b.z-a.z)>P.flatDistance(a,b)*(plan.ending=='connection'and .25 or .20)then return nil,'terrain grade'end
   if i>2 and not(plan.ending=='connection'and i==#plan.points)then
    local t=P.tangent(plan.points,i);local len=math.sqrt(t.x*t.x+t.y*t.y)
    local heights={}
    for _,side in ipairs({-1,1})do
     local shoulder={x=b.x-t.y/len*650*side,y=b.y+t.x/len*650*side,z=b.z}
     local z,why=N.sample(ctx,N.worldPoint(plan,shoulder));if not z then return nil,why end
     heights[side]=z
    end
    local roll=math.atan((heights[1]-heights[-1])/1300)
    if math.abs(roll)>.24 then return nil,'shoulder grade'end
    plan.rolls[i]=roll
   end
  end
  if plan.ending=='bulb'then
   plan.capHeights={};local q=plan.points[#plan.points];local t=P.tangent(plan.points,#plan.points);local length=math.sqrt(t.x*t.x+t.y*t.y)
   local half=N.pavedHalf;local radius=math.max(1600,half*2.4);local theta0=math.pi-math.asin(half/radius);local center=math.sqrt(radius*radius-half*half)
   plan.capHalf=half
   for i=1,12 do local theta=theta0*(1-i/12);local distance=center+radius*math.cos(theta)
    local p={x=q.x+t.x/length*distance,y=q.y+t.y/length*distance,z=q.z};local h,why=N.sample(ctx,N.worldPoint(plan,p))
    if not h then if why=='pending'then return nil,why end;plan.ending='hammerhead';plan.capHeights=nil;break end
    local z=h-plan.origin.z+80
    if math.abs(z-q.z)>400 then plan.ending='hammerhead';plan.capHeights=nil;break end
    plan.capHeights[i]=z
   end
  end
  -- Test the actual Hermite surface between nodes, across both lanes. Never
  -- treat a clear centre line as proof that a road fits the surrounding ground.
  local ok,why=N.surface(ctx,plan,true)
  if not ok then return nil,why end
  local endpoint=plan.ending=='connection'and #plan.points or 1
  local q=plan.points[endpoint];local yaw=plan.ending=='connection'and plan.target.yaw-plan.yaw or 0
  local p={x=q.x+math.sin(yaw)*1100*plan.side,y=q.y-math.cos(yaw)*1100,z=q.z}
  local z,reason=N.sample(ctx,N.worldPoint(plan,p));if not z then return nil,reason end
  plan.exitSignZ=z-plan.origin.z
  if plan.ending=='hammerhead'then
   local last=plan.points[#plan.points];local t=P.tangent(plan.points,#plan.points);local len=math.sqrt(t.x*t.x+t.y*t.y)
   local z,reason=N.sample(ctx,N.worldPoint(plan,{x=last.x+t.x/len*300,y=last.y+t.y/len*300,z=last.z}))
   if not z then return nil,reason end;plan.constructionSignZ=z-plan.origin.z
  end
  plan.clearanceVersion=1
  return true
 end
 function N.refit(ctx,original)
  local function fit(plan)
   local ok,why=N.conform(ctx,plan);if not ok then return nil,why end
   local points={};for i,q in ipairs(plan.points)do points[i]=N.worldPoint(plan,q)end
   for i=3,#points-2 do local w=points[i]
    if P.flatDistance(w,points[1])>3000 and(plan.ending~='connection'or P.flatDistance(w,points[#points])>3000)then
     local nearest={};ctx.manager:GetDistanceToClosestSpline(vec(w),nearest)
     if not nearest.X or P.flatDistance(w,point(nearest))<1800 then return nil,'road clearance'end
     for key,other in pairs(D.plans)do if key~=plan.key then
      local road={};for j,q in ipairs(other.points)do road[j]=N.worldPoint(other,q)end
      if P.roadDistance(w,road)<1800 then return nil,'detour clearance'end
     end end
    end
   end
   if not plan.legacy then
    for _,poi in ipairs(plan.pois)do
     local f=N.footprint(poi.path,N.poiTransform(plan,poi))
     if not f or P.roadDistance(f,points)<f.radius+1400 then return nil,'POI clearance'end
    end
   end
   return P.validate(plan)
  end
  local plan,why=fit(P.copy(original))
  if plan or why=='pending'then return plan,why end
  -- Native POIs and terrain LODs can settle after the initial survey. Reuse
  -- the bounded corridor adjustment without moving junctions or saved POIs.
  for _,shift in ipairs({500,-500,1000,-1000,2000,-2000,4000,-4000,6000,-6000})do
   local candidate=P.copy(original)
   local axis=candidate.ending=='connection'and'y'or'x'
   for i=3,#candidate.points-1 do candidate.points[i][axis]=candidate.points[i][axis]+shift*math.min(1,(i-2)/4,(#candidate.points-i)/4)end
   plan,why=fit(candidate);if plan or why=='pending'then return plan,why end
  end
  return nil,why
 end
 function N.migrate(ctx,old)
  if old.schema==2 and old.clearanceVersion==1 then
   local safe,why=N.surface(ctx,old,false);if safe then return old end
   if why=='pending'then return nil,why end
   return N.refit(ctx,old)
  end
  local plan=P.copy(old);plan.schema=2;plan.legacy=true
  -- Native saved levels retain their original transforms and suffixes.
  for _,poi in ipairs(plan.pois)do poi.transform=copyTransform(N.poiTransform(old,poi))end
  local why;plan,why=N.refit(ctx,plan);if not plan then return nil,why end
  P.placeStops(plan,N.pool,plan.origin.z-ctx.land:GetHeightOffset(),ctx.land.TerrainMaxHeight,plan.index*ctx.manager.RoadStep,function(e,node,s,stops)return N.placePOI(ctx,plan,e,node,s,stops)end)
  return P.validate(plan)
 end
 function N.shape(plan)
  local pts=P.copy(plan.points);local widths={};local rolls={};for i=1,#pts do widths[i]=1;rolls[i]=plan.rolls and plan.rolls[i]or 0 end
  widths[1]=1.25
  if plan.ending=='bulb'then
   local last=pts[#pts];local t=P.tangent(pts,#pts);local len=math.sqrt(t.x*t.x+t.y*t.y)
   local half=plan.capHalf or N.pavedHalf;local radius=math.max(1600,half*2.4)
   local theta0=math.pi-math.asin(half/radius);local center=math.sqrt(radius*radius-half*half)
   for i=1,12 do local theta=theta0*(1-i/12);local distance=center+radius*math.cos(theta)
    pts[#pts+1]={x=last.x+t.x/len*distance,y=last.y+t.y/len*distance,z=plan.capHeights and plan.capHeights[i]or last.z}
    widths[#pts]=math.max(.025,radius*math.sin(theta)/half)
    rolls[#pts]=rolls[#plan.points]
   end
  end
  return pts,widths,rolls
 end
 function N.surface(ctx,plan,repair,first,last)
  local pts,widths,rolls=N.shape(plan);local samples={};local initial={};local rays=0
  first=first or 1;last=math.min(last or #pts-1,#pts-1)
  for i,p in ipairs(pts)do initial[i]=p.z end
  for i=first,last do
   local ta,tb=P.tangent(pts,i),P.tangent(pts,i+1)
   local count=math.max(1,math.ceil(P.distance(pts[i],pts[i+1])/500))
   for j=0,count do
    local t=j/count;local q=P.hermite(pts[i],pts[i+1],ta,tb,t)
    local a=P.hermite(pts[i],pts[i+1],ta,tb,math.max(0,t-.001));local b=P.hermite(pts[i],pts[i+1],ta,tb,math.min(1,t+.001))
    local dx,dy=b.x-a.x,b.y-a.y;local length=math.sqrt(dx*dx+dy*dy)
    local width=(widths[i]*(1-t)+widths[i+1]*t)*(N.pavedHalf+5)
    local roll=rolls[i]*(1-t)+rolls[i+1]*t
    local lo,hi=math.huge,-math.huge
    for _,offset in ipairs({-1,-.5,0,.5,1})do
     local w=N.worldPoint(plan,{x=q.x-dy/length*width*offset*math.cos(roll),y=q.y+dx/length*width*offset*math.cos(roll),z=q.z})
     local h,why=N.sample(ctx,w);if not h then return nil,why end
     local relative=h-plan.origin.z-width*offset*math.sin(roll)
     lo=math.min(lo,relative);hi=math.max(hi,relative)
     rays=rays+1
    end
    if hi-lo>220 then return nil,'cross-road terrain clearance'end
    local join=P.flatDistance(q,pts[1])<1400 or(plan.ending=='connection'and P.flatDistance(q,pts[#pts])<1400)
    -- Build with 80 cm clearance; retain a 40 cm safety buffer on subsequent
    -- checks instead of rebuilding for harmless centimetre-scale LOD changes.
    samples[#samples+1]={i=i,t=t,height=hi,clearance=join and 0 or(repair and 80 or 40)}
   end
  end
  for pass=1,(repair and 4 or 1)do
   local changes={};local safe=true
   for _,v in ipairs(samples)do
    local i=v.i;local q=P.hermite(pts[i],pts[i+1],P.tangent(pts,i),P.tangent(pts,i+1),v.t)
    local need=v.height+v.clearance-q.z
    if need>1 then
     safe=false
     if not repair then return nil,'terrain intersects road corridor'end
     for _,k in ipairs({i,i+1})do
      local locked=k==1 or(plan.ending=='connection'and k==#pts)
      if not locked then changes[k]=math.max(changes[k]or 0,need+5)
      elseif (k==i and v.t<.2)or(k==i+1 and v.t>.8)then return nil,'junction terrain clearance'end
     end
    end
   end
   if safe then
    local ignored={ctx.player}
    for _,r in pairs(N.records)do if valid(r.actor)then ignored[#ignored+1]=r.actor end end
    for _,r in ipairs(ctx.surveyRoads or{})do if valid(r)then ignored[#ignored+1]=r end end
    for i=first,last do
     local a,b=N.worldPoint(plan,pts[i]),N.worldPoint(plan,pts[i+1]);local hits={}
     local yaw=math.deg(math.atan(b.y-a.y,b.x-a.x))
     S:BoxTraceMultiForObjects(ctx.player,{X=a.x,Y=a.y,Z=a.z+180},{X=b.x,Y=b.y,Z=b.z+180},{X=40,Y=math.max(widths[i],widths[i+1])*N.pavedHalf+60,Z=120},{Pitch=0,Yaw=yaw,Roll=0},{1},false,ignored,0,hits,true,color,color,0)
     for _,hit in ipairs(hits)do
      if not hit.Component and hit.get then hit=hit:get()end
      if not hit.Component then return nil,'unavailable collision result'end
      local c=hit.Component:Get()
      if valid(c)and not c:GetFullName():find('SantorLandscape',1,true)and not N.proceduralFoliage(c)then N.lastObstacle=c:GetFullName();return nil,'static object in road corridor'end
     end
    end
    if repair then
     for i,p in ipairs(pts)do
      if i<=#plan.points then plan.points[i].z=p.z else plan.capHeights[i-#plan.points]=p.z end
      if i>1 and math.abs(p.z-pts[i-1].z)>P.flatDistance(p,pts[i-1])*(plan.ending=='connection'and .26 or .22)then return nil,'surface grade'end
     end
    end
    return true,#samples*5
   end
   for i,delta in pairs(changes)do pts[i].z=pts[i].z+delta;if pts[i].z-initial[i]>180 then return nil,'terrain cannot fit road'end end
  end
  return nil,'terrain cannot fit road'
 end
 local function add(actor,path)
  local c=actor:AddComponentByClass(StaticFindObject(path),true,identity(),false)
  assert(valid(c),'Unable to create '..path)
  c:SetMobility(2)
  c:K2_AttachToComponent(actor.RootComponent,FName('None'),0,0,0,false)
  c:K2_SetRelativeLocation({X=0,Y=0,Z=0},false,{},true)
  c:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  c:SetComponentTickEnabled(false)
  return c
 end
 local function spline(actor,points,land)
  local c=add(actor,'/Script/SantorLand.SLSplineInfluencer')
  c:ClearSplinePoints(false)
  for _,p in ipairs(points)do c:AddSplinePoint(vec(p),0,false)end
  for i=1,#points do
   local t=P.tangent(points,i);c:SetTangentsAtSplinePoint(i-1,vec(t),vec(t),0,false)
  end
  c:SetClosedLoop(false,false);c:UpdateSpline();c.InfluenceHeight=false;c.MaskFoliage=true
  return c
 end
 local stretch={'VStretch','VStretch 2','VStretch 2 PNEU','VStretch 3 PNEU','VStretch 4 PNEU','VStretch 5'}
 local function mesh(actor,s,i,source,startWidth,endWidth,materials,startRoll,endRoll)
  local c=add(actor,'/Script/Engine.SplineMeshComponent');c:SetMobility(2)
  assert(c:SetStaticMesh(source.StaticMesh),'Native road mesh refused')
  local length=s:GetDistanceAlongSplineAtSplinePoint(i+1)-s:GetDistanceAlongSplineAtSplinePoint(i)
  local nativeLength=P.distance(point(source:GetStartPosition()),point(source:GetEndPosition()))
  local bucket=math.max(1,math.floor(length/50+.5));local mats=materials[bucket]
  for j=0,source:GetNumMaterials()-1 do
   if mats and mats[j]then c:SetMaterial(j,mats[j])else
    local parent=source:GetMaterial(j)
    -- CreateDynamicMaterialInstance returns SourceMaterial unchanged when it is
    -- already a MID. Start from its constant parent so native roads are never edited.
    local base=parent.Parent;c:SetMaterial(j,base)
    local mid=c:CreateDynamicMaterialInstance(j,base,FName('None'))
    assert(valid(mid),'Native road material unavailable')
    assert(mid:GetAddress()~=parent:GetAddress(),'Refusing to edit a shared native material')
    mid:CopyParameterOverrides(parent)
    for _,name in ipairs(stretch)do mid:SetScalarParameterValue(FName(name),parent:K2_GetScalarParameterValue(FName(name))*bucket*50/nativeLength)end
    materials[bucket]=materials[bucket]or{};materials[bucket][j]=mid
   end
  end
  c:SetForwardAxis(source:GetForwardAxis(),false)
  c.bSmoothInterpRollScale=false
  -- Taper the native camber with the very narrow cul-de-sac tip. Keeping its
  -- full cross-section height while shrinking width creates a steep ridge.
  c:SetStartScale({X=startWidth or 1,Y=math.min(1,startWidth or 1)},false);c:SetEndScale({X=endWidth or 1,Y=math.min(1,endWidth or 1)},false)
  c:SetStartRoll(startRoll or 0,false);c:SetEndRoll(endRoll or 0,false)
  c:SetStartAndEnd(s:GetLocationAtSplinePoint(i,0),s:GetTangentAtSplinePoint(i,0),s:GetLocationAtSplinePoint(i+1,0),s:GetTangentAtSplinePoint(i+1,0),true)
  c:SetCollisionProfileName(FName('BlockAll'),true);c:SetCollisionEnabled(3);c:SetGenerateOverlapEvents(false)
  return c
 end
 function N.build(ctx,plan,source)
  if N.records[plan.key]then return N.records[plan.key]end
  assert(valid(source),'Native road material not ready')
  local tr=identity(vec(plan.origin),plan.yaw)
  local a=G:BeginDeferredActorSpawnFromClass(ctx.player,StaticFindObject('/Script/Engine.StaticMeshActor'),tr,1,nil,0)
  assert(valid(a),'Unable to spawn detour')
  local rec={actor=a,plan=plan,splines={},meshes={},materials={}};N.records[plan.key]=rec
  local ok,err=xpcall(function()
   G:FinishSpawningActor(a,tr,0);a.StaticMeshComponent:SetMobility(2);a.StaticMeshComponent:SetCollisionEnabled(0)
   a:SetReplicates(false);a:SetActorTickEnabled(false)
   a.Tags={FName('BeyondDetours'),FName('BDTR_'..ctx.seed..'_'..plan.key)}
   local pts,widths,rolls=N.shape(plan);for _,p in ipairs(pts)do p.y=p.y*plan.side end
   local last=pts[#pts];local t=P.tangent(pts,#pts);local len=math.sqrt(t.x*t.x+t.y*t.y);local dx,dy=t.x/len,t.y/len
   local s=spline(a,pts,ctx.land);rec.splines[1]=s;rec.roadSpline=s
   for i,width in ipairs(widths)do s:SetScaleAtSplinePoint(i-1,{X=width,Y=width,Z=1},false)end
   s:UpdateSpline()
   for i=0,#pts-2 do
    rec.meshes[#rec.meshes+1]=mesh(a,s,i,source,widths[i+1],widths[i+2],rec.materials,-rolls[i+1]*plan.side,-rolls[i+2]*plan.side)
   end
   for _,inf in ipairs(rec.splines)do ctx.land:AddSplineInfluencer(inf)end
   N.clearFoliage(ctx,plan)
   if plan.ending=='hammerhead'then N.constructionSign(rec,last,dx,dy)end
   N.exitSign(rec)
  end,debug.traceback)
  if not ok then N.remove(ctx,plan.key);error(err)end
  N.metrics.builds=N.metrics.builds+1;return rec
 end
 function N.poiTransform(plan,poi)
  if poi.transform then return poi.transform end
  local e=assert(N.byPath[poi.path],'POI is no longer in the native pool')
  local q=N.worldPoint(plan,plan.points[poi.node]);local t=P.tangent(plan.points,poi.node)
  local yaw=plan.yaw+math.atan(t.y*plan.side,t.x)+(poi.side==-1 and math.pi or 0)
  local offset=e.template.UseCustomSideOffset and e.template.CustomSideOffset or N.sideOffset
  q.x=q.x-math.sin(yaw)*offset;q.y=q.y+math.cos(yaw)*offset
  -- Preserve the full authored local transform; circuit rotations, for example, are non-identity.
  return M:ComposeTransforms(e.template.Transform,identity(vec(q),yaw))
 end
 function N.footprint(path,transform)
  local b=N.footprints[path];if not b then return nil end
  local c=M:TransformLocation(transform,{X=b.x,Y=b.y,Z=0})
  local s=transform.Scale3D;return {x=c.X,y=c.Y,radius=b.radius*math.max(math.abs(s.X),math.abs(s.Y))}
 end
 function N.placePOI(ctx,plan,e,node,side,stops)
  if not N.footprints[e.path]then return end
  local q=N.worldPoint(plan,plan.points[node]);local t=P.tangent(plan.points,node)
  local yaw=plan.yaw+math.atan(t.y*plan.side,t.x)+(side==-1 and math.pi or 0)
  local radius=N.footprints[e.path].radius;local authored=e.template.UseCustomSideOffset and e.template.CustomSideOffset or N.sideOffset
  local sign=authored<0 and -1 or 1
  local offset=sign*math.max(math.abs(authored),radius+2200)
  local base={x=q.x-math.sin(yaw)*offset,y=q.y+math.cos(yaw)*offset,z=q.z}
  local transform=copyTransform(M:ComposeTransforms(e.template.Transform,identity(vec(base),yaw)))
  local footprint=N.footprint(e.path,transform);if not footprint or footprint.radius>35000 then return end
  -- Authored levels are often off-centre relative to their origin. Offset the
  -- whole footprint, not just the origin, beyond the road's shoulder.
  local nx,ny=-math.sin(yaw),math.cos(yaw)
  local separation=((footprint.x-q.x)*nx+(footprint.y-q.y)*ny)*sign
  if separation<footprint.radius+2000 then
   local shift=(footprint.radius+2000-separation)*sign
   transform.Translation.X=transform.Translation.X+nx*shift;transform.Translation.Y=transform.Translation.Y+ny*shift
   base.x=base.x+nx*shift;base.y=base.y+ny*shift;footprint=N.footprint(e.path,transform)
  end
  local points={};for i,p in ipairs(plan.points)do points[i]=N.worldPoint(plan,p)end
  if P.roadDistance(footprint,points)<footprint.radius+1400 then return end
  if plan.ending=='bulb'then
   local p=plan.points[#plan.points];local t=P.tangent(plan.points,#plan.points);local len=math.sqrt(t.x*t.x+t.y*t.y)
   local c=N.worldPoint(plan,{x=p.x+t.x/len*2000,y=p.y+t.y/len*2000,z=p.z})
   if P.flatDistance(footprint,c)<footprint.radius+3200 then return end
  end
  local nearest={};ctx.manager:GetDistanceToClosestSpline({X=footprint.x,Y=footprint.y,Z=q.z},nearest)
  if not nearest.X or P.flatDistance(footprint,point(nearest))<footprint.radius+2000 then return end
  local occupied={}
  for _,p in ipairs(stops)do occupied[#occupied+1]=N.footprint(p.path,N.poiTransform(plan,p))end
  for _,other in pairs(D.plans)do
   if other.key~=plan.key then
    local road={};for i,p in ipairs(other.points)do road[i]=N.worldPoint(other,p)end
    if P.roadDistance(footprint,road)<footprint.radius+1400 then return end
    for _,p in ipairs(other.pois)do occupied[#occupied+1]=N.footprint(p.path,N.poiTransform(other,p))end
   end
  end
  local nativeTooClose=false
  ctx.spawner.LevelsRep:ForEach(function(_,raw)local l=raw:get();local path=l.WorldSoftObjectPtrPath:ToString()
   if P.flatDistance(point(transform.Translation),point(l.Transform.Translation))<31000 then nativeTooClose=true end
   local f=N.footprint(path,l.Transform);if f then occupied[#occupied+1]=f end
  end)
  if nativeTooClose then return end
  for _,f in ipairs(occupied)do if f and P.flatDistance(footprint,f)<footprint.radius+f.radius+1500 then return end end
  -- Match the native spawner's duplicate-distance rule as well as full footprints.
  for _,p in ipairs(stops)do local tr=N.poiTransform(plan,p);if P.flatDistance(base,point(tr.Translation))<31000 then return end end
  local minimum,maximum=math.huge,-math.huge;local centerHeight
  for _,d in ipairs({{0,0},{1,0},{-1,0},{0,1},{0,-1},{.7,.7},{-.7,.7},{.7,-.7},{-.7,-.7}})do
   local z=N.sample(ctx,{x=footprint.x+d[1]*footprint.radius,y=footprint.y+d[2]*footprint.radius,z=base.z},true)
   if not z then return end;centerHeight=centerHeight or z;minimum=math.min(minimum,z);maximum=math.max(maximum,z)
  end
  local relief=footprint.radius>5000 and math.min(1000,footprint.radius*.18)or footprint.radius*.08
  if maximum-minimum>relief then return end
  transform.Translation.Z=centerHeight+e.template.Transform.Translation.Z
  return {transform=transform,radius=footprint.radius}
 end
 local function signBoard(rec,at,yaw)
  local sign=add(rec.actor,'/Script/Engine.StaticMeshComponent')
  local asset=LoadAsset('/Game/Roadside/VOL2/Meshes/LP/SM_Sign_Road_Set_01a1.SM_Sign_Road_Set_01a1');sign:SetStaticMesh(asset)
  sign:K2_SetRelativeLocation(vec(at),false,{},true)
  sign:K2_SetRelativeRotation({Pitch=0,Yaw=math.deg(yaw),Roll=0},false,{},true)
  sign:SetRelativeScale3D({X=2,Y=1,Z=1});sign:SetCollisionEnabled(3)
  -- Native sign geometry, with a plain face so no unrelated printed legend remains.
  local mat=LoadAsset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial')
  sign:SetMaterial(0,mat)
  return sign
 end
 function N.constructionSign(rec,last,dx,dy)
  local at={x=last.x+dx*300,y=last.y+dy*300,z=rec.plan.constructionSignZ or last.z-80}
  local yaw=math.atan(dy,dx)-math.pi*.5;signBoard(rec,at,yaw)
  local label=add(rec.actor,'/Script/Engine.TextRenderComponent');label:K2_SetText(FText('UNDER\nCONSTRUCTION'));label:SetWorldSize(15);label:SetHorizontalAlignment(1)
  label:SetTextRenderColor({R=15,G=15,B=15,A=255})
  label:K2_SetRelativeLocation({X=at.x-dx*4,Y=at.y-dy*4,Z=at.z+220},false,{},true)
  label:K2_SetRelativeRotation({Pitch=0,Yaw=math.deg(math.atan(dy,dx))+180,Roll=0},false,{},true)
 end
 function N.exitSign(rec)
  local plan=rec.plan;local endpoint=plan.ending=='connection'and #plan.points or 1
  local q=plan.points[endpoint];local yaw=plan.ending=='connection'and plan.target.yaw-plan.yaw or 0
  -- Put the board across the junction, outside the carriageway, facing the branch.
  local at={x=q.x+math.sin(yaw)*1100*plan.side,y=q.y*plan.side-math.cos(yaw)*1100*plan.side,z=plan.exitSignZ or q.z-80}
  signBoard(rec,at,yaw)
  local cube=LoadAsset('/Engine/BasicShapes/Cube.Cube');local material=LoadAsset('/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial')
  -- A geometric arrow is readable from either face and always points along the
  -- increasing main-road index. No font glyph or camera-relative left/right guess.
  for _,face in ipairs({-1,1})do
   for _,bar in ipairs({{x=-10,z=0,length=65,pitch=0},{x=24,z=11,length=34,pitch=-45},{x=24,z=-11,length=34,pitch=45}})do
    local c=add(rec.actor,'/Script/Engine.StaticMeshComponent');c:SetStaticMesh(cube);c:SetMaterial(0,material)
    local mid=c:CreateDynamicMaterialInstance(0,material,FName('None'));mid:SetVectorParameterValue(FName('Color'),{R=.015,G=.015,B=.015,A=1})
    c:SetRelativeScale3D({X=bar.length/100,Y=.012,Z=.065});c:SetCollisionEnabled(0)
    c:K2_SetRelativeRotation({Pitch=bar.pitch,Yaw=math.deg(yaw),Roll=0},false,{},true)
    c:K2_SetRelativeLocation({X=at.x+math.cos(yaw)*bar.x-math.sin(yaw)*4*face,Y=at.y+math.sin(yaw)*bar.x+math.cos(yaw)*4*face,Z=at.z+205+bar.z},false,{},true)
   end
  end
 end
 function N.spawnPOIs(ctx,plan,targets)
  if not ctx.host then return end
  local existing={}
  ctx.spawner.LevelsRep:ForEach(function(_,r)local e=r:get();existing[e.LevelLoad:ToString()]=true end)
  for i,poi in ipairs(plan.pois)do
   local suffix='BDv1_'..tostring(ctx.seed):gsub('-','n')..'_'..plan.key..'_'..i
   local found=false;for name in pairs(existing)do if name:sub(-#suffix)==suffix then found=true;break end end
   local transform=N.poiTransform(plan,poi);local p=transform.Translation
   if not found then
    local e=assert(N.byPath[poi.path],'Selected native POI disappeared');local t=e.template
    -- Native FLSLevel resolves this serialized path before consulting World. Do not
    -- retain/pass a borrowed TSoftObjectPtr from a data-asset array callback.
    ctx.spawner:AddLevel({Transform=transform,WorldSoftObjectPtrPath=e.path,AlwaysVisible=t.AlwaysVisible,UseCustomSideOffset=t.UseCustomSideOffset,CustomSideOffset=t.CustomSideOffset,CreationTime=t.CreationTime,HasBeenInitialized=false},suffix)
    N.metrics.poiAttempts=N.metrics.poiAttempts+1
   end
  end
  -- Register lightweight descriptors together to reserve native spacing. The
  -- native level streamer, not this descriptor list, loads actors by proximity.
  local count=0
  ctx.spawner.LevelsRep:ForEach(function(_,r)local name=r:get().LevelLoad:ToString()
   for i in ipairs(plan.pois)do
    local suffix='BDv1_'..tostring(ctx.seed):gsub('-','n')..'_'..plan.key..'_'..i
    if name:sub(-#suffix)==suffix then count=count+1;break end
   end
  end)
  return plan.legacy or count==#plan.pois
 end
 function N.remove(ctx,key)
  local r=N.records[key];if not r then return end
  if ctx and valid(ctx.land)then for _,s in ipairs(r.splines)do if valid(s)then ctx.land:RemoveSplineInfluencer(s)end end end
  if valid(r.actor)then r.actor:K2_DestroyActor()end;N.records[key]=nil;N.metrics.removes=N.metrics.removes+1
 end
 function N.cleanOrphans(ctx)
  -- Ownership is explicit. Never sweep arbitrary actors, native levels, or structures.
  for _,a in ipairs(FindAllOf('StaticMeshActor')or{})do
   if valid(a)and valid(a:GetWorld())and a:GetWorld():GetAddress()==ctx.worldAddress and a:ActorHasTag(FName('BeyondDetours'))then
    local owned=false;for _,r in pairs(N.records)do if valid(r.actor)and r.actor:GetAddress()==a:GetAddress()then owned=true;break end end
    if not owned then
     local list=a:K2_GetComponentsByClass(StaticFindObject('/Script/SantorLand.SLSplineInfluencer'))
     for _,v in ipairs(list)do local s=v:get();if valid(s)then ctx.land:RemoveSplineInfluencer(s)end end
     a:K2_DestroyActor();D.log('Removed an orphaned Beyond Detours road')
    end
   end
  end
 end
 function N.reset(ctx)
  local keys={};for k in pairs(N.records)do keys[#keys+1]=k end;for _,k in ipairs(keys)do N.remove(ctx,k)end
  N.pool={};N.byPath={};N.asset=nil;N.signature=nil
 end
 return N
end
