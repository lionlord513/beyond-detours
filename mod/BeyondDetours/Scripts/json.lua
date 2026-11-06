-- Strict, bounded JSON. Presets are data and are never executed as Lua.
local J={null={}}
function J.decode(s)
 assert(type(s)=='string'and #s<=4*1024*1024,'JSON exceeds size limit')
 local i,n=1,#s;local value
 local function ws()local _,e=s:find('^[ \t\r\n]*',i);i=(e or i-1)+1 end
 local function str()
  assert(s:sub(i,i)=='"','Expected JSON string');i=i+1;local a={}
  while i<=n do local c=s:sub(i,i);i=i+1
   if c=='"'then return table.concat(a)end
   if c=='\\'then local e=s:sub(i,i);i=i+1;local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    if e=='u'then local h=s:sub(i,i+3);assert(h:match('^%x%x%x%x$'),'Bad unicode escape');i=i+4;local code=tonumber(h,16)
     if code>=0xD800 and code<=0xDBFF then assert(s:sub(i,i+1)=='\\u','Missing surrogate');local low=tonumber(s:sub(i+2,i+5),16);assert(low and low>=0xDC00 and low<=0xDFFF,'Bad surrogate');i=i+6;code=0x10000+(code-0xD800)*1024+low-0xDC00 else assert(code<0xDC00 or code>0xDFFF,'Bad surrogate')end
     a[#a+1]=utf8.char(code)
    else assert(escapes[e],'Bad JSON escape');a[#a+1]=escapes[e]end
   else assert(c:byte()>=32,'Control in JSON string');a[#a+1]=c end
  end;error('Unclosed JSON string')
 end
 value=function(depth)
  assert(depth<=24,'JSON nesting too deep');ws();local c=s:sub(i,i)
  if c=='"'then return str()end
  if c=='{'or c=='['then
   i=i+1;local object=c=='{';local close=object and '}'or']';local t={};ws();if s:sub(i,i)==close then i=i+1;return t end
   local count=0
   while true do count=count+1;assert(count<=50000,'JSON has too many entries');ws();local k=count
    if object then k=str();assert(t[k]==nil,'Duplicate JSON key');ws();assert(s:sub(i,i)==':','Missing colon');i=i+1 end
    t[k]=value(depth+1);ws();c=s:sub(i,i);i=i+1;if c==close then return t end;assert(c==',','Missing comma')
   end
  end
  for word,v in pairs({['true']=true,['false']=false,['null']=J.null})do if s:sub(i,i+#word-1)==word then i=i+#word;return v end end
  local start=i;if s:sub(i,i)=='-'then i=i+1 end
  local d=s:sub(i,i);assert(d:match('%d'),'Expected JSON value')
  if d=='0'then i=i+1 else while s:sub(i,i):match('%d')do i=i+1 end end
  if s:sub(i,i)=='.'then i=i+1;assert(s:sub(i,i):match('%d'),'Invalid decimal');while s:sub(i,i):match('%d')do i=i+1 end end
  if s:sub(i,i):match('[eE]')then i=i+1;if s:sub(i,i):match('[+-]')then i=i+1 end;assert(s:sub(i,i):match('%d'),'Invalid exponent');while s:sub(i,i):match('%d')do i=i+1 end end
  local number=tonumber(s:sub(start,i-1));assert(number and math.abs(number)<math.huge,'Invalid JSON number');return number
 end
 local result=value(0);ws();assert(i>n,'Trailing JSON data');return result
end
local function quote(s)return '"'..s:gsub('[%z\1-\31\\"]',function(c)local e={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'};return e[c]or('\\u%04x'):format(c:byte())end)..'"'end
function J.encode(v,depth)
 depth=depth or 0;assert(depth<=24,'JSON nesting too deep');local t=type(v)
 if v==J.null then return 'null'elseif t=='string'then return quote(v)elseif t=='boolean'then return tostring(v)elseif t=='number'then assert(v==v and math.abs(v)<math.huge,'Invalid number');return ('%.12g'):format(v)end
 assert(t=='table','Unsupported JSON value');local out={};local array=#v>0
 if array then for i=1,#v do out[i]=J.encode(v[i],depth+1)end;return '['..table.concat(out,',')..']'end
 local keys={};for k in pairs(v)do assert(type(k)=='string','Non-string key');keys[#keys+1]=k end;table.sort(keys)
 for _,k in ipairs(keys)do out[#out+1]=quote(k)..':'..J.encode(v[k],depth+1)end
 return '{'..table.concat(out,',')..'}'
end
return J
