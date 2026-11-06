local root=assert(...)
local P=dofile(root..'/mod/BeyondDetours/Scripts/planner.lua')
local J=dofile(root..'/mod/BeyondDetours/Scripts/json.lua')
local time=5;local sent={}
local world={GetAddress=function()return 10 end,IsValid=function()return true end}
local pc={IsValid=function()return true end,HasAuthority=function()return true end,GetAddress=function()return 20 end,GetWorld=function()return world end,GetFullName=function()return 'remote pc'end,ClientMessage=function(_,text)sent[#sent+1]=J.decode(text:sub(7))end}
pc.PlayerControlled={IsValid=function()return true end,K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end}
StaticFindObject=function()return {GetTimeSeconds=function()return time end}end
FName=function(v)return v end
local D={version='0.1.0',planner=P,json=J,plans={},valid=function(o)return o and o:IsValid()end,log=function()end,dropRoads=function()end,native={signature='42',byPath={['/Game/Garage']={}}}}
D.ctx={host=true,world='session-a',worldAddress=10,seed=123,player=pc.PlayerControlled}
local N=dofile(root..'/mod/BeyondDetours/Scripts/network.lua')(D)
N.server(pc,{op='hello',version='different'});assert(sent[1].op=='mismatch');sent={}
N.server(pc,{op='hello',version=D.version});assert(sent[1].op=='ready'and sent[1].session=='session-a')
local plan=assert(P.make(123,3,1,function()return 0 end));plan.origin={x=0,y=0,z=0};plan.yaw=0;plan.pool='42';plan.pois={{path='/Game/Garage',node=4,side=1}}
D.plans[plan.key]=plan
N.tick();assert(sent[2].op=='plan');local packet=sent[2]
N.tick();assert(#sent==2,'Packets flood while unchanged')
time=22;N.server(pc,{op='hello',version=D.version});N.tick();assert(sent[#sent].op=='plan','Pruned client layout is not resent')
N.reset();D.ctx.host=false;D.plans={}
N.client({op='ready',version=D.version,session='session-a',seed=123,pool='42'});assert(N.ready)
N.client(packet);assert(D.plans[plan.key]and J.encode(D.plans[plan.key])==J.encode(plan))
D.plans={};N.client({op='plan',session='old-session',plan=plan});assert(not next(D.plans),'Old-world packet applied')
N.client({op='ready',version=D.version,session='session-b',seed=123,pool='wrong'});assert(not N.ready)
N.reset();assert(not N.ready and not N.session and not next(N.peers))
print('PASS protocol versions, session isolation, host plan transfer, resend after client culling, and reset')
