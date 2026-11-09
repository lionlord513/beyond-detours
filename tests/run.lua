-- Run with Lua 5.4: lua tests/run.lua .
local root=arg[1] or '.'
for _,name in ipairs({'planner','network','native','connections','surface'})do
 assert(loadfile(root..'/tests/'..name..'.lua'))(root)
end
