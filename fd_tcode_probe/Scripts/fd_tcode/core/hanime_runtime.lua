-- Stable runtime shell for hot-reloadable HAnime state detection.
--
-- The formal path deliberately does not depend on a single HAnime enter/exit
-- event. Inactive/acquiring state is checked at 4 Hz. Once verified, the gate
-- stays locked to live participant components and the 50 Hz skeleton stream
-- does not rescan AnimBP/Montage/HManager state. Lifecycle and F10 request a
-- bounded transition review; a future verified Montage adapter can use the
-- same one-shot detector API.

local Log = require("fd_tcode.core.log")
local SkeletonStream = require("fd_tcode.core.skeleton_stream")

local DETECTOR_MODULE = "fd_tcode.core.hanime_detector"

local Runtime = {
    detector = require(DETECTOR_MODULE),
    running = false,
}

local CHARACTER_ACTOR_TOKENS = {
    "CharacterADA", "CharacterAlet", "CharacterAnya", "CharacterByakhee",
    "CharacterCelia", "CharacterDeepOne", "CharacterDrone", "CharacterElderThing",
    "CharacterElizabeth", "CharacterErika", "CharacterGalatea", "CharacterGala",
    "CharacterGhast", "CharacterGhoul", "CharacterGug", "CharacterHippocamp",
    "CharacterHound", "CharacterJuzi", "CharacterJuzhi", "CharacterLloigor",
    "CharacterMale", "CharacterMigo", "CharacterNightgaunt", "CharacterSaaitii",
    "CharacterShantak", "CharacterSkorpion", "CharacterSkorpios", "CharacterSylph",
    "CharacterTalon", "CharacterTchoTcho", "CharacterTentacle", "CharacterYanshi",
}

local CHARACTER_ANIM_CLASSES = {
    CharacterADA = { "AMBP_ADA_C" },
    CharacterAlet = { "AMBP_Alet_HAnim_C" },
    CharacterAnya = { "AMBP_Anya_H_Anim_C" },
    CharacterByakhee = { "AMBP_Byakhee_C" },
    CharacterCelia = { "AMBP_Celia_C" },
    CharacterDeepOne = { "AMBP_DeepOne_C" },
    CharacterDrone = { "AMBP_Drone_C" },
    CharacterElderThing = { "AMBP_ElderThing_C" },
    CharacterElizabeth = { "AMBP_Elizabeth_C" },
    CharacterErika = { "AMBP_Erika_C" },
    CharacterGalatea = { "AMBP_Gala_C" },
    CharacterGala = { "AMBP_Gala_C" },
    CharacterGhast = { "AMBP_Ghast_C" },
    CharacterGhoul = { "AMBP_Ghoul_C" },
    CharacterGug = { "AMBP_Gug_C" },
    CharacterHippocamp = { "AMBP_Hippocamp_C" },
    CharacterHound = { "AMBP_Hound_HAnim_C" },
    CharacterJuzi = { "AMBP_Juzi_C" },
    CharacterJuzhi = { "AMBP_Juzi_C" },
    CharacterLloigor = { "AMBP_Lloigor_C" },
    CharacterMale = { "AMBP_Male_C" },
    CharacterMigo = { "AMBP_Migo_warrior_C" },
    CharacterNightgaunt = { "AMBP_nightgaunt_C" },
    CharacterSaaitii = { "AMBP_Saaitii_C" },
    CharacterShantak = { "AMBP_Shantak_C" },
    CharacterSkorpion = { "AMBP_Skorpios_C" },
    CharacterSkorpios = { "AMBP_Skorpios_C" },
    CharacterSylph = { "AMBP_Sylph_C" },
    CharacterTalon = { "AMBP_Talon_C" },
    CharacterTchoTcho = { "AMBP_TchoTcho_C" },
    CharacterTentacle = { "AMBP_Tentacle_C" },
    CharacterYanshi = { "AMBP_Yanshi_C" },
}

local function traceback(message)
    if debug ~= nil and type(debug.traceback) == "function" then
        return debug.traceback(tostring(message), 2)
    end
    return tostring(message)
end

local function reload_module(module_name)
    if package == nil or type(package.loaded) ~= "table" then
        return nil, "package.loaded is unavailable"
    end
    local previous = package.loaded[module_name]
    package.loaded[module_name] = nil
    local ok, candidate = xpcall(function()
        return require(module_name)
    end, traceback)
    if not ok or type(candidate) ~= "table" then
        package.loaded[module_name] = previous
        return nil, tostring(candidate)
    end
    return candidate, nil
end

local function unwrap_actor(remote)
    if remote == nil then
        return nil
    end
    local ok, actor = pcall(function()
        return remote:get()
    end)
    if ok then
        return actor
    end
    local direct_ok = pcall(function()
        return remote:GetFullName()
    end)
    return direct_ok and remote or nil
end

local function actor_name(actor)
    if actor == nil then
        return nil
    end
    local ok, name = pcall(function()
        return actor:GetFullName()
    end)
    return ok and name ~= nil and tostring(name) or nil
end

local function relevant_character_actor(name)
    -- The title screen owns an ADA presentation actor. It is not a room or an
    -- HAnime participant and must not seed wrappers that become stale during
    -- the subsequent map transition.
    if string.find(name or "", "/Map/Title.Title", 1, true) then
        return false
    end
    for _, token in ipairs(CHARACTER_ACTOR_TOKENS) do
        if string.find(name or "", token, 1, true) then
            return true
        end
    end
    return false
end

local function anim_classes_for_actor(name)
    local result = {}
    for token, class_names in pairs(CHARACTER_ANIM_CLASSES) do
        if string.find(name or "", token, 1, true) then
            for _, class_name in ipairs(class_names) do
                table.insert(result, class_name)
            end
        end
    end
    return result
end

local function register_component_discovery_signal()
    -- Keep the registered UE4SS callback stable and route it through a global
    -- dispatcher. Lua hot reload can then replace the implementation without
    -- stacking another BeginPlay hook (the specialised API has no unregister).
    _G.FD_TCODE_BEGIN_PLAY_HANDLER = function(actor_parameter)
        local actor = unwrap_actor(actor_parameter)
        local name = actor_name(actor)
        if relevant_character_actor(name) then
            local queued = Runtime.detector.queue_actor_components(actor)
            -- BeginPlay already supplies the concrete participant Actor. When
            -- its extracted primary mesh properties resolve successfully, the
            -- detector has everything needed for the next one-shot gate review.
            -- Scheduling FindFirstOf as well caused three redundant acquisition
            -- passes after every action entry, even after the exact HAnime
            -- binding was active. UE 5.7 visibly hitches clothing/physics during
            -- those passes. Keep class discovery only as the exceptional fallback
            -- for an actor whose primary component could not be read directly.
            local fallback_discovery = tonumber(queued or 0) <= 0
            if fallback_discovery then
                Runtime.detector.request_component_discovery(anim_classes_for_actor(name))
            end
            SkeletonStream.notify_hanime_event()
            Log.info(string.format(
                "HAnime component queued by character BeginPlay=%s directPrimary=%d fallbackDiscovery=%s",
                tostring(name),
                tonumber(queued or 0),
                tostring(fallback_discovery)
            ))
        end
        actor = nil
        actor_parameter = nil
    end
    if _G.FD_TCODE_STATE_BEGIN_PLAY_REGISTERED then
        return
    end
    local ok, register_error = pcall(function()
        RegisterBeginPlayPostHook(function(actor_parameter)
            local handler = _G.FD_TCODE_BEGIN_PLAY_HANDLER
            if type(handler) == "function" then
                local handler_ok, handler_error = pcall(handler, actor_parameter)
                if not handler_ok then
                    Log.warn("Character BeginPlay handler failed: " .. tostring(handler_error))
                end
            end
            actor_parameter = nil
        end)
    end)
    if ok then
        _G.FD_TCODE_STATE_BEGIN_PLAY_REGISTERED = true
        Log.info("Character BeginPlay cache-refresh signal registered")
    else
        Log.warn("Character BeginPlay cache-refresh signal unavailable: " .. tostring(register_error))
    end
end

function Runtime.world_changed()
    -- NotifyOnNewObject(World) is only a cache boundary. It is not interpreted
    -- as HAnime enter/exit, and no Unreal wrapper is retained from the event.
    Runtime.detector.clear_cache()
    SkeletonStream.notify_hanime_event()
end

function Runtime.queue_component(component)
    Runtime.detector.queue_component(component)
end

function Runtime.reload_detector()
    if SkeletonStream.is_running() then
        SkeletonStream.stop({
            reason = "detector-hot-reload",
            preserve_detector_cache = true,
        })
    end

    local previous_detector_module = package ~= nil and package.loaded ~= nil
        and package.loaded[DETECTOR_MODULE]
        or Runtime.detector
    local detector, detector_error = reload_module(DETECTOR_MODULE)
    if detector == nil
        or type(detector.sample) ~= "function"
        or type(detector.queue_component) ~= "function"
        or type(detector.queue_actor_components) ~= "function"
        or type(detector.request_component_discovery) ~= "function"
        or type(detector.clear_cache) ~= "function"
    then
        if package ~= nil and type(package.loaded) == "table" then
            package.loaded[DETECTOR_MODULE] = previous_detector_module
        end
        SkeletonStream.set_detector(Runtime.detector)
        SkeletonStream.start({ preserve_detector_cache = true })
        Log.error("HAnime detector hot reload failed: " .. tostring(detector_error or "invalid module API"))
        return false
    end

    Runtime.detector = detector
    Runtime.detector.request_component_discovery()
    SkeletonStream.set_detector(detector)
    SkeletonStream.start({ preserve_detector_cache = true })
    Log.info("HAnime state detector hot reload complete; 4 Hz watcher restarted")
    return true
end

function Runtime.start()
    if Runtime.running then
        return
    end
    Runtime.running = true
    SkeletonStream.set_detector(Runtime.detector)
    SkeletonStream.start()
    register_component_discovery_signal()
    RegisterKeyBind(Key.F10, Runtime.reload_detector)
    Log.info("HAnime transition gate armed; active bindings are event-reviewed, not periodically rescanned")
end

return Runtime
