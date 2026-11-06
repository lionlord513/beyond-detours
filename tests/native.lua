local root=assert(...)
local P=dofile(root..'/mod/BeyondDetours/Scripts/planner.lua')
local path='/Game/Maps/Levels/L_CowField_B.L_CowField_B'
local alive=true
local function borrowed(value)
 if type(value)~='table'then return value end
 return setmetatable({},{__index=function(_,key)
  assert(alive,'Borrowed native array storage escaped the callback')
  return borrowed(value[key])
 end})
end
local entry={RandomWeight=.5,MinSpawnDistance=0,MinSpawnHeight=0,MaxSpawnHeight=1,MinSlopeAngle=-180,MaxSlopeAngle=180,SpawnOneTimeAtDistance=0,Level={World=path,AlwaysVisible=false,UseCustomSideOffset=true,CustomSideOffset=-7000,CreationTime=-1,Transform={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}}}
local asset={IsValid=function()return true end,MaximumSpawn=1,SideOffset=2000,Levels={ForEach=function(_,callback)
 callback(1,{get=function()return borrowed(entry)end});alive=false
end}}
LoadAsset=function()return asset end
local S={Conv_SoftObjectReferenceToString=function(_,v)return{ToString=function()return v end}end}
local M={ComposeTransforms=function(_,localTransform,worldTransform)
 assert(localTransform.Rotation.W==1 and localTransform.Scale3D.X==1)
 return worldTransform
end}
StaticFindObject=function(name)if name:find('KismetSystem',1,true)then return S elseif name:find('KismetMath',1,true)then return M else return{}end end
local D={planner=P,valid=function(o)return o and o:IsValid()end,log=function()end}
local N=dofile(root..'/mod/BeyondDetours/Scripts/native.lua')(D)
N.loadPool();assert(N.byPath[path].weight==.5)
local names={};local calls=0
local spawner={LevelsRep={ForEach=function(_,callback)
 for _,name in ipairs(names)do callback(1,{get=function()return{LevelLoad={ToString=function()return name end}}end})end
end},AddLevel=function(_,level,suffix)
 calls=calls+1;names[#names+1]='/Game/Maps/Levels/L_CowField_B'..suffix
 assert(level.World==nil and level.WorldSoftObjectPtrPath==path)
 assert(level.AlwaysVisible==false and level.UseCustomSideOffset==true and level.CustomSideOffset==-7000 and level.CreationTime==-1)
 assert(math.abs(level.Transform.Translation.X-7000)<.000001 and math.abs(level.Transform.Translation.Y-1000)<.000001)
end}
local plan={key='3_R',origin={x=0,y=0,z=0},yaw=0,side=1,points={{x=0,y=0,z=0},{x=0,y=1000,z=0}},pois={{path=path,node=2,side=1}}}
N.spawnPOIs({host=true,seed=123,spawner=spawner},plan)
N.spawnPOIs({host=true,seed=123,spawner=spawner},plan)
N.spawnPOIs({host=false,seed=123,spawner=spawner},plan)
assert(calls==1,'Native POI duplicated or spawned by guest')
print('PASS native parameter snapshots outlive borrowed storage; serialized world path, transform, host-only spawning and stable deduplication')
