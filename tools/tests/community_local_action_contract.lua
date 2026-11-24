-- Run with Lua 5.4+ from the repository root:
-- lua tools/tests/community_local_action_contract.lua packaging/compatibility/community-0.9.0b/compat7313_local_action.lua
local adapter_path = assert(arg and arg[1], "Supply the community adapter path")
local adapter_file = assert(io.open(adapter_path, "rb"))
candidate_source = adapter_file:read("*a")
adapter_file:close()

local next_address=0
function obj(fields)
    fields=fields or {}; next_address=next_address+1; fields.address=next_address
    fields.GetAddress=function(self) return self.address end
    return fields
end
package.preload["fd_tcode.core.safe"]=function() return {
    is_object=function(value) return type(value)=="table" and value.address~=nil and value.invalid~=true end,
    read=function(value,name) if type(value)~="table" or value.invalid then return false,nil end; return true,value[name] end,
    object_name=function(value) return value and value.name end,
} end
package.preload["fd_tcode.core.log"]=function() return {info=function() end} end
function setup(action, world_name)
    local world=obj({name=world_name or "World /Game/Core/Map/Room_SinglePCMain.Room_SinglePCMain"})
    local room=obj({PlayerState=obj({PlayerAction={Type=action}}),Player=obj()})
    room.Player.PlayerController=room
    room.IsLocalPlayerController=function() return true end
    room.GetWorld=function() return world end
    local detector={local_action_active=false}
    detector.set_local_action_active=function(active) detector.local_action_active=active end
    package.loaded["fd_tcode.core.hanime_runtime"]={local_action_changed=detector.set_local_action_active}
    _G.FindAllOf=function() return {room} end
    local candidate=assert(load(candidate_source))()
    return candidate,detector,room,world
end
local checked=0
local function expect(value,message) assert(value,message); checked=checked+1 end
for _,action in ipairs({2,4}) do
    local c,d,r=setup(action); c.refresh(d); expect(d.local_action_active,"H state must open")
    r.PlayerState.PlayerAction.Type=0; c.refresh(d); expect(not d.local_action_active,"exit must close")
end
for _,action in ipairs({0,1,3,5,99,-1}) do
    local c,d=setup(action); c.refresh(d); expect(not d.local_action_active,"non-H must stay closed")
end
do local c,d=setup(2,"World /Game/Core/Map/Room_Online.Room_Online"); c.refresh(d); expect(not d.local_action_active,"online must not open") end
do local c,d,r=setup(2); r.Player.PlayerController=obj(); c.refresh(d); expect(not d.local_action_active,"stale backlink must reject") end
do local c,d,r=setup(2); c.refresh(d); r.PlayerState.PlayerAction.Type=nil; c.refresh(d); expect(not d.local_action_active,"unreadable enum must close") end
do local c,d,r=setup(2); c.refresh(d); r.invalid=true; c.refresh(d); expect(not d.local_action_active,"invalid room must close") end
do local c,d,r,w=setup(2); c.refresh(d); w.name="World /Game/Core/Map/Title.Title"; c.refresh(d); expect(not d.local_action_active,"map exit must close") end
do local c,d,r=setup(2); _G.FindAllOf=function() return {r,r} end; c.refresh(d); expect(not d.local_action_active,"ambiguous discovery must reject") end
do local c,d,r=setup(2); _G.FindAllOf=function() return {} end; c.refresh(d); c.observe_actor(obj({Owner=obj({Owner=r})})); c.refresh(d); expect(d.local_action_active,"BeginPlay owner route must recover") end
test_count=checked


local count = 0
local function expect(value, message) assert(value, message); count=count+1 end
do
    local c,d,r=setup(2)
    local searches=0
    local available=false
    FindAllOf=function() searches=searches+1; return available and {r} or {} end
    c.refresh(d)
    expect(not d.local_action_active, "menu startup must stay closed")
    for _=1,20 do c.refresh(d) end
    expect(searches==1, "idle must not rescan all objects")
    available=true
    c.observe_actor(obj()) -- Character owner chain need not lead to the controller.
    c.observe_actor(obj()) -- Two participants in one frame coalesce into one acquisition.
    c.refresh(d)
    expect(d.local_action_active, "cold startup must recover on Character BeginPlay without F10")
    expect(searches==2, "BeginPlay acquisition must be coalesced")
    c.observe_actor(obj()); c.refresh(d)
    expect(searches==2, "valid cached local room must not be reacquired")
    r.PlayerState.PlayerAction.Type=0; c.refresh(d)
    expect(not d.local_action_active, "action exit must close")
    r.PlayerState.PlayerAction.Type=2; c.refresh(d)
    expect(d.local_action_active, "same-room reentry must reopen")
    expect(searches==2, "action changes must not trigger object searches")
    local _,_,replacement=setup(2)
    package.loaded["fd_tcode.core.hanime_runtime"]={local_action_changed=d.set_local_action_active}
    FindAllOf=function() searches=searches+1; return {replacement} end
    r.invalid=true
    c.refresh(d)
    expect(not d.local_action_active, "invalidated world must close gate")
    expect(searches==2, "world invalidation alone must not start polling discovery")
    c.observe_actor(obj()); c.refresh(d)
    expect(d.local_action_active, "new-world Character BeginPlay must recover")
    expect(searches==3, "new world gets one event-driven acquisition")
end
do
    local c,d,r=setup(2)
    FindAllOf=function() return {} end; c.refresh(d)
    FindAllOf=function() return {r,r} end
    c.observe_actor(obj()); c.refresh(d)
    expect(not d.local_action_active, "ambiguous reacquisition must stay closed")
    FindAllOf=function() return {r} end
    c.observe_actor(obj()); c.refresh(d)
    expect(d.local_action_active, "a later explicit event may retry after ambiguity")
end
do
    local c,d,r=setup(2, "World /Game/Core/Map/Room_Online.Room_Online")
    c.refresh(d); c.observe_actor(obj()); c.refresh(d)
    expect(not d.local_action_active, "online room must remain outside this adapter")
end
cold_start_test_count=count

assert(test_count == 17 and cold_start_test_count == 15)
for _, action in ipairs({2,4}) do
    local c,d,r=setup(action,"World /Game/Core/Map/Room_SingleVRMain.Room_SingleVRMain")
    c.refresh(d); assert(d.local_action_active, "VR local H state must open")
    r.PlayerState.PlayerAction.Type=0; c.refresh(d)
    assert(not d.local_action_active, "VR exit must close")
end
local c,d,r=setup(2,"World /Game/Core/Map/Room_SingleVRMain.Room_SingleVRMain")
r.IsLocalPlayerController=function() return false end
c.refresh(d); assert(not d.local_action_active, "VR remote controller must stay closed")
print("Community action gate: 37 behavior, cold-start and VR checks passed.")
