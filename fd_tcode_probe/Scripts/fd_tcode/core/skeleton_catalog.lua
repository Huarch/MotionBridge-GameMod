-- Static skeleton facts extracted from Pak4 with UE Viewer, then verified from
-- the REFSKELT chunks in Mesh_Alet.pskx and MeshMaleB.pskx. Runtime discovery
-- matches these known assets/components; it does not guess a skeleton by
-- repeatedly probing arbitrary socket names.

local Safe = require("fd_tcode.core.safe")
local Config = require("fd_tcode.config")
local direct_profiles_ok, DirectProfiles = pcall(require, "fd_tcode.data.nonhuman_direct_output_profile_data")
if not direct_profiles_ok or type(DirectProfiles) ~= "table" then
    DirectProfiles = {}
end
local component_bindings_ok, NonhumanComponentBindings = pcall(require, "fd_tcode.data.nonhuman_component_binding_data")
if not component_bindings_ok or type(NonhumanComponentBindings) ~= "table" then
    NonhumanComponentBindings = {}
end

local Catalog = {}

-- These 22 motion bones are present in every currently exported playable
-- skeleton. They form a useful full-body stream for MotionBridge without sending
-- hundreds of deformation/helper bones per character.
local humanoid_motion_bones = {
    "Master", "M_Hips",
    "M_Spine1", "M_Spine2", "M_Spine3", "M_Spine4", "M_Neck", "M_Head",
    "L_Clavicle", "L_UpperArm", "L_Forearm", "L_Hand",
    "R_Clavicle", "R_UpperArm", "R_Forearm", "R_Hand",
    "L_Thigh", "L_Shin", "L_Foot",
    "R_Thigh", "R_Shin", "R_Foot",
}

local function motion_bones(...)
    local result = {}
    local seen = {}
    for _, name in ipairs(humanoid_motion_bones) do
        seen[name] = true
        table.insert(result, name)
    end
    for _, name in ipairs({ ... }) do
        if name ~= nil and not seen[name] then
            seen[name] = true
            table.insert(result, name)
        end
    end
    return result
end

Catalog.entries = {
    alet = {
        id = "alet-humanoid",
        role = "alet",
        motion_role = "female",
        participant_tags = { "alet" },
        asset_path = "/Paralogue/Content/Characters/Alet/Body/Meshes/Mesh_Alet",
        asset_names = { "Mesh_Alet" },
        skeleton_name = "Mesh_Alet_Skeleton",
        reference_bone_count = 396,
        compatible_reference_bone_counts = { 396, 443 },
        component_markers = {
            -- UE 5.7 Playtest spawns the native actor as A_CharacterAlet
            -- instead of the older generated CharacterAlet_C class.  F6
            -- runtime inventory verifies that Mesh_Main remains the primary
            -- animated body component.
            { "A_CharacterAlet_", ".Mesh_Main" },
            { "CharacterAlet_C_", ".Mesh_Main" },
            -- Demo (UE 4.25) uses the blueprint variable name directly.
            { "CharacterAlet_C_", ".Mesh_Alet" },
        },
        primary_component_names = { "Mesh_Main", "Mesh_Alet" },
        stream_bones = motion_bones(
            "M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot",
            "R_Breast_Nipple", "L_Breast_Nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
            right_breast_contact = "R_Breast_Nipple",
            left_breast_contact = "L_Breast_Nipple",
        },
    },
    ada = {
        -- Ada is a Playtest-only body with an Unreal mannequin-style lower
        -- body, not the M_Gen/M_Hips hierarchy used by Alet and the legacy
        -- women.  Every functional name below is present in the unpacked
        -- MESH_ADA_Body REFSKELT; runtime binding is restricted to her native
        -- actor and primary body component.
        id = "ada-humanoid",
        role = "ada",
        motion_role = "female",
        participant_tags = { "ada" },
        asset_path = "/Paralogue/Content/Characters/ADA/Body/MESH_ADA_Body",
        asset_names = { "MESH_ADA_Body" },
        skeleton_name = "MESH_ADA_Body_Skeleton",
        reference_bone_count = 1608,
        component_markers = {
            { "A_CharacterADA_", ".Mesh_Main" },
        },
        primary_component_names = { "Mesh_Main" },
        stream_bones = {
            "pelvis", "spine_01", "spine_02", "spine_03", "spine_04", "spine_05",
            "neck_01", "neck_02", "head",
            "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
            "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
            "thigh_l", "calf_l", "foot_l", "ball_l",
            "thigh_r", "calf_r", "foot_r", "ball_r",
            "gen", "rectum", "FACIAL_C_Jaw", "FACIAL_C_Tongue1", "nipple_l", "nipple_r",
        },
        functional = {
            right_hand = "hand_r",
            left_hand = "hand_l",
            right_foot = "foot_r",
            left_foot = "foot_l",
            mouth_origin = "FACIAL_C_Jaw",
            tongue_origin = "FACIAL_C_Tongue1",
            -- UE 5.7 USMAP decoding confirms that gen is ADA's real reference
            -- bone directly below pelvis, matching the M_Gen -> M_Hips
            -- relationship used by the legacy women. PussySocket and
            -- M_GenSocket are fixed offsets on this same bone; labia-minora
            -- bones are local deformation children and are not stable targets.
            vaginal_origin = "gen",
            -- rectum is the stable inner landmark directly below gen. Its
            -- reference offset closely matches M_AnusInside below M_Gen on
            -- Alet; M_Anus_1 is the deforming surface ring instead.
            anal_origin = "rectum",
            right_breast_contact = "nipple_r",
            left_breast_contact = "nipple_l",
        },
    },
    male = {
        id = "male-b-humanoid",
        role = "male",
        motion_role = "male",
        participant_tags = { "male", "dreamer" },
        asset_path = "/Paralogue/Content/Characters/MaleB/MeshMaleB",
        asset_names = { "MeshMaleB" },
        skeleton_name = "MeshMaleB_Skeleton",
        reference_bone_count = 353,
        component_markers = {
            { "CharacterMaleB_C_", ".Mesh_MaleB" },
            -- Some scene blueprints expose the base class in the instance
            -- name, while retaining the unpacked Mesh_MaleB component name.
            { "CharacterMale", ".Mesh_MaleB" },
        },
        primary_component_names = { "Mesh_MaleB" },
        stream_bones = motion_bones("Penis01", "Penis02", "Penis09", "M_Jaw", "M_TongueRoot"),
        functional = {
            primary_origin = "Penis01",
            primary_tip = "Penis02",
            extended_tip = "Penis09",
            support = "M_Hips",
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
        },
    },
    erika = {
        id = "erika-humanoid",
        role = "erika",
        motion_role = "female",
        participant_tags = { "erika", "eirka" },
        asset_path = "/Paralogue/Content/Characters/Eirka/Body/Meshes/Mesh_Erika",
        asset_names = { "Mesh_Erika" },
        skeleton_name = "Mesh_Erika_Skeleton",
        reference_bone_count = 461,
        component_markers = {
            { "CharacterErika", ".Mesh" },
            { "CharacterEirka", ".Mesh" },
        },
        primary_component_names = { "Mesh", "Mesh_Main", "Mesh_Erika" },
        stream_bones = motion_bones(
            "M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot",
            "R_Breast_Nipple", "L_Breast_Nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
            right_breast_contact = "R_Breast_Nipple",
            left_breast_contact = "L_Breast_Nipple",
        },
    },
    galatea = {
        id = "galatea-humanoid",
        role = "galatea",
        motion_role = "female",
        participant_tags = { "galatea", "gala" },
        asset_path = "/Paralogue/Content/Characters/Galatea/Body/Mesh_Galatea",
        asset_names = { "Mesh_Galatea" },
        skeleton_name = "Mesh_Galatea_Skeleton",
        reference_bone_count = 511,
        component_markers = {
            -- UE 5.7 Playtest spawns Galatea through A_CharacterGala. Keep the
            -- older CharacterGalatea marker for compatibility with extracted
            -- assets and earlier builds.
            { "A_CharacterGala_", ".Mesh_Main" },
            { "CharacterGala", ".Mesh_Main" },
            { "CharacterGalatea", ".Mesh" },
        },
        primary_component_names = { "Mesh", "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_Inside1", "M_Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside1",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    talon = {
        id = "talon-humanoid",
        role = "talon",
        motion_role = "female",
        participant_tags = { "talon" },
        asset_path = "/Paralogue/Content/Characters/Talon/Body/Meshes/mesh_talon",
        asset_names = { "mesh_talon", "Mesh_Talon_Copy" },
        skeleton_name = "mesh_talon_Skeleton",
        component_markers = {
            { "A_CharacterTalon_", ".Mesh_Main" },
            { "CharacterTalon", ".Mesh_Main" },
        },
        primary_component_names = { "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_1_SRT", "Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            -- The UE 5.7 Talon skeleton has no M_Anus_Inside bone. The exact
            -- unpacked central ring landmark is M_Anus_1_SRT.
            anal_origin = "M_Anus_1_SRT",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    celia = {
        id = "celia-humanoid",
        role = "celia",
        motion_role = "female",
        participant_tags = { "celia", "ceila" },
        asset_path = "/Paralogue/Content/Characters/Celia/Body/MeshCelia",
        asset_names = { "MeshCelia" },
        skeleton_name = "MeshCelia_Skeleton_VB",
        component_markers = {
            { "A_CharacterCelia_", ".Mesh_Main" },
            { "CharacterCelia", ".Mesh_Main" },
        },
        primary_component_names = { "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_Inside", "Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    elizabeth = {
        id = "elizabeth-humanoid",
        role = "elizabeth",
        motion_role = "female",
        participant_tags = { "elizabeth" },
        asset_path = "/Paralogue/Content/Characters/elizabeth/Body/Meshes/Mesh_Elizabeth",
        asset_names = { "Mesh_Elizabeth" },
        skeleton_name = "Mesh_Elizabeth_Skeleton_VBFix",
        component_markers = {
            { "A_CharacterElizabeth_", ".Mesh_Main" },
            { "CharacterElizabeth", ".Mesh_Main" },
        },
        primary_component_names = { "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_Inside", "Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    juzi = {
        id = "juzi-humanoid",
        role = "juzi",
        motion_role = "female",
        participant_tags = { "juzi", "juzhi" },
        asset_path = "/Paralogue/Content/Characters/Juzhi/Body/Meshes/Mesh_Juzi",
        asset_names = { "Mesh_Juzi" },
        skeleton_name = "Mesh_Juzi_Skeleton",
        reference_bone_count = 573,
        component_markers = {
            { "CharacterJuzi", ".Mesh" },
            { "CharacterJuzhi", ".Mesh" },
        },
        primary_component_names = { "Mesh", "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_Inside", "Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    yanshi = {
        id = "yanshi-humanoid",
        role = "yanshi",
        motion_role = "female",
        participant_tags = { "yanshi" },
        asset_path = "/Paralogue/Content/Characters/yanshi/Body/Meshes/Mesh_yanshi",
        asset_names = { "Mesh_yanshi" },
        skeleton_name = "Mesh_yanshi_Skeleton",
        reference_bone_count = 869,
        component_markers = {
            { "Characteryanshi", ".Mesh_Main" },
            { "CharacterYanshi", ".Mesh_Main" },
        },
        -- Confirmed at runtime in Room_SinglePCMain. The modular body, hair,
        -- hands and clothing components share Mesh_yanshi as SkinnedAsset but
        -- only Mesh_Main owns the character's complete animated pose.
        primary_component_names = { "Mesh_Main" },
        stream_bones = motion_bones(
            "M_Gen", "M_Anus_Inside1", "M_Jaw_master", "M_TongueRoot",
            "R_Breast_nipple", "L_Breast_nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside1",
            right_breast_contact = "R_Breast_nipple",
            left_breast_contact = "L_Breast_nipple",
        },
    },
    anya = {
        id = "anya-humanoid",
        role = "anya",
        motion_role = "female",
        participant_tags = { "anya" },
        asset_path = "/Paralogue/Content/Characters/Anya/Body/MeshAnya",
        asset_names = { "MeshAnya" },
        skeleton_name = "MeshAnya_Skeleton",
        reference_bone_count = 852,
        component_markers = {
            { "CharacterAnya", ".Mesh" },
        },
        primary_component_names = { "Mesh", "Mesh_Main", "Mesh_Anya" },
        stream_bones = motion_bones(
            "M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot",
            "R_Breast_Nipple", "L_Breast_Nipple"
        ),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
            right_breast_contact = "R_Breast_Nipple",
            left_breast_contact = "L_Breast_Nipple",
        },
    },
}

-- Nonhuman entries are generated solely from the unpacked REFSKELT mesh
-- inventory plus exact TableHAnim companion-Montage tags.  They deliberately
-- share the output motion role "male": this feeds the proven four-reference
-- bone SR6 path, while catalog IDs remain species-specific for binding and
-- diagnostics.  Unlike modular humanoids, these meshes are their actor's
-- only animated body component, so a verified asset match is primary.
local nonhuman_primary_component_names = {
    ["playtest-ue5"] = {
        -- Runtime evidence from the UE 5.7 Ghoul actor shows DickCap and
        -- Mesh_Ghoul_opacity sharing the body SkinnedAsset. Only Mesh_Ghoul
        -- owns the stable reference skeleton used by the motion contract.
        Ghoul = { "Mesh_Ghoul" },
        -- TchoTcho switches body components with the game's character-display
        -- mode. The ordinary model animates Mesh_TchoTcho; hide/opacity mode
        -- regenerates the actor and animates Mesh_TchoTcho_opacity instead.
        -- Both are legitimate body meshes. DickCap remains excluded.
        TchoTcho = { "Mesh_TchoTcho", "Mesh_TchoTcho_opacity" },
    },
}
local nonhuman_primary_anim_blueprint_classes = {
    ["playtest-ue5"] = {
        -- When both TchoTcho body components exist on an actor, the one which
        -- currently owns this AnimBP is the live motion source. This is a
        -- transition-time binding hint, not a visibility test or bone scan.
        TchoTcho = { "AMBP_TchoTcho_C" },
    },
}
for _, source in ipairs(DirectProfiles.catalogEntries or {}) do
    if tostring(source.edition or "") == tostring(Config.game_edition or "") then
        local role_key = tostring(source.roleKey or "")
        if role_key ~= "" and Catalog.entries[role_key] == nil then
            local edition_primary_names = nonhuman_primary_component_names[tostring(source.edition or "")] or {}
            local primary_names = edition_primary_names[tostring(source.monsterDirectory or "")] or {}
            local edition_primary_anim_classes = nonhuman_primary_anim_blueprint_classes[
                tostring(source.edition or "")
            ] or {}
            Catalog.entries[role_key] = {
                id = tostring(source.id or role_key),
                role = role_key,
                motion_role = "male",
                participant_tags = source.participantTags or {},
                asset_names = source.assetNames or {},
                primary_component_names = primary_names,
                preferred_anim_blueprint_classes = edition_primary_anim_classes[
                    tostring(source.monsterDirectory or "")
                ] or {},
                allow_asset_primary = #primary_names == 0,
                nonhuman_direct = true,
                monster_directory = tostring(source.monsterDirectory or ""),
                functional = {},
            }
        end
    end
end

Catalog.by_id = {}
for _, entry in pairs(Catalog.entries) do
    Catalog.by_id[entry.id] = entry
end

function Catalog.get(catalog_id)
    return Catalog.by_id[catalog_id]
end

local function normalized_tag(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

function Catalog.role_for_participant_tag(participant_tag)
    local normalized = normalized_tag(participant_tag)
    if normalized == "" then
        return nil
    end
    for role, entry in pairs(Catalog.entries) do
        for _, marker in ipairs(entry.participant_tags or {}) do
            -- Participant tags are exported as role-prefixed identifiers such
            -- as Dreamer_A_01 and Yanshi_01. Match that static prefix only;
            -- a substring match could bind a future unrelated catalog name.
            if string.find(normalized, normalized_tag(marker), 1, true) == 1 then
                return role
            end
        end
    end
    return nil
end

local function short_object_name(full_name)
    if full_name == nil then
        return nil
    end
    local tail = string.match(full_name, "([^%./:]+)$")
    return tail or full_name
end

local function read_skinned_asset_name(component)
    -- UE 5.5 exposes the active mesh through SkinnedAsset; SkeletalMesh is
    -- retained as a compatibility fallback for builds that expose the old
    -- property name to UE4SS Lua.
    for _, property_name in ipairs({ "SkinnedAsset", "SkeletalMesh" }) do
        local ok, asset = Safe.read(component, property_name)
        if ok and asset ~= nil then
            local full_name = Safe.object_name(asset)
            if full_name ~= nil then
                return short_object_name(full_name), full_name, property_name
            end
            local text = Safe.value_text(asset)
            if text ~= nil and text ~= "<nil>" then
                return short_object_name(text), text, property_name
            end
        end
    end
    return nil, nil, nil
end

local function asset_matches(entry, asset_name, asset_full_name)
    for _, known_name in ipairs(entry.asset_names or {}) do
        if asset_name == known_name then
            return true
        end
        if asset_full_name ~= nil and string.find(asset_full_name, known_name, 1, true) then
            return true
        end
    end
    return false
end

local function component_name_matches(entry, component_name)
    for _, markers in ipairs(entry.component_markers or {}) do
        local matches = true
        for _, marker in ipairs(markers) do
            if not string.find(component_name, marker, 1, true) then
                matches = false
                break
            end
        end
        if matches then
            return true
        end
    end
    return false
end

function Catalog.role_for_actor(actor)
    local actor_name = Safe.object_name(actor) or ""
    if actor_name == "" then
        return nil
    end
    for role, entry in pairs(Catalog.entries) do
        for _, marker in ipairs(entry.component_markers or {}) do
            if string.find(actor_name, tostring(marker[1] or ""), 1, true) then
                return role
            end
        end
        if entry.nonhuman_direct == true then
            local actor_token = normalized_tag("Character" .. tostring(entry.monster_directory or ""))
            if actor_token ~= "" and string.find(normalized_tag(actor_name), actor_token, 1, true) then
                return role
            end
        end
    end
    return nil
end

local function exact_nonhuman_component_name_matches(entry, component_name)
    if entry.nonhuman_direct ~= true then
        return false
    end
    local component_leaf = short_object_name(component_name)
    for _, known_asset_name in ipairs(entry.asset_names or {}) do
        -- The names come from the unpacked primary mesh inventory. Exact
        -- equality deliberately excludes opacity/helper components.
        if component_leaf == known_asset_name then
            return true
        end
    end
    return false
end

local function match_unpacked_nonhuman_component(component_name)
    local edition_bindings = NonhumanComponentBindings[tostring(Config.game_edition or "")] or {}
    local component_leaf = short_object_name(component_name)
    for directory, binding in pairs(edition_bindings) do
        if type(binding) == "table"
            and component_leaf == tostring(binding.componentName or "")
        then
            local owner_class = tostring(binding.ownerClass or "")
            -- Safe.object_name normally includes the owning actor instance.
            -- If this UE4SS build returns only the leaf, the exact primary
            -- component identity remains unique within this static table.
            if owner_class == ""
                or string.find(component_name, owner_class .. "_", 1, true)
                or component_name == component_leaf
            then
                for role, entry in pairs(Catalog.entries) do
                    if entry.nonhuman_direct == true
                        and tostring(entry.monster_directory or "") == tostring(directory)
                    then
                        return role, entry, {
                            method = "unpacked-blueprint-component",
                            component = component_name,
                            asset = nil,
                            property = nil,
                        }
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

function Catalog.match_component(component)
    local component_name = Safe.object_name(component) or ""
    local asset_name, asset_full_name, property_name = read_skinned_asset_name(component)

    for role, entry in pairs(Catalog.entries) do
        if asset_matches(entry, asset_name, asset_full_name) then
            return role, entry, {
                method = "skinned-asset",
                component = component_name,
                asset = asset_full_name,
                property = property_name,
            }
        end
    end

    -- Demo UE4.25 may hide SkeletalMesh/SkinAsset from Lua.  Bind the exact
    -- primary component exported from its Blueprint before HAnime detection;
    -- otherwise the companion Montage is never observed and the later
    -- HAnime-specific recovery scan cannot run.
    local unpacked_role, unpacked_entry, unpacked_evidence = match_unpacked_nonhuman_component(component_name)
    if unpacked_entry ~= nil then
        unpacked_evidence.asset = asset_full_name
        unpacked_evidence.property = property_name
        return unpacked_role, unpacked_entry, unpacked_evidence
    end

    -- Playtest normally exposes SkinnedAsset, but some spawned nonhuman
    -- actors expose only the component leaf to UE4SS Lua. The exact unpacked
    -- primary mesh identity is still sufficient and avoids a category/name
    -- heuristic or a bone probe.
    for role, entry in pairs(Catalog.entries) do
        if exact_nonhuman_component_name_matches(entry, component_name) then
            return role, entry, {
                method = "unpacked-primary-component-name",
                component = component_name,
                asset = asset_full_name,
                property = property_name,
            }
        end
    end

    -- This fallback is also static: component markers come from the unpacked
    -- CharacterAlet/CharacterMaleB blueprints, not from bone-name probing.
    for role, entry in pairs(Catalog.entries) do
        if component_name_matches(entry, component_name) then
            return role, entry, {
                method = "blueprint-component",
                component = component_name,
                asset = asset_full_name,
                property = property_name,
            }
        end
    end

    return nil, nil, nil
end

-- Direct nonhuman profiles declare the authoritative monster directory.
-- Resolve against that exact declaration rather than using the generic first
-- asset match, because canonical and supplemental entries can share meshes.
function Catalog.match_component_for_monster_directory(component, monster_directory)
    local wanted = tostring(monster_directory or "")
    if wanted == "" then
        return nil, nil, nil
    end
    local component_name = Safe.object_name(component) or ""
    local asset_name, asset_full_name, property_name = read_skinned_asset_name(component)
    for role, entry in pairs(Catalog.entries) do
        if entry.nonhuman_direct == true
            and tostring(entry.monster_directory or "") == wanted
            and asset_matches(entry, asset_name, asset_full_name)
        then
            return role, entry, {
                method = "direct-profile-skinned-asset",
                component = component_name,
                asset = asset_full_name,
                property = property_name,
            }
        end
    end

    -- UE 4.25 Demo does not consistently expose SkeletalMesh to UE4SS Lua.
    -- Use the exact owner Blueprint and primary component template exported
    -- from the package instead.  This cannot select similarly named opacity
    -- or helper components.
    local component_leaf = short_object_name(component_name)
    local edition_bindings = NonhumanComponentBindings[tostring(Config.game_edition or "")] or {}
    local exact_binding = edition_bindings[wanted]
    if type(exact_binding) == "table"
        and component_leaf == tostring(exact_binding.componentName or "")
        and string.find(component_name, tostring(exact_binding.ownerClass or "") .. "_", 1, true)
    then
        for role, entry in pairs(Catalog.entries) do
            if entry.nonhuman_direct == true
                and tostring(entry.monster_directory or "") == wanted
            then
                return role, entry, {
                    method = "direct-profile-unpacked-blueprint-component",
                    component = component_name,
                    asset = asset_full_name,
                    property = property_name,
                }
            end
        end
    end

    -- Some UE4SS object-name builds omit the owning actor from the printed
    -- component name.  The exact exported primary component name is still
    -- unambiguous within this restricted HAnime directory lookup.
    if type(exact_binding) == "table"
        and component_leaf == tostring(exact_binding.componentName or "")
    then
        for role, entry in pairs(Catalog.entries) do
            if entry.nonhuman_direct == true
                and tostring(entry.monster_directory or "") == wanted
            then
                return role, entry, {
                    method = "direct-profile-unpacked-component",
                    component = component_name,
                    asset = asset_full_name,
                    property = property_name,
                }
            end
        end
    end

    -- Retain exact unsuffixed component identity for editions whose runtime
    -- object printer removes Unreal's _GEN_VARIABLE suffix.
    for role, entry in pairs(Catalog.entries) do
        if tostring(entry.monster_directory or "") == wanted
            and exact_nonhuman_component_name_matches(entry, component_name)
        then
            return role, entry, {
                method = "direct-profile-blueprint-component",
                component = component_name,
                asset = asset_full_name,
                property = property_name,
            }
        end
    end
    return nil, nil, nil
end

function Catalog.is_primary_component(component, entry)
    local selected_entry = entry
    if selected_entry == nil then
        local _, matched_entry = Catalog.match_component(component)
        selected_entry = matched_entry
    end
    if selected_entry == nil then
        return false
    end
    if selected_entry.allow_asset_primary == true then
        return true
    end
    local full_name = Safe.object_name(component) or ""
    local leaf_name = string.match(full_name, "%.([^%.]+)$") or full_name
    for _, known_name in ipairs(selected_entry.primary_component_names or {}) do
        if leaf_name == known_name then
            return true
        end
    end
    return false
end

local function find_owned_component_by_path(owner_name, component_leaf)
    if type(StaticFindObject) ~= "function" then
        return nil
    end
    local owner_path = string.match(tostring(owner_name or ""), "([^%s]+)$")
    if owner_path == nil or owner_path == "" then
        return nil
    end
    local candidate_path = owner_path .. "." .. tostring(component_leaf or "")
    for _, lookup_name in ipairs({ candidate_path, "SkeletalMeshComponent " .. candidate_path }) do
        local lookup_ok, candidate = pcall(StaticFindObject, lookup_name)
        if lookup_ok and Safe.is_object(candidate) then
            return candidate
        end
    end
    return nil
end

local function actor_matches_entry(actor_name, entry)
    for _, marker in ipairs(entry.component_markers or {}) do
        if string.find(actor_name, tostring(marker[1] or ""), 1, true) then
            return true
        end
    end
    if entry.nonhuman_direct == true then
        local actor_token = normalized_tag("Character" .. tostring(entry.monster_directory or ""))
        return actor_token ~= ""
            and string.find(normalized_tag(actor_name), actor_token, 1, true) ~= nil
    end
    return false
end

-- Find the authoritative body mesh next to a helper/POV component.  The
-- property names and owner markers are extracted static facts from the
-- character Blueprints; this does not enumerate components or probe bones.
function Catalog.primary_components_from_actor(actor)
    if not Safe.is_object(actor) then
        return {}
    end

    local actor_name = Safe.object_name(actor) or ""
    local result = {}
    local seen = {}
    for role, entry in pairs(Catalog.entries) do
        local owner_matches = actor_matches_entry(actor_name, entry)
        if owner_matches then
            for _, property_name in ipairs(entry.primary_component_names or {}) do
                local property_ok, component = Safe.read(actor, property_name)
                if not property_ok or not Safe.is_object(component) then
                    component = find_owned_component_by_path(actor_name, property_name)
                    property_ok = Safe.is_object(component)
                end
                if property_ok
                    and Safe.is_object(component)
                    and Catalog.is_primary_component(component, entry)
                then
                    local component_name = Safe.object_name(component)
                    if component_name ~= nil and not seen[component_name] then
                        seen[component_name] = true
                        table.insert(result, {
                            component = component,
                            role = role,
                            entry = entry,
                            property_name = property_name,
                        })
                    end
                end
            end
        end
    end
    return result
end

function Catalog.resolve_primary_sibling(component)
    if not Safe.is_object(component) then
        return nil, nil, nil
    end

    local current_role, current_entry = Catalog.match_component(component)
    if current_entry ~= nil and Catalog.is_primary_component(component, current_entry) then
        return component, current_role, current_entry
    end

    local owner = Safe.outer(component)
    local owner_name = Safe.object_name(owner) or ""
    if owner_name == "" then
        return component, current_role, current_entry
    end

    for role, entry in pairs(Catalog.entries) do
        local owner_matches = actor_matches_entry(owner_name, entry)
        if owner_matches then
            for _, property_name in ipairs(entry.primary_component_names or {}) do
                local property_ok, candidate = Safe.read(owner, property_name)
                if not property_ok or not Safe.is_object(candidate) then
                    candidate = find_owned_component_by_path(owner_name, property_name)
                    property_ok = Safe.is_object(candidate)
                end
                if property_ok
                    and Safe.is_object(candidate)
                    and Catalog.is_primary_component(candidate, entry)
                then
                    local matched_role, matched_entry = Catalog.match_component(candidate)
                    if matched_entry == entry then
                        return candidate, matched_role or role, entry
                    end
                end
            end
        end
    end

    return component, current_role, current_entry
end

return Catalog
