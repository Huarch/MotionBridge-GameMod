-- Verified low-cost body reference planes.  The entries are derived from the
-- exported REFSKELT hierarchies, never from a runtime bone-name scan.  A plane
-- uses left/right anchors plus a centre and a trunk-forward landmark.
--
-- These planes improve geometric interpretation in Motion Bridge.  They do
-- not by themselves enable nonhuman rotation output: R axes remain guarded by
-- config.nonhuman_rotation_axes_enabled until each template is calibrated in
-- a representative HAnime.

return {
    ["demo-ue4.25"] = {
        -- DeepOne exposes the same verified four pelvis landmarks, so its
        -- geometry can use this plane without classifying the creature itself.
        DeepOne = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        -- Ghast is the Demo's humanoid nonhuman character and uses the
        -- verified standard pelvis landmarks from its exported skeleton.
        Ghast = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        -- Demo component binding uses the exact directory key "Byakhee".
        Byakhee = {
            mode = "winged_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
        ElderThingSupplemental = {
            mode = "radial_trunk",
            centerBone = "Root_M",
            forwardBone = "Spine1_M",
            leftBone = "BackLeg1_L",
            rightBone = "BackLeg1_R",
        },
        Hound = {
            mode = "quadruped_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
        Lloigor = {
            mode = "winged_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
        ShaggaiSupplemental = {
            mode = "insectoid_trunk",
            centerBone = "Reoot_M",
            forwardBone = "Spine1_M",
            leftBone = "MiddleLeg1_L",
            rightBone = "MiddleLeg1_R",
        },
        SkorpiosSupplemental = {
            mode = "arachnid_trunk",
            centerBone = "Root_M",
            forwardBone = "hipsplineIkBnA",
            leftBone = "MiddleLeg1_L",
            rightBone = "MiddleLeg1_R",
        },
        Sylph = {
            mode = "sylph_trunk",
            centerBone = "waist_M",
            forwardBone = "neck_M",
            leftBone = "shoulder_L",
            rightBone = "shoulder_R",
        },
        Tentacle = {
            mode = "radial_tentacle_base",
            centerBone = "pasted__body_joint",
            forwardBone = "waist_jiointBnA",
            leftBone = "Skirt_old13",
            rightBone = "Skirt_old37",
        },
    },
    ["playtest-ue5"] = {
        DeepOne = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        Ghast = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        Ghoul = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        TchoTcho = {
            mode = "humanoid_pelvis",
            centerBone = "M_Hips",
            forwardBone = "M_Spine1",
            leftBone = "L_Thigh",
            rightBone = "R_Thigh",
        },
        guge = {
            mode = "biped_rigified",
            centerBone = "spine_C0_0_jnt",
            forwardBone = "spine_C0_1_jnt",
            leftBone = "leg_L0_0_jnt",
            rightBone = "leg_R0_0_jnt",
        },
        yeyan = {
            mode = "biped_winged",
            centerBone = "spine_C0_pelvis_Jnt",
            forwardBone = "spine_C0_spine_01_Jnt",
            leftBone = "legBack_L0_0_Jnt",
            rightBone = "legBack_R0_0_Jnt",
        },
        FlyCreature = {
            mode = "winged_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
        Hound = {
            mode = "quadruped_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
        RevenantOfSaaitii_1 = {
            mode = "quadruped_trunk",
            centerBone = "Root_M",
            forwardBone = "Chest_M",
            leftBone = "Hip_L",
            rightBone = "Hip_R",
        },
    },
}
