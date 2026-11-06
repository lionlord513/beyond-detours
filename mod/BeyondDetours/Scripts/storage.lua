return function(D)
 local S={};local J,P=D.json,D.planner
 local function path(seed,key,signature)
  assert(P.finite(seed)and tostring(key):match('^%d+_[LR]$')and tostring(signature):match('^%d+$'),'Invalid cache identity')
  return D.root..'/state/v1_'..tostring(seed):gsub('-','n')..'_'..signature..'_'..key..'.json'
 end
 function S.read(seed,key,signature)
  local f=io.open(path(seed,key,signature),'rb');if not f then return end
  local text=f:read(32769);f:close();assert(#text<=32768,'Detour cache exceeds limit')
  local p=P.validate(J.decode(text));assert(p.seed==seed and p.key==key and p.pool==signature,'Detour cache identity mismatch')
  return p
 end
 function S.write(plan)
  P.validate(plan);local file=path(plan.seed,plan.key,plan.pool);local tmp=file..'.tmp'
  local f=assert(io.open(tmp,'wb'),'Cannot write detour cache');assert(f:write(J.encode(plan)));assert(f:close())
  -- Plans are immutable. An existing valid record must never be replaced by a reroll.
  local old=io.open(file,'rb');if old then old:close();os.remove(tmp);return end
  local ok,e=os.rename(tmp,file);assert(ok,e)
 end
 return S
end
