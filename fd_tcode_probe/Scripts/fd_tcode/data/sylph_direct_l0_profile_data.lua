-- Exact live-output overrides for the seven Playtest Sylph drill scenes.
--
-- Drill3_0 is coincident with Drill3 in the live PSA.  The unpacked
-- REFSKELT, however, proves that the child lies 8.005407333cm along Drill3's
-- local +X.  These are deliberately L0-only profiles: the consumer must make
-- a virtual tip from Drill3's current rotation and this fixed length, then
-- project M_Gen onto that line.  No transverse/support plane or R-axis is
-- declared here.
local ids = {
    ["AletSylph_Anal01"] = "anal",
    ["AletSylph_Anal02"] = "anal",
    ["AletSylph_Vaginal01"] = "vaginal",
    ["AletSylph_Vaginal02"] = "vaginal",
    ["AletSylph_Vaginal03"] = "vaginal",
    ["AletSylph_Vaginal04"] = "vaginal",
    ["AletSylph_Vaginal05"] = "vaginal",
}

local function build_profiles(edition)
    local profiles = {}
    for id, category in pairs(ids) do
        profiles[id] = {
        id = id,
        edition = edition,
        status = "enabled_for_simulation_validation",
        deviceOutput = "l0_only",
        outputAxes = { "L0" },
        category = category,
        referenceCandidates = {
            {
                monsterDirectory = "Sylph",
                originBone = "Drill3",
                directionBone = "Drill3_0",
                tipBone = "Drill3_0",
                supportBone = "Drill3",
                axisFallback = {
                    mode = "origin_local_x_reference_length",
                    lengthCm = 8.005407333,
                    evidence = "REFSKELT Drill3->Drill3_0 is +local_x; PSA child transform is coincident",
                },
            },
        },
        targetSemantic = category == "anal" and "anal_origin" or "vaginal_origin",
        targetOwner = "alet",
        targetCatalog = "alet-humanoid",
        -- L0 is deliberately a shared, simple partner-distance channel for
        -- the robot drill set.  It always consumes Alet's stable M_Gen point,
        -- including the two Anal-labelled montages.
        targetBone = edition == "demo-ue4.25" and category == "anal" and "M_AnusInside" or "M_Gen",
        targetBasis = { up = "-local_y", right = "+local_z" },
        axes = {
            enabled = { "L0" },
            l0RangeMode = "reference_tip_length",
        },
        l0Policy = "project_target_on_drill3_local_positive_x_static_length",
        }
    end
    return profiles
end

local profiles = build_profiles("playtest-ue5")
local demo_profiles = build_profiles("demo-ue4.25")

return {
    schema_version = 1,
    revision = "sylph-direct-l0-override-v1",
    edition = "playtest-ue5",
    profile_count = 7,
    profiles = profiles,
    demo_profiles = demo_profiles,
}
