-- Static skeleton facts extracted from Pak4 with UE Viewer, then verified from
-- the REFSKELT chunks in Mesh_Alet.pskx and MeshMaleB.pskx. Runtime discovery
-- matches these known assets/components; it does not guess a skeleton by
-- repeatedly probing arbitrary socket names.

local Safe = require("fd_tcode.safe")

local Catalog = {}

-- These 24 motion bones are present in every currently exported playable
-- skeleton. They form a useful full-body stream for F8Studio without sending
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
        asset_path = "/Paralogue/Content/Characters/Alet/Body/Meshes/Mesh_Alet",
        asset_names = { "Mesh_Alet" },
        skeleton_name = "Mesh_Alet_Skeleton",
        reference_bone_count = 396,
        component_markers = {
            { "CharacterAlet_C_", ".Mesh_Main" },
        },
        stream_bones = motion_bones("M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
        },
    },
    male = {
        id = "male-b-humanoid",
        role = "male",
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
        stream_bones = motion_bones("Penis01", "Penis02", "Penis09", "M_Jaw", "M_TongueRoot"),
        functional = {
            primary_origin = "Penis01",
            primary_tip = "Penis02",
            extended_tip = "Penis09",
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
        asset_path = "/Paralogue/Content/Characters/Eirka/Body/Meshes/Mesh_Erika",
        asset_names = { "Mesh_Erika" },
        skeleton_name = "Mesh_Erika_Skeleton",
        reference_bone_count = 461,
        component_markers = {
            { "CharacterErika", ".Mesh" },
            { "CharacterEirka", ".Mesh" },
        },
        stream_bones = motion_bones("M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
        },
    },
    galatea = {
        id = "galatea-humanoid",
        role = "galatea",
        asset_path = "/Paralogue/Content/Characters/Galatea/Body/Mesh_Galatea",
        asset_names = { "Mesh_Galatea" },
        skeleton_name = "Mesh_Galatea_Skeleton",
        reference_bone_count = 511,
        component_markers = {
            { "CharacterGalatea", ".Mesh" },
        },
        stream_bones = motion_bones("M_Gen", "M_Anus_Inside1", "M_Jaw_master", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside1",
        },
    },
    juzi = {
        id = "juzi-humanoid",
        role = "juzi",
        asset_path = "/Paralogue/Content/Characters/Juzhi/Body/Meshes/Mesh_Juzi",
        asset_names = { "Mesh_Juzi" },
        skeleton_name = "Mesh_Juzi_Skeleton",
        reference_bone_count = 573,
        component_markers = {
            { "CharacterJuzi", ".Mesh" },
            { "CharacterJuzhi", ".Mesh" },
        },
        stream_bones = motion_bones("M_Gen", "M_Anus_Inside", "Jaw_master", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside",
        },
    },
    yanshi = {
        id = "yanshi-humanoid",
        role = "yanshi",
        asset_path = "/Paralogue/Content/Characters/yanshi/Body/Meshes/Mesh_yanshi",
        asset_names = { "Mesh_yanshi" },
        skeleton_name = "Mesh_yanshi_Skeleton",
        reference_bone_count = 869,
        component_markers = {
            { "Characteryanshi", ".Mesh" },
            { "CharacterYanshi", ".Mesh" },
        },
        stream_bones = motion_bones("M_Gen", "M_Anus_Inside1", "M_Jaw_master", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw_master",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_Anus_Inside1",
        },
    },
    anya = {
        id = "anya-humanoid",
        role = "anya",
        asset_path = "/Paralogue/Content/Characters/Anya/Body/MeshAnya",
        asset_names = { "MeshAnya" },
        skeleton_name = "MeshAnya_Skeleton",
        reference_bone_count = 852,
        component_markers = {
            { "CharacterAnya", ".Mesh" },
        },
        stream_bones = motion_bones("M_Gen", "M_AnusInside", "M_Jaw", "M_TongueRoot"),
        functional = {
            right_hand = "R_Hand",
            left_hand = "L_Hand",
            right_foot = "R_Foot",
            left_foot = "L_Foot",
            mouth_origin = "M_Jaw",
            tongue_origin = "M_TongueRoot",
            vaginal_origin = "M_Gen",
            anal_origin = "M_AnusInside",
        },
    },
}

Catalog.by_id = {}
for _, entry in pairs(Catalog.entries) do
    Catalog.by_id[entry.id] = entry
end

function Catalog.get(catalog_id)
    return Catalog.by_id[catalog_id]
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
    for _, known_name in ipairs(entry.asset_names) do
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
    for _, markers in ipairs(entry.component_markers) do
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

return Catalog
