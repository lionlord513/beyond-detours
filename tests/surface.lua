local root=assert(...);local P=dofile(root..'/mod/BeyondDetours/Scripts/planner.lua')
local height=function()return 0 end;local obstacle=false;local rays=0
local terrain={IsValid=function()return true end,GetFullName=function()return 'ProceduralMeshComponent SantorLandscape terrain'end}
local pole={IsValid=function()return true end,GetFullName=function()return 'Native telephone pole'end}
local S={LineTraceSingle=function(_,ctx,a,b,channel,complex,ignored,draw,hit)
 rays=rays+1;hit.Component={Get=function()return terrain end};hit.ImpactPoint={Z=height(a.X,a.Y)};hit.ImpactNormal={Z=1};return true
end,BoxTraceMultiForObjects=function(_,ctx,a,b,size,rotation,types,complex,ignored,draw,hits)
 if obstacle then hits[1]={Component={Get=function()return pole end}}end;return obstacle
end}
StaticFindObject=function(path)if path:find('KismetSystem')then return S end;return{}end
local D={planner=P,valid=function(o)return o and o:IsValid()end}
local N=dofile(root..'/mod/BeyondDetours/Scripts/native.lua')(D)
local p={origin={x=0,y=0,z=0},yaw=0,side=1,ending='hammerhead',points={{x=0,y=0,z=80},{x=0,y=2000,z=80},{x=0,y=4000,z=80},{x=0,y=6000,z=80}}}
assert(N.surface({},p,false));assert(rays>=75)
height=function()return 20 end
assert(N.surface({},p,false),'Harmless terrain settling caused road removal')
height=function(x,y)return y>2400 and y<2600 and math.abs(x)>300 and 120 or 0 end
assert(not N.surface({},p,false),'Off-centre terrain penetration was accepted')
local repaired=P.copy(p);assert(N.surface({},repaired,true));assert(N.surface({},repaired,false))
height=function(x,y)return y>2400 and y<2600 and 600 or 0 end
assert(not N.surface({},P.copy(p),true),'Unsafe elevated road was accepted')
height=function()return 0 end;obstacle=true
assert(not N.surface({},p,false),'Pole inside the swept corridor was accepted')
obstacle=false
for i=1,#p.points-1 do local before=rays;assert(N.surface({},p,false,i,i));assert(rays-before<=25,'Incremental check exceeded one segment')end
print('PASS full-width/inter-node terrain rejection, bounded elevation repair, static obstacle rejection and incremental checks')
