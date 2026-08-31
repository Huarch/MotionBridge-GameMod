-- Playtest target contact surfaces, version-isolated from Demo.
-- Legacy women use their static M_* rigs. ADA alone uses her UE5.7 generated
-- pelvis/gen/rectum and lowercase limb hierarchy. Penetration entrances opt
-- into plane_intersection and use stable torso/thigh landmarks; deforming
-- labia/anal-ring bones are unsuitable for a per-frame intersection normal.
-- Surface contacts retain single-point translations.

local function plane(source, origin, forward, left, right, translation_mode)
    return { mode = "plane_normal", sourceBone = source, originBone = origin,
        forwardBone = forward, leftBone = left, rightBone = right,
        translationMode = translation_mode or "" }
end

local function entrance(source, origin, forward, left, right)
    local frame = plane(source, origin, forward, left, right, "plane_intersection")
    -- Keep the mode itself self-describing as well. During F10 the existing
    -- skeleton_stream serializer cannot replace its local JSON closure, but it
    -- already forwards `mode`; a normal restart additionally emits the newer
    -- translationMode field.
    frame.mode = "plane_intersection"
    return frame
end

local function axis(source, origin, base, tangent_from, tangent_to)
    return { mode = "axis_tangent", sourceBone = source, originBone = origin,
        forwardBone = base, leftBone = tangent_from, rightBone = tangent_to }
end

local function old_static_frames(anal_right)
    return {
        entrance("M_Gen", "M_Gen", "M_Spine1", "L_Thigh", "R_Thigh"),
        entrance("M_AnusInside", "M_AnusInside", "M_Spine1", "L_Thigh", "R_Thigh"),
        plane("R_Hand", "R_Hand", "R_Middle_F01", "R_Pinky_F01", "R_Index_F01"),
        plane("L_Hand", "L_Hand", "L_Middle_F01", "L_Index_F01", "L_Pinky_F01"),
        plane("R_Foot", "R_Foot", "R_Toe", "R_ToeE_01", "R_ToeA_01"),
        plane("L_Foot", "L_Foot", "L_Toe", "L_ToeA_01", "L_ToeE_01"),
        axis("R_Breast_Nipple", "R_Breast_Nipple", "R_Breast", "M_Spine3", "M_Spine4"),
        axis("L_Breast_Nipple", "L_Breast_Nipple", "L_Breast", "M_Spine4", "M_Spine3"),
        entrance("M_Jaw", "M_Jaw", "M_LowerLip_Base", "L_LipCorner", "R_LipCorner"),
    }
end

local function new_static_frames(options)
    local anal_origin = options.analOrigin
    return {
        entrance("M_Gen", "M_Gen", "M_Spine1", "L_Thigh", "R_Thigh"),
        entrance(anal_origin, anal_origin, "M_Spine1", "L_Thigh", "R_Thigh"),
        plane("R_Hand", "R_Hand", "R_Middle_F01", "R_Pinky_F01", "R_Index_F01"),
        plane("L_Hand", "L_Hand", "L_Middle_F01", "L_Index_F01", "L_Pinky_F01"),
        plane("R_Foot", "R_Foot", "R_Toe", "R_ToeE_01", "R_ToeA_01"),
        plane("L_Foot", "L_Foot", "L_Toe", "L_ToeA_01", "L_ToeE_01"),
        axis(options.rightNipple, options.rightNipple, "R_Breast_pvt_start", "M_Spine3", "M_Spine4"),
        axis(options.leftNipple, options.leftNipple, "L_Breast_pvt_start", "M_Spine4", "M_Spine3"),
        entrance(options.mouth, options.mouth, "Lower_lip", "L_lip_corner", "R_lip_corner"),
    }
end

local ada_frames = {
    entrance("gen", "gen", "spine_01", "thigh_l", "thigh_r"),
    entrance("rectum", "rectum", "spine_01", "thigh_l", "thigh_r"),
    plane("hand_r", "hand_r", "middle_01_r", "pinky_01_r", "index_01_r"),
    plane("hand_l", "hand_l", "middle_01_l", "index_01_l", "pinky_01_l"),
    plane("foot_r", "foot_r", "ball_r", "littletoe_01_r", "bigtoe_01_r"),
    plane("foot_l", "foot_l", "ball_l", "bigtoe_01_l", "littletoe_01_l"),
    axis("nipple_r", "nipple_r", "breast_root_r", "spine_03", "spine_04"),
    axis("nipple_l", "nipple_l", "breast_root_l", "spine_04", "spine_03"),
    entrance("FACIAL_C_Jaw", "FACIAL_C_Jaw", "FACIAL_C_LipLower", "FACIAL_L_LipCorner", "FACIAL_R_LipCorner"),
}

return {
    schema_version = 2,
    edition = "playtest-ue5",
    evidence = "latest extracted main-body UAsset name maps; ADA remains a separate generated rig",
    catalogs = {
        ["alet-humanoid"] = old_static_frames(),
        ["anya-humanoid"] = old_static_frames("R_Anus3"),
        ["erika-humanoid"] = old_static_frames(),
        ["ada-humanoid"] = ada_frames,
        ["galatea-humanoid"] = new_static_frames({ analOrigin = "M_Anus_Inside1", mouth = "M_Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
        ["talon-humanoid"] = new_static_frames({ analOrigin = "M_Anus_1_SRT", analForward = "M_Anus_2_SRT", mouth = "Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
        ["celia-humanoid"] = new_static_frames({ analOrigin = "M_Anus_Inside", mouth = "Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
        ["elizabeth-humanoid"] = new_static_frames({ analOrigin = "M_Anus_Inside", mouth = "Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
        ["juzi-humanoid"] = new_static_frames({ analOrigin = "M_Anus_Inside", mouth = "Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
        ["yanshi-humanoid"] = new_static_frames({ analOrigin = "M_Anus_Inside1", mouth = "M_Jaw_master", rightNipple = "R_Breast_nipple", leftNipple = "L_Breast_nipple" }),
    },
}
