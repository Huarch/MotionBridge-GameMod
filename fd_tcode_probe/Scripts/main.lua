-- Fallen Doll TCode discovery probe.
-- Read-only: it enumerates runtime Unreal objects but changes no game state.

local MOD = "[FD-TCode-Probe]"
local MAX_PER_CLASS = 80
local stream_enabled = false
local stream_counts = {}
local stream_last_montage = {}
local stream_last_section = {}
local sex_trace_pre = nil
local sex_trace_post = nil
local sex_tick_pre = nil
local sex_tick_post = nil
local sex_trace_remaining = 0
local sex_tick_index = 0

local function valid_name(object)
    if object == nil then
        return "<nil>"
    end

    if not object:IsValid() then
        return "<invalid>"
    end

    return object:GetFullName()
end

local function dump_class(short_class_name)
    local objects = FindAllOf(short_class_name)
    if objects == nil then
        print(string.format("%s %s: none\n", MOD, short_class_name))
        return
    end

    local count = 0
    for _, object in pairs(objects) do
        count = count + 1
        if count <= MAX_PER_CLASS then
            local outer = object:GetOuter()
            print(string.format(
                "%s %s #%d: %s | outer: %s\n",
                MOD,
                short_class_name,
                count,
                valid_name(object),
                valid_name(outer)
            ))
        end
    end

    if count > MAX_PER_CLASS then
        print(string.format("%s %s: %d total; first %d shown\n", MOD, short_class_name, count, MAX_PER_CLASS))
    else
        print(string.format("%s %s: %d total\n", MOD, short_class_name, count))
    end
end

local function scan_runtime()
    print(string.format("%s ----- BEGIN runtime scan -----\n", MOD))
    dump_class("AnimInstance")
    dump_class("SkeletalMeshComponent")
    dump_class("Character")
    dump_class("Pawn")
    print(string.format("%s ----- END runtime scan -----\n", MOD))
end

local function value_text(value)
    local lua_type = type(value)
    if lua_type == "string" or lua_type == "number" or lua_type == "boolean" then
        return tostring(value)
    end

    if lua_type == "userdata" then
        -- FVector values are not UObjects, so IsValid() is unavailable. Log
        -- their coordinates first; this is the read-only bone probe path.
        local vector_ok, x, y, z = pcall(function()
            return value.X, value.Y, value.Z
        end)
        if vector_ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then
            return string.format("(%.3f, %.3f, %.3f)", x, y, z)
        end
        local ok, name = pcall(function()
            if value:IsValid() then
                return value:GetFullName()
            end
            return "<invalid userdata>"
        end)
        if ok then
            return name
        end
        return tostring(value)
    end

    return "<" .. lua_type .. ">"
end

local function is_interesting(name)
    local lower = string.lower(name)
    return string.find(lower, "anim", 1, true)
        or string.find(lower, "montage", 1, true)
        or string.find(lower, "play", 1, true)
        or string.find(lower, "time", 1, true)
        or string.find(lower, "state", 1, true)
        or string.find(lower, "rate", 1, true)
end

local function dump_animation_controller(instance)
    local class = instance:GetClass()
    print(string.format("%s ===== Controller: %s =====\n", MOD, instance:GetFullName()))

    local depth = 0
    while class ~= nil and class:IsValid() and depth < 8 do
        print(string.format("%s class: %s\n", MOD, class:GetFullName()))
        class:ForEachProperty(function(property)
            local name = property:GetFName():ToString()
            if is_interesting(name) then
                local ok, value = pcall(function()
                    return instance[name]
                end)
                print(string.format(
                    "%s property %s (%s) = %s\n",
                    MOD,
                    name,
                    property:GetClass():GetFName():ToString(),
                    ok and value_text(value) or "<unreadable>"
                ))
            end
        end)
        class:ForEachFunction(function(fn)
            local name = fn:GetFName():ToString()
            if is_interesting(name) then
                print(string.format("%s function %s\n", MOD, fn:GetFullName()))
            end
        end)
        class = class:GetSuperStruct()
        depth = depth + 1
    end
end

local function scan_animation_controllers()
    print(string.format("%s ----- BEGIN controller scan -----\n", MOD))
    local instances = FindAllOf("AnimInstance") or {}
    local matches = 0
    for _, instance in pairs(instances) do
        local class_name = instance:GetClass():GetFName():ToString()
        if class_name == "AMBP_Alet_HAnim_C" or class_name == "AMBP_Male_C" then
            matches = matches + 1
            dump_animation_controller(instance)
        end
    end
    print(string.format("%s controller matches: %d\n", MOD, matches))
    print(string.format("%s ----- END controller scan -----\n", MOD))
end

local function try_call(label, callback)
    local ok, result = pcall(callback)
    if ok then
        print(string.format("%s snapshot %s = %s\n", MOD, label, value_text(result)))
    else
        print(string.format("%s snapshot %s = <unavailable>\n", MOD, label))
    end
    return ok, result
end

local function is_primary_controller(instance)
    local outer = instance:GetOuter()
    local name = valid_name(outer)
    return string.find(name, ".Mesh_Main", 1, true) ~= nil
        or string.find(name, ".Mesh_MaleB", 1, true) ~= nil
end

local function is_valid_object(value)
    return value ~= nil and type(value) == "userdata" and pcall(function()
        return value:IsValid()
    end) and value:IsValid()
end

-- Compact, read-only sample intended for two manual snapshots during the same action.
-- F10 avoids scanning reflected properties and only targets the visible main meshes.
local function snapshot_animation_playback()
    print(string.format("%s ----- BEGIN playback snapshot -----\n", MOD))
    local instances = FindAllOf("AnimInstance") or {}
    local matches = 0

    for _, instance in pairs(instances) do
        local class_name = instance:GetClass():GetFName():ToString()
        if (class_name == "AMBP_Alet_HAnim_C" or class_name == "AMBP_Male_C") and is_primary_controller(instance) then
            matches = matches + 1
            print(string.format("%s target %s\n", MOD, valid_name(instance)))

            local montage_ok, montage = pcall(function()
                return instance:GetCurrentActiveMontage()
            end)
            if montage_ok and is_valid_object(montage) then
                print(string.format("%s snapshot active_montage = %s\n", MOD, value_text(montage)))
                try_call("montage_position", function() return instance:Montage_GetPosition(montage) end)
                try_call("montage_rate", function() return instance:Montage_GetPlayRate(montage) end)
                try_call("montage_section", function() return instance:Montage_GetCurrentSection(montage) end)
            else
                print(string.format("%s snapshot active_montage = <none>\n", MOD))
            end

            -- Do not query state-machine indices here: this game does not expose their
            -- valid indices and invalid native calls can destabilize the running session.
        end
    end

    print(string.format("%s snapshot targets: %d\n", MOD, matches))
    print(string.format("%s ----- END playback snapshot -----\n", MOD))
end

-- Read-only snapshot of the separate gameplay accumulator that feeds the
-- sex/pleasure bar. This deliberately does not call IncrementSexCount or any
-- setter; it only exposes existing state for two-point comparison.
local function is_hscene_state_name(name)
    local lower = string.lower(name)
    return string.find(lower, "sex", 1, true)
        or string.find(lower, "climax", 1, true)
        or string.find(lower, "count", 1, true)
        or string.find(lower, "sweat", 1, true)
        or string.find(lower, "rate", 1, true)
        or string.find(lower, "state", 1, true)
end

local function snapshot_hscene_state()
    print(string.format("%s ----- BEGIN HScene state snapshot -----\n", MOD))
    local instances = FindAllOf("HStateManager_C") or {}
    if #instances == 0 then
        -- In this build the actor is sometimes registered only through the
        -- scene manager's generated component reference.
        local managers = FindAllOf("HSceneManager_C") or FindAllOf("HSceneManager") or {}
        for _, manager in pairs(managers) do
            local ok, state_manager = pcall(function() return manager.StateManager end)
            if ok and is_valid_object(state_manager) then
                table.insert(instances, state_manager)
            end
        end
    end
    local matches = 0
    for _, instance in pairs(instances) do
        if instance ~= nil and instance:IsValid() then
            matches = matches + 1
            print(string.format("%s state target %s\n", MOD, valid_name(instance)))
            local owner = instance:GetOuter()
            print(string.format("%s hstate owner %s\n", MOD, valid_name(owner)))
            try_call("hscene_owner_has_authority", function() return owner:HasAuthority() end)
            try_call("hscene_owner_local_role", function() return owner:GetLocalRole() end)
            try_call("hscene_owner_remote_role", function() return owner:GetRemoteRole() end)
            try_call("hscene_owner_role_property", function() return owner.Role end)
            try_call("hscene_owner_remote_role_property", function() return owner.RemoteRole end)
            local class = instance:GetClass()
            local depth = 0
            while class ~= nil and class:IsValid() and depth < 6 do
                class:ForEachProperty(function(property)
                    local name = property:GetFName():ToString()
                    if is_hscene_state_name(name) then
                        local ok, value = pcall(function() return instance[name] end)
                        print(string.format("%s hstate property %s = %s\n", MOD, name, ok and value_text(value) or "<unreadable>"))
                    end
                end)
                class:ForEachFunction(function(fn)
                    local name = fn:GetFName():ToString()
                    if is_hscene_state_name(name) then
                        print(string.format("%s hstate function %s\n", MOD, name))
                    end
                end)
                class = class:GetSuperStruct()
                depth = depth + 1
            end
        end
    end
    print(string.format("%s HScene state targets: %d\n", MOD, matches))
    print(string.format("%s ----- END HScene state snapshot -----\n", MOD))
end

-- Observe the exact accumulator call before modifying it. In this game the
-- Blueprint may compute the increment internally from DeltaSeconds, so a
-- parameter must never be multiplied until its layout is verified.
local function trace_sex_count_pre(self, ...)
    if sex_trace_remaining <= 0 then return end
    local ok, instance = pcall(function() return self:get() end)
    if not ok or not is_valid_object(instance) then return end
    local params = { ... }
    local values = {}
    for index, param in ipairs(params) do
        local value_ok, value = pcall(function() return param:get() end)
        values[#values + 1] = string.format("p%d=%s", index, value_ok and value_text(value) or "<unreadable>")
    end
    print(string.format("%s sex-trace pre count=%s %s\n", MOD, value_text(instance.SexCount), table.concat(values, " ")))
end

local function trace_sex_count_post(self, ...)
    if sex_trace_remaining <= 0 then return end
    local ok, instance = pcall(function() return self:get() end)
    if not ok or not is_valid_object(instance) then return end
    sex_trace_remaining = sex_trace_remaining - 1
    print(string.format("%s sex-trace post count=%s remaining=%d\n", MOD, value_text(instance.SexCount), sex_trace_remaining))
end

local function trace_sex_tick_pre(self, ...)
    if sex_trace_remaining <= 0 then return end
    sex_tick_index = sex_tick_index + 1
    if sex_tick_index % 12 ~= 0 then return end
    local ok, instance = pcall(function() return self:get() end)
    if ok and is_valid_object(instance) then
        sex_trace_remaining = sex_trace_remaining - 1
        print(string.format("%s sex-tick pre count=%s\n", MOD, value_text(instance.SexCount)))
        if sex_trace_remaining == 0 then
            print(string.format("%s sex-tick trace complete.\n", MOD))
        end
    end
end

local function trace_sex_tick_post(self, ...)
    -- Some UE4SS builds do not invoke a Blueprint post callback. The bounded
    -- pre-sample above is therefore the authoritative trace mechanism.
end

local function enable_sex_count_trace()
    if sex_trace_pre == nil then
        local ok, pre, post = pcall(function()
            return RegisterHook("/Game/BP/HStateManager.HStateManager_C:IncrementSexCount", trace_sex_count_pre, trace_sex_count_post)
        end)
        if not ok then
            print(string.format("%s sex-trace unavailable: enter an HScene, then press Ctrl+Alt+F6 again.\n", MOD))
            return
        end
        sex_trace_pre = pre
        sex_trace_post = post
    end
    if sex_tick_pre == nil then
        local ok, pre, post = pcall(function()
            return RegisterHook("/Game/BP/HStateManager.HStateManager_C:ReceiveTick", trace_sex_tick_pre, trace_sex_tick_post)
        end)
        if not ok then
            print(string.format("%s sex-tick trace unavailable; IncrementSexCount trace remains active.\n", MOD))
        else
            sex_tick_pre = pre
            sex_tick_post = post
        end
    end
    sex_trace_remaining = 12
    sex_tick_index = 0
    print(string.format("%s sex-trace armed for next %d IncrementSexCount calls (read-only).\n", MOD, sex_trace_remaining))
end

-- The gameplay animation update is the safest clock available in this build.
-- While explicitly enabled, emit a compact state record roughly every five updates.
-- This remains log-only: a later localhost bridge will consume these records.
local function emit_playback_state(instance)
    local class_name = instance:GetClass():GetFName():ToString()
    if class_name ~= "AMBP_Male_C" then
        return
    end

    local source = valid_name(instance)
    if string.find(source, ".Mesh_MaleB", 1, true) == nil then
        return
    end

    stream_counts[source] = (stream_counts[source] or 0) + 1

    local montage_ok, montage = pcall(function()
        return instance:GetCurrentActiveMontage()
    end)
    if not montage_ok or not is_valid_object(montage) then
        if stream_last_montage[source] ~= "<none>" then
            stream_last_montage[source] = "<none>"
            stream_last_section[source] = "<none>"
            print(string.format("[FD-TCode-State] stop source=%s\n", source))
        end
        return
    end

    local name = value_text(montage)
    if stream_last_montage[source] ~= name then
        stream_last_montage[source] = name
        stream_last_section[source] = nil
        print(string.format("[FD-TCode-State] start source=%s montage=%s\n", source, name))
    end

    local position_ok, position = pcall(function() return instance:Montage_GetPosition(montage) end)
    local rate_ok, rate = pcall(function() return instance:Montage_GetPlayRate(montage) end)
    local section_ok, section = pcall(function() return instance:Montage_GetCurrentSection(montage) end)
    if section_ok then
        local section_name = value_text(section)
        if stream_last_section[source] ~= section_name then
            stream_last_section[source] = section_name
            print(string.format("[FD-TCode-State] section source=%s name=%s\n", source, section_name))
        end
    end
    -- Section changes are checked every animation update so short trigger
    -- sections are not missed; the high-volume clock remains throttled.
    if position_ok and rate_ok and stream_counts[source] % 5 == 0 then
        print(string.format("[FD-TCode-State] tick source=%s position=%.6f rate=%.6f\n", source, position, rate))
    end
end

local male_update_hook_pre = nil
local male_update_hook_post = nil
local male_update_path = "/Game/Characters/MaleB/AMBP_Male.AMBP_Male_C:BlueprintUpdateAnimation"

-- The function only exists after an action scene has loaded. Register lazily from
-- F11 so a normal game launch never fails just because the character is absent.
local function on_male_update(context)
    if not stream_enabled then
        return
    end
    local ok, instance = pcall(function() return context:get() end)
    if ok and instance ~= nil and instance:IsValid() then
        emit_playback_state(instance)
    end
end

local function toggle_playback_stream()
    if stream_enabled then
        stream_enabled = false
        print(string.format("%s playback stream disabled\n", MOD))
        return
    end

    if male_update_hook_pre == nil then
        local ok, pre, post = pcall(function()
            return RegisterHook(male_update_path, on_male_update)
        end)
        if not ok then
            print(string.format("%s playback stream unavailable: enter an action scene, then press F11 again.\n", MOD))
            return
        end
        male_update_hook_pre = pre
        male_update_hook_post = post
    end

    stream_enabled = true
    stream_counts = {}
    stream_last_montage = {}
    stream_last_section = {}
    print(string.format("%s playback stream enabled\n", MOD))
end

RegisterKeyBind(Key.F8, { ModifierKey.CONTROL, ModifierKey.ALT }, function()
    ExecuteInGameThread(scan_runtime)
end)

RegisterKeyBind(Key.F9, { ModifierKey.CONTROL, ModifierKey.ALT }, function()
    ExecuteInGameThread(scan_animation_controllers)
end)

RegisterKeyBind(Key.F10, { ModifierKey.CONTROL, ModifierKey.ALT }, function()
    ExecuteInGameThread(snapshot_animation_playback)
end)

RegisterKeyBind(Key.F7, { ModifierKey.CONTROL, ModifierKey.ALT }, function()
    ExecuteInGameThread(snapshot_hscene_state)
end)

RegisterKeyBind(Key.F6, { ModifierKey.CONTROL, ModifierKey.ALT }, function()
    enable_sex_count_trace()
end)

RegisterKeyBind(Key.F11, function()
    toggle_playback_stream()
end)

print(string.format("%s loaded. Ctrl+Alt+F6 traces SexCount; F7 snapshots HScene state; F8 scans; F9 controllers; F10 animation snapshot; F11 toggles log-only playback stream.\n", MOD))
