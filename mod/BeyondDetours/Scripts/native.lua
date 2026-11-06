return function(D)
 local N={pool={},byPath={},records={}};local P=D.planner;local valid=D.valid
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
 function N.context()
  local engine=FindFirstOf('GameEngine');if not valid(engine)or not valid(engine.GameViewport)then return end
  local pc=G:GetPlayerController(engine.GameViewport,0)
  if not valid(pc)or not pc:IsLocalPlayerController()then return end
  local p=pc.PlayerControlled
  if not valid(p)or not p.IsLoaded or not p.IsInitialized then return end
  local gs=G:GetGameState(p);if not valid(gs)then return end
  local world=gs:GetWorld();if not valid(world)then return end
  local manager
  for _,m in ipairs(FindAllOf('RoadManager')or{})do
   if valid(m)and valid(m:GetWorld())and m:GetWorld():GetAddress()==world:GetAddress()then manager=m;break end
  end
  if not valid(gs)or not valid(manager)or not valid(manager.Landscape)or not valid(gs.LSLevelSpawner)then return end
  return {pc=pc,player=p,gs=gs,manager=manager,land=manager.Landscape,spawner=gs.LSLevelSpawner,seed=gs.Seed,host=pc:HasAuthority(),world=gs:GetFullName()..':'..gs:GetAddress(),worldAddress=world:GetAddress()}
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
 function N.sample(ctx,world)
  local hit={}
  -- Ignore our generated road meshes. Terrain is queried before adding its influencer.
  local ignored={ctx.player};for _,r in pairs(N.records)do if valid(r.actor)then ignored[#ignored+1]=r.actor end end
  local ok=S:LineTraceSingle(ctx.player,{X=world.x,Y=world.y,Z=world.z+16000},{X=world.x,Y=world.y,Z=world.z-16000},0,false,ignored,0,hit,true,color,color,0)
  if not ok then return nil,'pending'end
  local comp=hit.Component:Get()
  if not valid(comp)then return nil,'pending'end
  -- Refuse roofs/props: never pave over a POI. Native terrain uses procedural meshes.
  local name=comp:GetFullName()
  if not name:find('SantorLandscape',1,true)then return nil,'obstacle'end
  if hit.ImpactNormal.Z<.89 then return nil,'steep'end
  return hit.ImpactPoint.Z
 end
 function N.plan(ctx,road,t,side)
  local origin,yaw=N.anchor(road,t);if not origin then return nil,'pending'end
  local frame={origin=origin,yaw=yaw,side=side}
  local function sample(x,y,z)
   local q=N.worldPoint(frame,{x=x,y=y,z=z});local h,why=N.sample(ctx,q)
   if not h then return nil,why end
   return h-origin.z+5 -- Small lift, with native road skirts blending the shoulder.
  end
  local function clear(q,n)
   if n<3 then return true end
   local w=N.worldPoint(frame,q);local nearest={}
   ctx.manager:GetDistanceToClosestSpline(vec(w),nearest)
   return nearest.X and (w.x-nearest.X)^2+(w.y-nearest.Y)^2>2000^2
  end
  local plan,why=P.make(ctx.seed,road.RoadIndex,side,sample,clear)
  if not plan then return nil,why end
  plan.origin=origin;plan.yaw=yaw;plan.pool=N.signature
  local altitude=origin.z-ctx.land:GetHeightOffset()
  P.populate(plan,N.pool,altitude,ctx.land.TerrainMaxHeight,road.RoadIndex*ctx.manager.RoadStep,N.maximum)
  if #plan.pois==0 then return nil,'no eligible native POI'end
  return P.validate(plan)
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
  c:SetClosedLoop(false,false);c:UpdateSpline();c.InfluenceHeight=true;c.MaskFoliage=true
  land:AddSplineInfluencer(c)
  return c
 end
 local function mesh(actor,s,i,source,startWidth,endWidth)
  local c=add(actor,'/Script/Engine.SplineMeshComponent');c:SetMobility(2)
  assert(c:SetStaticMesh(source.StaticMesh),'Native road mesh refused')
  for j=0,source:GetNumMaterials()-1 do c:SetMaterial(j,source:GetMaterial(j))end
  c:SetForwardAxis(source:GetForwardAxis(),false)
  c:SetStartScale({X=startWidth or 1,Y=1},false);c:SetEndScale({X=endWidth or 1,Y=1},false)
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
  local rec={actor=a,plan=plan,splines={},meshes={}};N.records[plan.key]=rec
  local ok,err=xpcall(function()
   G:FinishSpawningActor(a,tr,0);a.StaticMeshComponent:SetMobility(2);a.StaticMeshComponent:SetCollisionEnabled(0)
   a:SetReplicates(false);a:SetActorTickEnabled(false)
   local pts={};for _,q in ipairs(plan.points)do pts[#pts+1]={x=q.x,y=q.y*plan.side,z=q.z}end
   -- A broad, closed road head leaves room for a car to turn around.
   local last=pts[#pts];local t=P.tangent(pts,#pts);local len=math.sqrt(t.x*t.x+t.y*t.y);local dx,dy=t.x/len,t.y/len
   local capWidths={1.45,1.7,1.5,1.0,.08}
   local capStart=#pts
   for _,distance in ipairs({800,1600,2400,2850,3050})do
    pts[#pts+1]={x=last.x+dx*distance,y=last.y+dy*distance,z=last.z}
   end
   local s=spline(a,pts,ctx.land);rec.splines[1]=s;rec.roadSpline=s
   for i,width in ipairs(capWidths)do s:SetScaleAtSplinePoint(capStart+i-1,{X=width,Y=width,Z=1},false)end
   s:UpdateSpline()
   for i=0,#pts-2 do
    local w1,w2=1,1
    if i==0 then w1=1.25 end
    if i>=capStart-1 then
     local j=i-(capStart-1);w1=j==0 and 1 or capWidths[j];w2=capWidths[j+1]
    end
    rec.meshes[#rec.meshes+1]=mesh(a,s,i,source,w1,w2)
   end
   if plan.ending=='hammerhead'then
    local cross={{x=last.x-dy*1600,y=last.y+dx*1600,z=last.z},{x=last.x,y=last.y,z=last.z},{x=last.x+dy*1600,y=last.y-dx*1600,z=last.z}}
    local ss=spline(a,cross,ctx.land);rec.splines[#rec.splines+1]=ss
    rec.meshes[#rec.meshes+1]=mesh(a,ss,0,source,.15,.9);rec.meshes[#rec.meshes+1]=mesh(a,ss,1,source,.9,.15)
   end
  end,debug.traceback)
  if not ok then N.remove(ctx,plan.key);error(err)end
  return rec
 end
 function N.poiTransform(plan,poi)
  local e=assert(N.byPath[poi.path],'POI is no longer in the native pool')
  local q=N.worldPoint(plan,plan.points[poi.node]);local t=P.tangent(plan.points,poi.node)
  local yaw=plan.yaw+math.atan(t.y*plan.side,t.x)+(poi.side==-1 and math.pi or 0)
  local offset=e.template.UseCustomSideOffset and e.template.CustomSideOffset or N.sideOffset
  q.x=q.x-math.sin(yaw)*offset;q.y=q.y+math.cos(yaw)*offset
  -- Preserve the full authored local transform; circuit rotations, for example, are non-identity.
  return M:ComposeTransforms(e.template.Transform,identity(vec(q),yaw))
 end
 function N.spawnPOIs(ctx,plan)
  if not ctx.host then return end
  local existing={}
  ctx.spawner.LevelsRep:ForEach(function(_,r)local e=r:get();existing[e.LevelLoad:ToString()]=true end)
  for i,poi in ipairs(plan.pois)do
   local suffix='BDv1_'..tostring(ctx.seed):gsub('-','n')..'_'..plan.key..'_'..i
   local found=false;for name in pairs(existing)do if name:sub(-#suffix)==suffix then found=true;break end end
   if not found then
    local e=assert(N.byPath[poi.path],'Selected native POI disappeared');local t=e.template
    -- Native FLSLevel resolves this serialized path before consulting World. Do not
    -- retain/pass a borrowed TSoftObjectPtr from a data-asset array callback.
    ctx.spawner:AddLevel({Transform=N.poiTransform(plan,poi),WorldSoftObjectPtrPath=e.path,AlwaysVisible=t.AlwaysVisible,UseCustomSideOffset=t.UseCustomSideOffset,CustomSideOffset=t.CustomSideOffset,CreationTime=t.CreationTime,HasBeenInitialized=false},suffix)
   end
  end
 end
 function N.remove(ctx,key)
  local r=N.records[key];if not r then return end
  if ctx and valid(ctx.land)then for _,s in ipairs(r.splines)do if valid(s)then ctx.land:RemoveSplineInfluencer(s)end end end
  if valid(r.actor)then r.actor:K2_DestroyActor()end;N.records[key]=nil
 end
 function N.reset(ctx)
  local keys={};for k in pairs(N.records)do keys[#keys+1]=k end;for _,k in ipairs(keys)do N.remove(ctx,k)end
  N.pool={};N.byPath={};N.asset=nil;N.signature=nil
 end
 return N
end
