-- Pure HAnime identity resolution.
--
-- This module owns generated allowlists and string/participant metadata only.
-- It never discovers Unreal objects and never reads bone transforms.

local Config = require("fd_tcode.config")
local IdentityData = require("fd_tcode.core.hanime_identity_catalog")
local SkeletonCatalog = require("fd_tcode.core.skeleton_catalog")

local table_rows_ok, DemoTableRows = pcall(require, "fd_tcode.data.demo_hanime_table_row_data")
if not table_rows_ok or type(DemoTableRows) ~= "table" then
    DemoTableRows = {}
end

local Resolver = {}

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function participant_slot(participant_tag)
    local raw_tag = string.lower(tostring(participant_tag or ""))
    return string.match(raw_tag, "[_%-]([abc])[_%-]?%d*$")
        or string.match(raw_tag, "[_%-]([abc])$")
        or "generic"
end

local function participant_base(participant_tag)
    local raw_tag = string.lower(tostring(participant_tag or ""))
    raw_tag = string.gsub(raw_tag, "[_%-][abc][_%-%d]*$", "")
    raw_tag = string.gsub(raw_tag, "[_%-]%d+$", "")
    return normalized(raw_tag)
end

local family_by_normalized_id = {}
for hanime_id in pairs(IdentityData.by_family or {}) do
    local key = normalized(hanime_id)
    if key ~= "" then
        family_by_normalized_id[key] = tostring(hanime_id)
    end
end

local function exact_family_id(value)
    local text = normalized(value)
    if text == "" then
        return nil
    end
    local exact = family_by_normalized_id[text]
    if exact ~= nil then
        return exact
    end

    -- Reflected property text may contain a type wrapper.  Prefer the longest
    -- complete family ID so a shorter similarly named family cannot win.
    local best = nil
    local best_length = 0
    for key, hanime_id in pairs(family_by_normalized_id) do
        if #key > best_length and string.find(text, key, 1, true) then
            best = hanime_id
            best_length = #key
        end
    end
    return best
end

local function exact_demo_table_row_family(value)
    if tostring(Config.game_edition or "") ~= "demo-ue4.25" then
        return nil
    end
    local raw = tostring(value or "")
    local anim_id = string.match(raw, "^%s*(%d+)%s*$")
        or string.match(raw, "[Aa]nim[Ii][Dd][^%d]*(%d+)")
    return anim_id and (DemoTableRows.by_anim_id or {})[anim_id] or nil
end

local function build_family_catalog_roles()
    local families = {}
    local function add_participant(hanime_id, participant_tag)
        hanime_id = tostring(hanime_id or "")
        local role = SkeletonCatalog.role_for_participant_tag(participant_tag)
        if hanime_id == "" or role == nil then
            return
        end
        local family = families[hanime_id]
        if family == nil then
            family = {}
            families[hanime_id] = family
        end
        local role_slots = family[role]
        if role_slots == nil then
            role_slots = { generic = false, named = {}, first_position = nil }
            family[role] = role_slots
        end
        local position = string.find(
            normalized(hanime_id), participant_base(participant_tag), 1, true
        )
        if position ~= nil
            and (role_slots.first_position == nil or position < role_slots.first_position)
        then
            role_slots.first_position = position
        end
        local slot = participant_slot(participant_tag)
        if slot == "generic" then
            role_slots.generic = true
        else
            role_slots.named[slot] = true
        end
    end

    for _, identity in pairs(IdentityData.by_montage or {}) do
        add_participant(identity.hanime_id, identity.participant_tag)
    end
    for hanime_id, metadata in pairs(IdentityData.by_family or {}) do
        for _, participant_tag in ipairs(metadata.participant_tags or {}) do
            add_participant(hanime_id, participant_tag)
        end
    end

    local roles_by_family = {}
    local slots_by_family = {}
    local priorities_by_family = {}
    for hanime_id, family in pairs(families) do
        local roles = {}
        local slots_result = {}
        local ordered_roles = {}
        roles_by_family[hanime_id] = roles
        slots_by_family[hanime_id] = slots_result
        priorities_by_family[hanime_id] = {}
        for role, slots in pairs(family) do
            local ordered_slots = {}
            for _, slot in ipairs({ "a", "b", "c" }) do
                if slots.named[slot] then
                    table.insert(ordered_slots, slot)
                end
            end
            if #ordered_slots == 0 and slots.generic then
                table.insert(ordered_slots, "generic")
            end
            slots_result[role] = ordered_slots
            roles[role] = #ordered_slots
            table.insert(ordered_roles, {
                role = role,
                position = slots.first_position or 1000000,
            })
        end
        table.sort(ordered_roles, function(a, b)
            if a.position == b.position then
                return a.role < b.role
            end
            return a.position < b.position
        end)
        for index, item in ipairs(ordered_roles) do
            priorities_by_family[hanime_id][item.role] = index - 1
        end
    end
    return roles_by_family, slots_by_family, priorities_by_family
end

local family_roles, family_slots, family_priorities = build_family_catalog_roles()

function Resolver.participant_slot(participant_tag)
    return participant_slot(participant_tag)
end

function Resolver.slot_priority(slots, wanted_slot)
    for index, slot in ipairs(slots or {}) do
        if slot == wanted_slot then
            return index - 1
        end
    end
    return nil
end

function Resolver.family_roles(hanime_id)
    return family_roles[tostring(hanime_id or "")] or {}
end

function Resolver.family_slots(hanime_id)
    return family_slots[tostring(hanime_id or "")] or {}
end

function Resolver.family_priorities(hanime_id)
    return family_priorities[tostring(hanime_id or "")] or {}
end

function Resolver.montage_asset_name(full_name)
    local text = tostring(full_name or "")
    local object_path = string.match(text, "([^%s]+)$") or text
    return string.match(object_path, "%.([^%.:]+)$")
        or string.match(object_path, "([^/]+)$")
        or object_path
end

function Resolver.montage_identity(asset)
    local key = normalized(asset)
    if tostring(Config.game_edition or "") ~= "demo-ue4.25" then
        return IdentityData.by_montage[key]
    end
    if (DemoTableRows.ambiguous_montages or {})[key] == true then
        return nil
    end
    local alias = (DemoTableRows.by_montage or {})[key]
    if type(alias) ~= "table" then
        return IdentityData.by_montage[key]
    end
    local family = (IdentityData.by_family or {})[tostring(alias.hanime_id or "")]
    if type(family) ~= "table" then
        return nil
    end
    local result = {}
    for name, value in pairs(IdentityData.by_montage[key] or {}) do
        result[name] = value
    end
    result.asset = result.asset or asset
    result.hanime_id = alias.hanime_id
    result.category = family.category or result.category or "other"
    result.phase = alias.phase or result.phase or "normal"
    result.participant_tag = alias.participant_tag or result.participant_tag or "generic"
    result.evidence = "demo_table_hanim_same_row"
    return result
end

function Resolver.hsystem_identity(scene_state)
    local values = scene_state and scene_state.values or {}
    local hanime_id = nil
    for _, property_name in ipairs({
        "AnimID", "CurrentAnimID", "AnimationID", "AnimName",
        "CurrentAnimName", "AnimationName", "CurrentAnimation", "CurrentMontage",
    }) do
        hanime_id = exact_family_id(values[property_name])
        if hanime_id ~= nil then
            break
        end
    end
    if hanime_id == nil then
        for _, property_name in ipairs({ "AnimID", "CurrentAnimID", "AnimationID" }) do
            hanime_id = exact_demo_table_row_family(values[property_name])
            if hanime_id ~= nil then
                break
            end
        end
    end
    local family = hanime_id and (IdentityData.by_family or {})[hanime_id] or nil
    if type(family) ~= "table" then
        return nil
    end
    return {
        hanime_id = hanime_id,
        asset = tostring(scene_state.current_animation or scene_state.anim_id or hanime_id),
        category = family.category or "other",
        phase = "normal",
        recognition_source = "hmanager_exact_anim_id",
        expected_catalog_roles = Resolver.family_roles(hanime_id),
        expected_catalog_slots = Resolver.family_slots(hanime_id),
        expected_catalog_priorities = Resolver.family_priorities(hanime_id),
        matched_components = {},
        matched_participants = {},
        active_participant_montages = 0,
        montage_full_name = scene_state.current_montage,
    }
end

function Resolver.assets_indicate_reentry(assets)
    for _, asset in ipairs(assets or {}) do
        local text = string.lower(tostring(asset or ""))
        if string.find(text, "exp_in_", 1, true)
            or string.find(text, "exp_sexing_", 1, true)
            or string.find(text, "exp_touch_in_", 1, true)
        then
            return true
        end
    end
    return false
end

function Resolver.assets_indicate_active_hanime(assets)
    for _, asset in ipairs(assets or {}) do
        local text = string.lower(tostring(asset or ""))
        if string.find(text, "exp_sexing_", 1, true)
            or string.find(text, "exp_touch_in_", 1, true)
            -- Ada's UE 5.7 HAnime keeps only facial-expression Montages
            -- visible after the exact TableHAnim Montage has established the
            -- scene. These markers may preserve an existing exact identity,
            -- but assets_indicate_reentry() intentionally does not accept
            -- them as standalone HAnime start signals.
            or string.find(text, "exp_suffocate_", 1, true)
            or string.find(text, "exp_ahegao_", 1, true)
            or string.find(text, "_spasm", 1, true)
        then
            return true
        end
    end
    return false
end

return Resolver
