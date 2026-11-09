local root=assert(...);local P=dofile(root..'/mod/BeyondDetours/Scripts/planner.lua')
local J=dofile(root..'/mod/BeyondDetours/Scripts/json.lua')
local connections,total=0,0
for seed=1,100 do
 for _,side in ipairs({-1,1})do
  local target={x=100000,y=2500,z=200,index=6}
  local function sample(x,y)return x*.002+math.sin(y/12000)*80 end
  local p=assert(P.connect(seed,4,side,target,sample))
  local q=assert(P.connect(seed,4,side,target,sample))
  assert(J.encode(p)==J.encode(q));p.origin={x=0,y=0,z=0};p.yaw=0;p.pool='1';P.validate(p)
  assert(P.distance(p.points[#p.points],target)==0)
  for i=2,#p.points do assert(p.points[i].x>p.points[i-1].x)end
 end
 for index=2,50 do
  local full=P.junction(seed,index,1);local low=P.junction(seed,index,.2)
  assert(not P.junction(seed,index,0));assert(not low or full)
  if full then total=total+1;if full.connect then connections=connections+1 end end
 end
end
assert(connections/total>.70 and connections/total<.85)
local p=assert(P.connect(10,4,1,{x=100000,y=0,z=0,index=6},function()return 0 end))
p.origin={x=0,y=0,z=0};p.yaw=0;p.pool='1'
p.target.index=3;assert(not pcall(P.validate,p),'Backward reconnection accepted')
assert(P.roadDistance({x=5,y=4},{{x=0,y=0},{x=10,y=0}})==4)
print('PASS 200 reproducible forward connections, endpoint validation, road clearance, and monotonic native density gating')
