-- Community 0.9.0b compatibility, validated with build 7313; PC/VR single-room maps only.
-- Read the native local PlayerAction.Type; never infer action from animation.
local Safe = require("fd_tcode.core.safe")
local Log = require("fd_tcode.core.log")
local M = { room=nil, acquired=false, was_scoped=false, last_action=nil, last_active=nil }

local function object_field(object, name)
    local ok, value = Safe.read(object, name)
    return ok and Safe.is_object(value) and value or nil
end

local function same(left, right)
    if not Safe.is_object(left) or not Safe.is_object(right) then return false end
    local ok, result = pcall(function() return left:GetAddress() == right:GetAddress() end)
    return ok and result == true
end

local function local_single_room(room)
    if not Safe.is_object(room) then return false end
    local ok, local_controller = pcall(function() return room:IsLocalPlayerController() end)
    if not ok or local_controller ~= true then return false end
    local player = object_field(room, "Player")
    if not same(object_field(player, "PlayerController"), room) then return false end
    local world_ok, world = pcall(function() return room:GetWorld() end)
    if not world_ok or not Safe.is_object(world) then return false end
    local name = Safe.object_name(world) or ""
    return string.find(name, "/Game/Core/Map/Room_SinglePCMain.Room_SinglePCMain", 1, true) ~= nil
        or string.find(name, "/Game/Core/Map/Room_SingleVRMain.Room_SingleVRMain", 1, true) ~= nil
end

function M.observe_actor(actor)
    local current = actor
    for _=1,4 do
        if local_single_room(current) then M.room=current; return end
        current = object_field(current, "Owner")
        if current == nil then break end
    end
    -- Startup can run in the title world before a local room exists. A later
    -- Character BeginPlay is an explicit acquisition boundary even when its
    -- Owner chain does not lead back to the local player controller. Coalesce
    -- all such events into the next sample, without steady-state discovery.
    if not local_single_room(M.room) then
        M.room = nil
        M.acquired = false
    end
end

local function acquire_once()
    if M.acquired then return end
    M.acquired = true
    local ok, rooms = pcall(FindAllOf, "RoomManagerBase")
    if not ok or type(rooms) ~= "table" then return end
    local found, count, checked = nil, 0, 0
    for _, room in pairs(rooms) do
        checked=checked+1
        if checked > 8 then return end
        if local_single_room(room) then found=room; count=count+1 end
    end
    if count == 1 then M.room=found end
end

function M.refresh(detector)
    acquire_once()
    local scoped = local_single_room(M.room)
    if not scoped and not M.was_scoped then return end
    local action = nil
    if scoped then
        local state = object_field(M.room, "PlayerState")
        local ok, value = pcall(function() return state.PlayerAction.Type end)
        if ok and type(value) == "number" and value % 1 == 0 then action=value end
    end
    local active = scoped and (action == 2 or action == 4)
    if action ~= M.last_action or scoped ~= M.was_scoped or M.last_active == nil then
        Log.info(string.format("Community 0.9.0b local-state scoped=%s native_action=%s active=%s",
            tostring(scoped), tostring(action), tostring(active)))
    end
    M.last_action, M.was_scoped, M.last_active = action, scoped, active
    if detector.local_action_active ~= active then
        local runtime = package.loaded["fd_tcode.core.hanime_runtime"]
        if type(runtime) == "table" and type(runtime.local_action_changed) == "function" then
            runtime.local_action_changed(active)
        else
            detector.set_local_action_active(active)
        end
    end
    if not scoped then M.room=nil end
end

return M
