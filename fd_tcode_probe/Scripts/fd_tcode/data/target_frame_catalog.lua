-- Demo UE4.25 target contact surfaces verified from exported REFSKELT data.
-- Penetration entrances use a stable torso/thigh plane for translations;
-- deforming labia/anal-ring bones are deliberately excluded from the
-- per-frame intersection normal. Surface contacts retain point translations.

local function plane(source, origin, forward, left, right, translation_mode)
    return {
        mode = "plane_normal",
        translationMode = translation_mode or "",
        sourceBone = source,
        originBone = origin,
        forwardBone = forward,
        leftBone = left,
        rightBone = right,
    }
end

local function entrance(source, origin)
    local frame = plane(source, origin, "M_Spine1", "L_Thigh", "R_Thigh", "plane_intersection")
    -- `mode` remains self-describing for a running serializer that predates
    -- translationMode during an F10 hot reload.
    frame.mode = "plane_intersection"
    return frame
end

local function axis(source, origin, base, tangent_from, tangent_to)
    return {
        mode = "axis_tangent",
        sourceBone = source,
        originBone = origin,
        forwardBone = base,
        leftBone = tangent_from,
        rightBone = tangent_to,
    }
end

local function legacy_woman_frames()
    return {
        entrance("M_Gen", "M_Gen"),
        entrance("M_AnusInside", "M_AnusInside"),
        plane("R_Hand", "R_Hand", "R_Middle_F01", "R_Pinky_F01", "R_Index_F01"),
        plane("L_Hand", "L_Hand", "L_Middle_F01", "L_Index_F01", "L_Pinky_F01"),
        plane("R_Foot", "R_Foot", "R_Toe", "R_ToeE_01", "R_ToeA_01"),
        plane("L_Foot", "L_Foot", "L_Toe", "L_ToeA_01", "L_ToeE_01"),
        axis("R_Breast_Nipple", "R_Breast_Nipple", "R_Breast", "M_Spine3", "M_Spine4"),
        axis("L_Breast_Nipple", "L_Breast_Nipple", "L_Breast", "M_Spine4", "M_Spine3"),
        plane("M_Jaw", "M_Jaw", "M_LowerLip_Base", "L_LipCorner", "R_LipCorner"),
    }
end

return {
    schema_version = 2,
    edition = "demo-ue4.25",
    evidence = "Demo Mesh_Alet.pskx and Mesh_Erika.pskx REFSKELT",
    catalogs = {
        ["alet-humanoid"] = legacy_woman_frames(),
        ["erika-humanoid"] = legacy_woman_frames(),
    },
}
