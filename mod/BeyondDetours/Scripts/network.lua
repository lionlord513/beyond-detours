-- Standalone transport using native owning-controller RPCs; no other mod is required.
return function(D)
 local N={peers={},hooks={},ready=false};local prefix='BDTR1 ';local G=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local function geometry(p)
  return D.json.encode({origin=p.origin,yaw=p.yaw,side=p.side,points=p.points,rolls=p.rolls,ending=p.ending,capHalf=p.capHalf,capHeights=p.capHeights,exitSignZ=p.exitSignZ,constructionSignZ=p.constructionSignZ,target=p.target})
 end
 local function clock()return D.ctx and G:GetTimeSeconds(D.ctx.player)or 0 end
 local function send(pc,p)
  local bytes=prefix..D.json.encode(p);assert(#bytes<30000,'Detour packet too large')
  pc:ClientMessage(bytes,FName('BeyondDetours'),0)
 end
 function N.server(pc,p)
  local ctx=D.ctx;if not ctx or not ctx.host or not D.valid(pc)or not pc:HasAuthority()or p.op~='hello'then return end
  if not D.valid(pc:GetWorld())or pc:GetWorld():GetAddress()~=ctx.worldAddress then return end
  local id=pc:GetAddress();local peer=N.peers[id]
  if peer and peer.name~=pc:GetFullName()then N.peers[id]=nil;peer=nil end
  if peer and clock()-peer.seen<1 then return end
  if p.version~=D.version then send(pc,{op='mismatch',version=D.version});return end
  if not peer then peer={pc=pc,name=pc:GetFullName(),sent={}};N.peers[id]=peer end
  peer.seen=clock()
  send(pc,{op='ready',version=D.version,session=ctx.world,seed=ctx.seed,pool=D.native.signature})
 end
 function N.client(p)
  local ctx=D.ctx;if not ctx or ctx.host then return end
  if p.op=='mismatch'then D.log('Host uses Beyond Detours '..tostring(p.version)..'; install the same version on every peer');return end
  if p.op=='ready'then
   if p.version~=D.version or p.seed~=ctx.seed or p.pool~=D.native.signature then N.ready=false;return end
   if N.session and N.session~=p.session then D.dropRoads();D.plans={}end
   N.session=p.session;N.ready=true;N.seen=clock()
  elseif p.op=='plan'and N.ready and p.session==N.session then
   local plan=D.planner.validate(p.plan)
   assert(plan.seed==ctx.seed and plan.pool==D.native.signature,'Host road does not match this world')
   for _,poi in ipairs(plan.pois)do assert(D.native.byPath[poi.path],'Host sent a non-native POI')end
   local built=D.native.records and D.native.records[plan.key]
   if built and(plan.blocked or plan.poiReady~=true or(built.plan and geometry(built.plan)~=geometry(plan)))then D.native.remove(ctx,plan.key)end
   D.plans[plan.key]=plan
  end
 end
 function N.install()
  if #N.hooks>0 then return end
  N.hooks[1]={RegisterHook('/Script/Engine.PlayerController:ServerExecRPC',function(c,msg)
   local text=msg:get():ToString();if text:sub(1,#prefix)~=prefix or #text>1000 then return end
   local pc=c:get();D.enqueue(function()N.server(pc,D.json.decode(text:sub(#prefix+1)))end)
  end)}
  N.hooks[2]={RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(c,msg)
   local text=msg:get():ToString();if text:sub(1,#prefix)~=prefix or #text>30000 then return end
   local pc=c:get();if not D.valid(pc)or not pc:IsLocalPlayerController()then return end
   D.enqueue(function()if D.ctx and D.valid(pc)and pc:IsLocalPlayerController()and pc:GetAddress()==D.ctx.pc:GetAddress()then N.client(D.json.decode(text:sub(#prefix+1)))end end)
  end)}
 end
 function N.tick()
  local ctx=D.ctx;if not ctx then return end
  local t=clock()
  if ctx.host then
   for id,peer in pairs(N.peers)do
    if not D.valid(peer.pc)or peer.name~=peer.pc:GetFullName()or t-peer.seen>20 then N.peers[id]=nil
    else
     local p=peer.pc.PlayerControlled
     if D.valid(p)then
      local at=p:K2_GetActorLocation()
      for key,plan in pairs(D.plans)do
       local nearby=false
       for _,q in ipairs(plan.points)do
        local w=D.native.worldPoint(plan,q);local dx,dy=w.x-at.X,w.y-at.Y
        if dx*dx+dy*dy<200000^2 then nearby=true;break end
       end
       if nearby and(not peer.sent[key]or t-peer.sent[key]>15)then
        send(peer.pc,{op='plan',session=ctx.world,plan=plan});peer.sent[key]=t;break
       end
      end
     end
    end
   end
  elseif t>=(N.helloAt or 0)then
   N.helloAt=t+4
   ctx.pc:ServerExecRPC(prefix..D.json.encode({op='hello',version=D.version}))
   if N.seen and t-N.seen>20 then N.ready=false end
  end
 end
 function N.reset()N.peers={};N.ready=false;N.session=nil;N.seen=nil;N.helloAt=nil end
 return N
end
