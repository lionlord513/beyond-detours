local root=assert(...)
local P=dofile(root..'/mod/BeyondDetours/Scripts/planner.lua')
local J=dofile(root..'/mod/BeyondDetours/Scripts/json.lua')
local pool={
 {path='/Game/Cow',weight=.5,minDistance=0,minHeight=0,maxHeight=1,minSlope=-180,maxSlope=180,once=0},
 {path='/Game/Garage',weight=1,minDistance=0,minHeight=0,maxHeight=1,minSlope=-180,maxSlope=180,once=0},
 {path='/Game/Motel',weight=1,minDistance=0,minHeight=0,maxHeight=1,minSlope=-180,maxSlope=180,once=0},
 {path='/Game/Story',weight=100,minDistance=0,minHeight=0,maxHeight=1,minSlope=-180,maxSlope=180,once=50000},
}
local unique={};local count=0
for seed=1,500 do
 for _,side in ipairs({-1,1})do
  local function make()
   local p=assert(P.make(seed,7,side,function(x,y)return math.sin(y/14000)*300+math.sin(x/10000)*150 end))
   p.origin={x=100000,y=-10000,z=3000};p.yaw=.3;p.pool='123'
   return P.populate(p,pool,3000,400000,350000,1)
  end
  local p,q=make(),make();assert(J.encode(p)==J.encode(q),'Seed or iteration-order instability')
  P.validate(J.decode(J.encode(p)))
  assert(#p.pois>=1 and #p.pois<=2)
  local used={};for _,v in ipairs(p.pois)do assert(not used[v.path]and v.path~='/Game/Story');used[v.path]=true end
  local sampled={}
  for i=1,#p.points-1 do
   local a,b=p.points[i],p.points[i+1];local ta,tb=P.tangent(p.points,i),P.tangent(p.points,i+1)
   for j=0,10 do
    local v=P.hermite(a,b,ta,tb,j/10)
    if #sampled>0 and j>0 then local last=sampled[#sampled];assert(v.y>last.y,'Curve doubled back');local flat=math.sqrt((v.x-last.x)^2+(v.y-last.y)^2);assert(math.abs(v.z-last.z)/flat<.13,'Undriveable grade')end
    sampled[#sampled+1]=v
   end
  end
  unique[J.encode(p.points)]=true;count=count+1
 end
end
local n=0;for _ in pairs(unique)do n=n+1 end;assert(n==count,'Repeated route geometry')
local restricted={path='/Game/Test',weight=1,minDistance=1000,minHeight=.2,maxHeight=.6,minSlope=-12,maxSlope=12,once=0}
assert(not P.eligible(restricted,999,.4,0));assert(not P.eligible(restricted,2000,.1,0));assert(not P.eligible(restricted,2000,.7,0));assert(not P.eligible(restricted,2000,.4,13));assert(P.eligible(restricted,1000,.2,-12))
local rejected,why=P.make(123,5,1,function()return nil,'pending'end);assert(not rejected and why=='pending')
local cliff=P.make(123,5,1,function()return 50000 end);assert(not cliff,'Cliff accepted')
local tally={};local random=P.rng(5678)
for i=1,30000 do local e=P.choose(pool,random,100000,.5,0,{});tally[e.path]=(tally[e.path]or 0)+1 end
assert(tally['/Game/Cow']>5400 and tally['/Game/Cow']<6600,'Native relative weight not respected')
assert(not tally['/Game/Story'])
print('PASS '..count..' reproducible distinct roads; spline grade, dead ends, native eligibility, weights and JSON round trips')
