-- Pure deterministic geometry and native-pool selection. Centimetres internally.
local P={schema=2}
local pi=math.pi
function P.hash(s)
 local h=2166136261
 for i=1,#s do h=((h~s:byte(i))*16777619)&0xffffffff end
 h=((h~(h>>16))*0x85ebca6b)&0xffffffff
 h=((h~(h>>13))*0xc2b2ae35)&0xffffffff
 return (h~(h>>16))&0xffffffff
end
function P.rng(seed)
 local n=P.hash(tostring(seed));if n==0 then n=1 end
 return function()n=(n~(n<<13))&0xffffffff;n=(n~(n>>17))&0xffffffff;n=(n~(n<<5))&0xffffffff;return n/4294967296 end
end
function P.copy(x)
 if type(x)~='table'then return x end
 local r={};for k,v in pairs(x)do r[k]=P.copy(v)end;return r
end
function P.finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end
function P.distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
function P.junction(seed,index,chance)
 -- One irregularly placed junction in each 1.5 km cell. Never in the spawn chunk.
 if index<2 then return end
 local cell=math.floor((index-2)/3);local r=P.rng(seed..':junction:'..cell)
 if index~=2+cell*3+math.floor(r()*3)then return end
 local sides={r()<.5 and -1 or 1}
 if r()<.28 then sides[2]=-sides[1]end
 local t=.3+r()*.4
 -- A separate roll makes lower native LevelSpawn settings a stable subset.
 if chance~=nil and P.rng(seed..':density:'..cell)()>=clamp(chance,0,1)then return end
 return {sides=sides,t=t,cell=cell,connect=P.rng(seed..':connection:'..cell)()<.78}
end
function P.tangent(points,i)
 local a=points[math.max(1,i-1)];local b=points[math.min(#points,i+1)]
 local div=(i==1 or i==#points)and 1 or 2
 return {x=(b.x-a.x)/div,y=(b.y-a.y)/div,z=(b.z-a.z)/div}
end
function P.hermite(a,b,ta,tb,t)
 local t2,t3=t*t,t*t*t;local h1,h2,h3,h4=2*t3-3*t2+1,t3-2*t2+t,-2*t3+3*t2,t3-t2
 return {x=h1*a.x+h2*ta.x+h3*b.x+h4*tb.x,y=h1*a.y+h2*ta.y+h3*b.y+h4*tb.y,z=h1*a.z+h2*ta.z+h3*b.z+h4*tb.z}
end
function P.make(seed,index,side,sample,clear)
 local r=P.rng(seed..':detour-v1:'..index..':'..side)
 local target=40000+r()*45000;local step=2500
 local phase=r()*pi*2;local frequency=.2+r()*.25;local amplitude=.35+r()*.6
 local direction=r()<.5 and -1 or 1
 -- Coordinates: x follows the main road, y points outward, z is root-relative.
 local points={{x=0,y=0,z=0},{x=direction*700,y=900,z=0}}
 local length=P.distance(points[1],points[2]);local heading=direction*.5
 local reason
 for i=1,40 do
  if length>=target then break end
  local prev=points[#points];local wanted=math.sin(phase+i*frequency)*amplitude
  local center=clamp(heading+clamp(wanted-heading,-.23,.23),-1.0,1.0)
  local best,score,bestHeading
  -- Retry headings in a fixed order; no shared/global random state.
  for _,delta in ipairs({0,-.16,.16,-.32,.32})do
   local h=clamp(center+delta,-1.05,1.05)
   if math.abs(h-heading)<=.35 then
    local q={x=prev.x+math.sin(h)*step,y=prev.y+math.cos(h)*step,z=prev.z}
    local z,why=sample(q.x,q.y,prev.z)
    if why=='pending'then return nil,'pending'end
    if z and P.finite(z)and math.abs(q.x)<26000 then
     q.z=clamp(z,prev.z-step*.105,prev.z+step*.105)
     local cut=math.abs(q.z-z)
     local valid=cut<=400 and(not clear or clear(q,#points))
     if valid then local s=math.abs(h-center)*120+math.abs(q.z-prev.z)+cut*3;if not score or s<score then best,score,bestHeading=q,s,h end end
    end
   end
  end
  if not best then reason='terrain';break end
  points[#points+1]=best;heading=bestHeading;length=length+P.distance(prev,best)
 end
 if length<18000 then return nil,reason or'too short'end
 -- Ease the first approach into the surveyed elevation; no step at the junction.
 points[2].z=points[3].z*.22
 -- Light smoothing preserves terrain shape and limits abrupt grade changes.
 for _=1,2 do local old=P.copy(points)
  for i=3,#points-1 do points[i].z=(old[i-1].z+2*old[i].z+old[i+1].z)/4 end
 end
 local plan={schema=P.schema,key=index..'_'..(side==1 and'R'or'L'),seed=seed,index=index,side=side,points=points,pois={},length=length,ending=r()<.5 and'bulb'or'hammerhead'}
 return plan
end
function P.connect(seed,index,side,target,sample,clear,variant)
 if not target or target.x<25000 or target.x>125000 then return nil,'pending connection'end
 local r=P.rng(seed..':connect-v2:'..index..':'..side)
 local depth=(22000+r()*18000)*(({1,.55,.25})[variant or 1]or 1);local phase=r()*pi*2
 local count=math.ceil((target.x+depth*2)/2000)
 local points={};local length=0;local heading
 for i=0,count do
  local t=i/count;local wave=math.max(0,math.sin(pi*t))^.7
  local baseline=target.y*t+4*t*(1-t)*((target.midY or target.y*.5)-target.y*.5)
  local q={x=target.x*t,y=baseline+depth*wave*(1+.16*math.sin(t*4*pi+phase)*wave),z=target.z*t}
  if i==count then q={x=target.x,y=target.y,z=target.z}end
  if i>0 and i<count then
   local previous=points[#points];local best,score,reason
   for _,shift in ipairs({0,-500,500,-1000,1000,-2000,2000})do
    local candidate={x=q.x,y=q.y+shift*math.min(1,i/4,(count-i)/4),z=q.z}
    local z,why=sample(candidate.x,candidate.y,candidate.z)
    if why=='pending'then return nil,why end
    if z then
     candidate.z=z;local dx,dy=candidate.x-previous.x,candidate.y-previous.y
     local slope=math.abs(z-previous.z)/math.sqrt(dx*dx+dy*dy);local turn=math.atan(dy,dx)
     if slope<=.25 and(not heading or math.abs(turn-heading)<.65)and(i<=5 or i>=count-5 or not clear or clear(candidate,i))then
      local cost=math.abs(shift)*.04+slope*200+(heading and(turn-heading)^2*2000 or 0)
      if not score or cost<score then best,score=candidate,cost end
     end
    else reason=why end
   end
   if not best then return nil,reason or'connection grade'end;q=best
  end
  if i>5 and i<count-5 and clear and not clear(q,i)then return nil,'road clearance'end
  if #points>0 then
   local a=points[#points];local flat=math.sqrt((q.x-a.x)^2+(q.y-a.y)^2)
   if math.abs(q.z-a.z)>flat*.25 then return nil,'connection grade'end
   length=length+P.distance(a,q)
   heading=math.atan(q.y-a.y,q.x-a.x)
  end
  points[#points+1]=q
 end
 return {schema=2,key=index..'_'..(side==1 and'R'or'L'),seed=seed,index=index,side=side,points=points,pois={},length=length,ending='connection',target=P.copy(target)}
end
function P.flatDistance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)end
function P.segmentDistance(p,a,b)
 local x,y=b.x-a.x,b.y-a.y;local d=x*x+y*y
 local t=d>0 and clamp(((p.x-a.x)*x+(p.y-a.y)*y)/d,0,1)or 0
 return P.flatDistance(p,{x=a.x+x*t,y=a.y+y*t})
end
function P.roadDistance(p,points)
 local best=math.huge;for i=2,#points do best=math.min(best,P.segmentDistance(p,points[i-1],points[i]))end;return best
end
function P.placeStops(plan,pool,altitude,terrainHeight,mainDistance,place)
 local r=P.rng(plan.seed..':stops-v2:'..plan.key);local used={}
 local wanted=plan.ending=='connection'and(plan.length>110000 and 4 or plan.length>90000 and 3 or 2)or 2
 local stops=plan.pois or{};for _,p in ipairs(stops)do used[p.path]=true end
 local worldPoints={};for i,q in ipairs(plan.points)do worldPoints[i]=q end
 for slot=#stops+1,wanted do
  local fraction=(slot-.5)/wanted
  local center=clamp(math.floor(1+(#plan.points-1)*fraction),3,#plan.points-2)
  local placed
  for _,shift in ipairs({0,2,-2,4,-4,6,-6})do
   local node=clamp(center+shift,3,#plan.points-2);local q=plan.points[node];local t=P.tangent(plan.points,node)
   local failed=P.copy(used)
   for attempt=1,#pool do
    local e=P.choose(pool,r,mainDistance+plan.length*fraction,clamp((altitude+q.z)/terrainHeight,0,1),math.deg(math.atan(t.z,math.sqrt(t.x*t.x+t.y*t.y))),failed)
    if not e then break end;failed[e.path]=true
    local side=r()<.5 and -1 or 1
    for _,s in ipairs({side,-side})do
     local candidate=place(e,node,s,stops)
     if candidate then candidate.path=e.path;candidate.node=node;candidate.side=s;stops[#stops+1]=candidate;used[e.path]=true;placed=true;break end
    end
    if placed then break end
   end
   if placed then break end
  end
 end
 plan.pois=stops
 return #stops>=math.min(3,wanted)
end
function P.eligible(entry,distance,height,slope)
 return type(entry.path)=='string'and entry.path~=''and P.finite(entry.weight)and entry.weight>0
  and entry.once==0 -- Do not duplicate native one-time progression landmarks.
  and distance>=entry.minDistance and height>=entry.minHeight and height<=entry.maxHeight
  and slope>=entry.minSlope and slope<=entry.maxSlope
end
function P.choose(pool,r,distance,height,slope,used)
 local choices,total={},0
 for _,e in ipairs(pool)do
  if P.eligible(e,distance,height,slope)and not used[e.path]then total=total+e.weight;choices[#choices+1]=e end
 end
 if total==0 then return end
 local pick=r()*total
 for _,e in ipairs(choices)do pick=pick-e.weight;if pick<0 then return e end end
 return choices[#choices]
end
function P.populate(plan,pool,altitude,terrainHeight,mainDistance,maximum)
 local r=P.rng(plan.seed..':poi-v1:'..plan.key);local used={};local stops={}
 -- The native MaximumSpawn remains the cap per 500 m road section.
 local count=math.min(3,math.max(1,math.ceil(plan.length/50000))*(maximum or 1))
 for slot=1,count do
  local fraction=slot==count and .90 or (.32+r()*.18)
  local i=clamp(math.floor(2+(#plan.points-3)*fraction),3,#plan.points-1)
  local q=plan.points[i];local t=P.tangent(plan.points,i)
  local slope=math.deg(math.atan(t.z,math.sqrt(t.x*t.x+t.y*t.y)))
  local height=clamp((altitude+q.z)/terrainHeight,0,1)
  local e=P.choose(pool,r,mainDistance+plan.length*fraction,height,slope,used)
  if e then used[e.path]=true;stops[#stops+1]={path=e.path,node=i,side=r()<.5 and -1 or 1}end
 end
 plan.pois=stops
 return plan
end
function P.validate(p)
 assert(type(p)=='table'and(p.schema==1 or p.schema==P.schema),'Unsupported detour schema')
 assert(P.finite(p.seed)and p.seed%1==0,'Invalid seed')
 assert(P.finite(p.index)and p.index>=0 and p.index%1==0,'Invalid road index')
 assert(p.side==1 or p.side==-1,'Invalid road side')
 assert(p.key==p.index..'_'..(p.side==1 and'R'or'L'),'Invalid branch key')
 assert(type(p.points)=='table'and #p.points>=4 and #p.points<=112,'Invalid road points')
 assert(type(p.origin)=='table'and P.finite(p.origin.x)and P.finite(p.origin.y)and P.finite(p.origin.z),'Invalid origin')
 assert(P.finite(p.yaw),'Invalid heading')
 assert(P.finite(p.length)and p.length>0 and p.length<300000,'Invalid length')
 if p.rolls then
  assert(type(p.rolls)=='table'and #p.rolls==#p.points,'Invalid road banking')
  for _,v in ipairs(p.rolls)do assert(P.finite(v)and math.abs(v)<=.24,'Invalid bank angle')end
 end
 for _,name in ipairs({'exitSignZ','constructionSignZ'})do if p[name]~=nil then assert(P.finite(p[name]),'Invalid sign height')end end
 assert(p.ending=='bulb'or p.ending=='hammerhead'or p.ending=='connection','Invalid ending')
 if p.ending=='connection'then
  assert(p.schema==2 and type(p.target)=='table'and P.finite(p.target.index)and p.target.index>p.index,'Connection must rejoin ahead')
  assert(P.distance(p.points[#p.points],p.target)<1,'Disconnected endpoint')
 end
 local last
 for _,q in ipairs(p.points)do
  assert(P.finite(q.x)and P.finite(q.y)and P.finite(q.z)and math.abs(q.x)<130000 and math.abs(q.y)<110000 and math.abs(q.z)<40000,'Invalid point')
  if last then assert((p.ending=='connection'and q.x>last.x or p.ending~='connection'and q.y>last.y)and P.distance(last,q)<6000,'Branch crosses or skips a segment')end
  last=q
 end
 assert(type(p.pois)=='table'and #p.pois<=4,'Invalid POI list')
 for _,poi in ipairs(p.pois)do
  assert(type(poi.path)=='string'and #poi.path<240 and poi.path:match('^/Game/'),'Invalid POI reference')
  assert(type(poi.node)=='number'and poi.node%1==0 and poi.node>=2 and poi.node<=#p.points,'Invalid POI node')
  assert(poi.side==1 or poi.side==-1,'Invalid POI side')
  if poi.transform then
   local t=poi.transform;assert(type(t.Translation)=='table'and type(t.Rotation)=='table'and type(t.Scale3D)=='table','Invalid POI transform')
   for _,name in ipairs({'Translation','Rotation','Scale3D'})do for _,v in pairs(t[name])do assert(P.finite(v),'Invalid POI transform value')end end
  end
 end
 return p
end
return P
