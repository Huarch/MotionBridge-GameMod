-- Unified per-participant motion contract resolution.
--
-- Every exact HAnime follows the same runtime path. Generated sidecars may
-- override which bones form the reference/target, but the detector and bone
-- sampler do not contain edition-, species-, or interaction-specific branches.

local Config = require("fd_tcode.config")

local function optional_table(module_name)
    local ok, value = pcall(require, module_name)
    return ok and type(value) == "table" and value or {}
end

local DirectProfiles = optional_table("fd_tcode.data.nonhuman_direct_output_profile_data")
local DemoNonhumanCalibration = optional_table("fd_tcode.data.demo_nonhuman_calibration_data")
local SylphL0Profiles = optional_table("fd_tcode.data.sylph_direct_l0_profile_data")
local DirectFFProfiles = optional_table("fd_tcode.data.female_female_direct_l0_profile_data")
local BodyPlanes = optional_table("fd_tcode.data.body_plane_catalog")
local TargetFrames = optional_table("fd_tcode.data.target_frame_catalog")

local Contract = {}

-- Categories rank candidates only. Hand/foot ambiguity remains explicit: all
-- useful sides are emitted and Motion Bridge applies the user's selection.
local target_functions_by_category = {
    mouth = { "mouth_origin", "tongue_origin" },
    anal = { "anal_origin" },
    vaginal = { "vaginal_origin" },
}

local candidate_functions_by_category = {
    hand = { "right_hand", "left_hand" },
    foot = { "right_foot", "left_foot" },
    breast = { "right_breast_contact", "left_breast_contact" },
    mouth = { "mouth_origin", "tongue_origin" },
    anal = { "anal_origin" },
    vaginal = { "vaginal_origin" },
    other = {
        "vaginal_origin", "anal_origin",
        "mouth_origin", "tongue_origin",
        "right_hand", "left_hand",
        "right_foot", "left_foot",
    },
}

target_functions_by_category.other = candidate_functions_by_category.other

local target_functions_by_hanime_id = {
    AletMale_Hand01 = { "right_hand", "left_hand" },
    AletMale_Hand02 = { "right_hand", "left_hand" },
    AletMale_Hand03 = { "right_hand", "left_hand" },
    JuziDreamer_Sleep01 = { "vaginal_origin" },
}

-- A multi-contact HAnime is not a single category with a longer target list.
-- Each reference slot owns an explicit target contact.  Keep the pair data
-- exact and small so the stream contains only the required target bones,
-- rather than a wider body scan.  AletMaleAB_VaginalMouth02 has separate
-- runtime geometry evidence; the remaining package-derived bindings still
-- require the normal per-pose runtime geometry check before calibration.
local function contact_pair(id, participant_slot, participant_tag, catalog_id, semantic, bone)
    return {
        id = id,
        reference = { participantSlot = participant_slot },
        target = {
            participantTag = participant_tag,
            catalogId = catalog_id,
            semantic = semantic,
            bone = bone,
        },
    }
end

local contact_pairs_by_hanime_id = {
    -- TableHAnim's MaleAB/DreamerAB families provide two independent male
    -- streams.  These entries intentionally bind each stream to its own
    -- character contact point; never fall back to the family's category.
    AletMaleAB_VaginalHand01 = {
        contact_pair("hand-a", "a", "Alet_01", "alet-humanoid", "right_hand", "R_Hand"),
        contact_pair("vaginal-b", "b", "Alet_01", "alet-humanoid", "vaginal_origin", "M_Gen"),
    },
    AletMaleAB_VaginalMouth01 = {
        contact_pair("mouth-a", "a", "Alet_01", "alet-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Alet_01", "alet-humanoid", "vaginal_origin", "M_Gen"),
    },
    AletMaleAB_VaginalMouth02 = {
        contact_pair("mouth-a", "a", "Alet_01", "alet-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Alet_01", "alet-humanoid", "vaginal_origin", "M_Gen"),
    },
    -- The first male in this older naming family is called `Male` rather
    -- than `Male_A`.  Resolver.participant_slot() exports it as `generic`;
    -- it is nevertheless a distinct, stable reference stream.
    AnyaMaleAB_AnalHand01 = {
        contact_pair("hand-generic", "generic", "Anya_01", "anya-humanoid", "right_hand", "R_Hand"),
        contact_pair("anal-b", "b", "Anya_01", "anya-humanoid", "anal_origin", "M_AnusInside"),
    },
    AnyaMaleAB_VaginalMouth01 = {
        contact_pair("mouth-a", "a", "Anya_01", "anya-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Anya_01", "anya-humanoid", "vaginal_origin", "M_Gen"),
    },
    AnyaMaleAB_VaginalMouth02 = {
        contact_pair("mouth-a", "a", "Anya_01", "anya-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Anya_01", "anya-humanoid", "vaginal_origin", "M_Gen"),
    },
    AnyaMale_AB_VagialAnal01 = {
        contact_pair("anal-a", "a", "Anya_01", "anya-humanoid", "anal_origin", "M_AnusInside"),
        contact_pair("vaginal-b", "b", "Anya_01", "anya-humanoid", "vaginal_origin", "M_Gen"),
    },
    ErikaMaleAB_Vagina_Mouth03 = {
        contact_pair("mouth-a", "a", "Erika_01", "erika-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Erika_01", "erika-humanoid", "vaginal_origin", "M_Gen"),
    },
    ErikaMaleAB_VaginalMouth01 = {
        contact_pair("mouth-a", "a", "Erika_01", "erika-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Erika_01", "erika-humanoid", "vaginal_origin", "M_Gen"),
    },
    ErikaMaleAB_VaginalMouth02 = {
        contact_pair("mouth-a", "a", "Erika_01", "erika-humanoid", "mouth_origin", "M_Jaw"),
        contact_pair("vaginal-b", "b", "Erika_01", "erika-humanoid", "vaginal_origin", "M_Gen"),
    },
    JuziDreamerAB_Mouth_Anal01 = {
        contact_pair("anal-a", "a", "Juzi_01", "juzi-humanoid", "anal_origin", "M_Anus_Inside"),
        contact_pair("mouth-b", "b", "Juzi_01", "juzi-humanoid", "mouth_origin", "Jaw_master"),
    },
    YanshiDreamerAB_MouthVaginal20251031_Kiana = {
        contact_pair("vaginal-a", "a", "Yanshi_01", "yanshi-humanoid", "vaginal_origin", "M_Gen"),
        contact_pair("mouth-b", "b", "Yanshi_01", "yanshi-humanoid", "mouth_origin", "M_Jaw_master"),
    },
}

local function edition()
    return tostring(Config.game_edition or "")
end

local function enabled_profile(profile)
    return type(profile) == "table"
        and tostring(profile.edition or "") == edition()
        and profile.status == "enabled_for_simulation_validation"
        and (profile.deviceOutput == "enabled" or profile.deviceOutput == "l0_only")
end

local function sylph_profile(hanime_id)
    local profiles = edition() == "demo-ue4.25"
        and (SylphL0Profiles.demo_profiles or {})
        or (SylphL0Profiles.profiles or {})
    local profile = profiles[tostring(hanime_id or "")]
    return enabled_profile(profile) and profile or nil
end

-- Ada's first Playtest release uses the already-exported Hippocamp,
-- Nightgaunt and Shaggai skeletal meshes. Their reference-chain geometry is
-- therefore known; only Ada's new target mesh still awaits one runtime
-- catalog capture. Reuse the species calibration, never a similarly named
-- action curve.
local nonhuman_profile_aliases = {
    -- The August UE 5.7 update added Ada HAnime identities without duplicating
    -- the already verified creature geometry sidecars. Reuse only the same
    -- species and contact category; Ada's target bone is still selected from
    -- her own functional skeleton catalog at runtime.
    ["AdaGhoul_Anal20260520_Prince"] = "GalaGhoul_Anal01",
    ["AM_AdaGhoul_Anal20260630_Prince"] = "GalaGhoul_Anal01",
    ["AM_AdaElderthing_Anal20260522_X"] = "GalaElderthing_Anal01",
    ["AdaGhast_Hand20260702_QingChen"] = "AletGhast_Hand01",
    ["AdaHippocamp_Anal20260424_X"] = "GalaHippocamp_Anal01",
    ["AM_AdaHippocamp_Vaginal20260527_QingChen"] = "GalaHippocamp_Vaginal01",
    ["AdaNightgaunt_Vaginal20260601_Wumiao"] = "GalaNightgaunt_Vaginal01",
    ["AdaShaggai_Vaginal20260530_QingChen"] = "AletDrone_Vaginal01",
    ["AdaTchotcho_Anal20260420_X"] = "GalaTchotcho_Anal01",
    ["AM_AdaTchotcho_Anal20260613_Tango"] = "GalaTchotcho_Anal01",
    ["AdaTchotcho_Anal20260704_Slime"] = "GalaTchotcho_Anal01",
    ["AM_AdaTchotcho_Foot20260629_Wumiao"] = "YanshiTchoTcho_Foot20251221_QingChen",
    ["AdaTchotcho_Vaginal20260406_Kiana"] = "JuziTchotcho_Vaginal01",
}

-- Runtime motion evidence can refine an exact action without changing every
-- action which shares the same species profile.  TchoTcho's shaft is a curved
-- spline: for this Ada action the root tangent (A -> Bn1) splits the same
-- stroke almost equally across L0 and L1.  The root-to-tip chord keeps the
-- penetration stroke on the longitudinal axis while retaining the full chain
-- length and the independently verified humanoid pelvis plane.
local nonhuman_reference_overrides = {
    ["AdaTchotcho_Vaginal20260406_Kiana"] = {
        monsterDirectory = "TchoTcho",
        originBone = "JJ_skin1splineIkBnA",
        directionBone = "JJ_skin1splineIkBn20",
        tipBone = "JJ_skin1splineIkBn20",
        supportBone = "JJ_skin1splineIkBnA",
    },
}

local function nonhuman_profile(hanime_id)
    -- The small Sylph table is an authoritative L0-only correction to the
    -- older generated SR6 sidecar and therefore has precedence.
    local override = sylph_profile(hanime_id)
    if override ~= nil then
        return override
    end
    local profiles = (DirectProfiles.profiles or {})[edition()] or {}
    local requested_id = tostring(hanime_id or "")
    local profile = profiles[nonhuman_profile_aliases[requested_id] or requested_id]
    return enabled_profile(profile) and profile or nil
end

local function female_female_profile(hanime_id)
    local profile = (DirectFFProfiles.profiles or {})[tostring(hanime_id or "")]
    return enabled_profile(profile) and profile or nil
end

local function unique_functional_bones(entry, function_names)
    local functional = entry.functional or {}
    local bones = {}
    local seen = {}
    for _, function_name in ipairs(function_names or {}) do
        local bone_name = functional[function_name]
        if bone_name ~= nil and not seen[bone_name] then
            seen[bone_name] = true
            table.insert(bones, bone_name)
        end
    end
    return bones
end

local function paired_target_bones(entry, identity)
    local pairs = contact_pairs_by_hanime_id[tostring(identity.hanime_id or "")] or {}
    local functional = entry.functional or {}
    local result, seen = {}, {}
    for _, pair in ipairs(pairs) do
        local target = pair.target or {}
        if tostring(target.catalogId or "") == tostring(entry.id or "") then
            -- A pair names both its semantic and the unpacked skeleton bone.
            -- Refuse to infer a bone if the catalog does not agree.
            local semantic_bone = functional[target.semantic]
            local bone = tostring(target.bone or "")
            if semantic_bone == bone and bone ~= "" and not seen[bone] then
                seen[bone] = true
                table.insert(result, bone)
            end
        end
    end
    return result
end

local humanoid_reference_plane_bones = { "M_Hips", "M_Spine1", "L_Thigh", "R_Thigh" }

local function with_humanoid_reference_plane(entry, bones)
    -- Standard Fallen Doll humanoids share these four body landmarks. They
    -- form a stable pelvis plane without paying the cost of a full skeleton
    -- read.  Only the entering/reference participant needs this plane; adding
    -- it to the contact target wastes four reflected bone reads per frame and
    -- does not contribute to the reference geometry. Direct nonhuman meshes
    -- retain their own validated minimal stream.
    if entry.nonhuman_direct == true or entry.motion_role ~= "male" then
        return bones
    end
    local seen = {}
    for _, bone_name in ipairs(bones) do
        seen[bone_name] = true
    end
    for _, bone_name in ipairs(humanoid_reference_plane_bones) do
        if not seen[bone_name] then
            seen[bone_name] = true
            table.insert(bones, bone_name)
        end
    end
    return bones
end

local function default_function_names(entry, identity, preferred)
    if entry.motion_role == "male" then
        return preferred
            and { "primary_origin" }
            or { "primary_origin", "primary_tip", "extended_tip", "support" }
    end
    local hanime_id = tostring(identity.hanime_id or "")
    if target_functions_by_hanime_id[hanime_id] ~= nil then
        return target_functions_by_hanime_id[hanime_id]
    end
    local category = tostring(identity.category or "")
    return preferred
        and (target_functions_by_category[category] or {})
        or (candidate_functions_by_category[category] or {})
end

local function single_target_bone(entry, identity)
    -- The target contributes one contact point.  Prefer the pose/category
    -- selection (for example R_Hand for the three Alet Hand profiles), then
    -- fall back to the first valid category candidate when no preferred table
    -- exists (foot/breast/other).  Candidate selection belongs to the contract,
    -- not to a 50 Hz whole-target skeleton stream.
    local paired = paired_target_bones(entry, identity)
    if #paired > 0 then
        return paired
    end
    local preferred = unique_functional_bones(entry, default_function_names(entry, identity, true))
    if #preferred > 0 then
        return { preferred[1] }
    end
    local candidates = unique_functional_bones(entry, default_function_names(entry, identity, false))
    if #candidates > 0 then
        return { candidates[1] }
    end
    return {}
end


local function target_frames_for_bones(entry, bone_names)
    if tostring(TargetFrames.edition or "") ~= edition() then return {} end
    local allowed = {}
    for _, bone_name in ipairs(bone_names or {}) do allowed[bone_name] = true end
    local result = {}
    for _, frame in ipairs((TargetFrames.catalogs or {})[tostring(entry.id or "")] or {}) do
        if type(frame) == "table" and allowed[tostring(frame.sourceBone or "")] then
            table.insert(result, frame)
        end
    end
    return result
end


local function with_target_frame_bones(bone_names, target_frames)
    local result, seen = {}, {}
    for _, bone_name in ipairs(bone_names or {}) do
        if type(bone_name) == "string" and bone_name ~= "" and not seen[bone_name] then
            seen[bone_name] = true
            table.insert(result, bone_name)
        end
    end
    for _, frame in ipairs(target_frames or {}) do
        for _, field in ipairs({ "originBone", "forwardBone", "leftBone", "rightBone" }) do
            local bone_name = frame[field]
            if type(bone_name) == "string" and bone_name ~= "" and not seen[bone_name] then
                seen[bone_name] = true
                table.insert(result, bone_name)
            end
        end
    end
    return result
end

function Contract.contact_pairs(identity)
    return contact_pairs_by_hanime_id[tostring((identity or {}).hanime_id or "")] or {}
end

local function nonhuman_candidate(profile, entry, hanime_id)
    if edition() == "playtest-ue5" then
        local calibrated = nonhuman_reference_overrides[tostring(hanime_id or "")]
        if type(calibrated) == "table"
            and tostring(calibrated.monsterDirectory or "") == tostring(entry.monster_directory or "")
        then
            return calibrated
        end
    end
    if edition() == "demo-ue4.25" then
        local calibrated = (DemoNonhumanCalibration.profiles or {})[tostring(hanime_id or "")]
        if type(calibrated) == "table"
            and tostring(calibrated.monsterDirectory or "") == tostring(entry.monster_directory or "")
        then
            return calibrated
        end
    end
    for _, candidate in ipairs(profile.referenceCandidates or {}) do
        if tostring(candidate.monsterDirectory or "") == tostring(entry.monster_directory or "") then
            return candidate
        end
    end
    return nil
end

local function reference_geometry(profile, candidate, body_plane)
    local output_axes = candidate.outputAxes or profile.outputAxes or ((profile.axes or {}).enabled)
    if Config.nonhuman_rotation_axes_enabled ~= true then
        local positional_axes = {}
        for _, axis in ipairs(output_axes or {}) do
            if axis == "L0" or axis == "L1" or axis == "L2" then
                table.insert(positional_axes, axis)
            end
        end
        output_axes = positional_axes
    end
    return {
        source = "nonhuman-direct-output-v1",
        deviceOutput = profile.deviceOutput,
        outputAxes = output_axes,
        referenceOriginBone = candidate.originBone,
        referenceDirectionBone = candidate.directionBone,
        referenceTipBone = candidate.tipBone,
        -- VaMToy uses three shaft/contact landmarks plus a four-landmark body
        -- plane.  When that plane exists its centre is also the support point;
        -- do not stream a separate eighth support landmark.
        referenceSupportBone = body_plane and body_plane.centerBone or candidate.supportBone,
        targetSemantic = profile.targetSemantic,
        targetBasis = profile.targetBasis,
        -- Creature size is not a meaningful external-toy scale. Retain this
        -- chain for direction/contact, while Motion Bridge learns the actual
        -- in-animation axial travel for nonhuman L0.
        l0Normalization = "activity_window",
        l0MinMeters = candidate.l0MinMeters,
        l0MaxMeters = candidate.l0MaxMeters,
        l0Inverted = candidate.l0Inverted == true,
        axes = profile.axes,
        axisFallback = candidate.axisFallback,
        referencePlane = body_plane,
    }
end

local function plane_for_entry(entry)
    local planes = BodyPlanes[edition()] or {}
    return planes[tostring(entry.monster_directory or "")]
end

local function append_unique(values, additions)
    local result, seen = {}, {}
    for _, value in ipairs(values or {}) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(result, value)
        end
    end
    for _, value in ipairs(additions or {}) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true
            table.insert(result, value)
        end
    end
    return result
end

local function numeric_chain_names(origin_bone, direction_bone, tip_bone)
    local origin_prefix, origin_index = string.match(tostring(origin_bone or ""), "^(.-)(%d+)$")
    local direction_prefix, direction_index = string.match(tostring(direction_bone or ""), "^(.-)(%d+)$")
    local tip_prefix, tip_index = string.match(tostring(tip_bone or ""), "^(.-)(%d+)$")
    origin_index = tonumber(origin_index)
    direction_index = tonumber(direction_index)
    tip_index = tonumber(tip_index)
    if origin_prefix == nil
        or origin_prefix ~= direction_prefix
        or origin_prefix ~= tip_prefix
        or origin_index == nil
        or direction_index == nil
        or tip_index == nil
    then
        return {}
    end
    local first_index = math.min(origin_index, direction_index, tip_index)
    local last_index = math.max(origin_index, direction_index, tip_index)
    if last_index - first_index + 1 > tonumber(Config.motion_debug_max_bones or 32) then
        return {}
    end
    local result = {}
    for index = first_index, last_index do
        table.insert(result, origin_prefix .. tostring(index))
    end
    return result
end

local function nonhuman_contract(entry, identity)
    local profile = nonhuman_profile(identity.hanime_id)
    if profile == nil then
        return nil, "nonhuman exact HAnime has no enabled motion contract"
    end
    local candidate = nonhuman_candidate(profile, entry, identity.hanime_id)
    if candidate == nil then
        return nil, "nonhuman motion contract has no reference chain for bound mesh"
    end
    local body_plane = plane_for_entry(entry)
    local output_body_plane = body_plane and {
        mode = body_plane.mode,
        -- Keep the same public seven-bone contract as Dreamer/Male. The Mod
        -- resolves this alias to the creature's exact edition-specific centre
        -- bone below; MotionBridge never guesses the source name.
        centerBone = "M_Hips",
        forwardBone = body_plane.forwardBone,
        leftBone = body_plane.leftBone,
        rightBone = body_plane.rightBone,
    } or nil
    local plane_bones = output_body_plane and {
        output_body_plane.centerBone,
        output_body_plane.forwardBone,
        output_body_plane.leftBone,
        output_body_plane.rightBone,
    } or {}
    local stream_bones = { "Penis01", "Penis02", "Penis09" }
    local source_bones = {
        Penis01 = candidate.originBone,
        Penis02 = candidate.directionBone,
        Penis09 = candidate.tipBone,
    }
    if body_plane ~= nil then
        source_bones.M_Hips = body_plane.centerBone
        stream_bones = append_unique(stream_bones, plane_bones)
    else
        -- Retain the legacy support alias only for a profile that has not yet
        -- acquired an edition-specific four-landmark body plane.
        table.insert(stream_bones, "M_Hips")
        source_bones.M_Hips = candidate.supportBone
    end
    return {
        kind = "reference",
        source = "nonhuman-direct-output-v1",
        role = entry.motion_role or entry.role,
        -- Plane landmarks are a four-bone bounded cost, not a whole-skeleton
        -- read.  Keep their native names so Motion Bridge can construct a
        -- profile-specific plane without pretending every creature is human.
        bone_names = stream_bones,
        preferred_bone_names = { "Penis01" },
        source_bones = source_bones,
        debug_bone_names = numeric_chain_names(candidate.originBone, candidate.directionBone, candidate.tipBone),
        direct_geometry = reference_geometry(profile, candidate, output_body_plane),
    }, nil
end

local function female_female_contract(entry, profile)
    if tostring(entry.id or "") == tostring(profile.referenceCatalog or "") then
        local bones = profile.referenceBones or {}
        return {
            kind = "reference",
            source = "female-female-direct-l0-v1",
            role = "male",
            bone_names = { "Penis01", "Penis02", "Penis09", "M_Hips" },
            preferred_bone_names = { "Penis01" },
            source_bones = {
                Penis01 = bones.originBone,
                Penis02 = bones.directionBone,
                Penis09 = bones.tipBone,
                M_Hips = bones.supportBone,
            },
            direct_geometry = {
                source = "female-female-direct-l0-v1",
                referenceOriginBone = bones.originBone,
                referenceDirectionBone = bones.directionBone,
                referenceTipBone = bones.tipBone,
                referenceSupportBone = bones.supportBone,
                targetSemantic = "vaginal_origin",
                targetBasis = { up = "-local_y", right = "+local_z" },
                outputAxes = profile.outputAxes,
            },
        }
    end
    if tostring(entry.id or "") == tostring(profile.targetCatalog or "") then
        local target_bone = profile.targetBone or "M_Gen"
        local target_frames = target_frames_for_bones(entry, { target_bone })
        return {
            kind = "target",
            source = "female-female-direct-l0-v1",
            role = entry.motion_role or entry.role,
            bone_names = with_target_frame_bones({ target_bone }, target_frames),
            preferred_bone_names = { target_bone },
            target_frames = target_frames,
            source_bones = {},
        }
    end
    return nil
end

local function sylph_target_contract(entry, identity)
    local profile = sylph_profile(identity.hanime_id)
    if profile == nil
        or tostring(entry.id or "") ~= tostring(profile.targetCatalog or "")
        or type(profile.targetBone) ~= "string"
        or profile.targetBone == ""
    then
        return nil
    end
    local target_frames = target_frames_for_bones(entry, { profile.targetBone })
    return {
        kind = "target",
        source = "sylph-direct-l0-override-v1",
        role = entry.motion_role or entry.role,
        bone_names = with_target_frame_bones({ profile.targetBone }, target_frames),
        preferred_bone_names = { profile.targetBone },
        target_frames = target_frames,
        source_bones = {},
    }
end

function Contract.reference_directories(identity)
    local profile = nonhuman_profile(identity and identity.hanime_id)
    if profile == nil then
        return {}
    end
    local result = {}
    local seen = {}
    for _, candidate in ipairs(profile.referenceCandidates or {}) do
        local directory = tostring(candidate.monsterDirectory or "")
        if directory ~= "" and not seen[directory] then
            seen[directory] = true
            table.insert(result, directory)
        end
    end
    table.sort(result)
    return result
end

function Contract.resolve(entry, identity)
    if type(entry) ~= "table" then
        return nil, "component is not in the unpacked skeleton catalog"
    end
    identity = type(identity) == "table" and identity or {}

    if entry.nonhuman_direct == true then
        return nonhuman_contract(entry, identity)
    end

    local ff_profile = female_female_profile(identity.hanime_id)
    if ff_profile ~= nil then
        local contract = female_female_contract(entry, ff_profile)
        if contract ~= nil then
            return contract, nil
        end
    end

    local sylph_target = sylph_target_contract(entry, identity)
    if sylph_target ~= nil then
        return sylph_target, nil
    end

    local kind = entry.motion_role == "male" and "reference" or "target"
    local preferred_bones = unique_functional_bones(
        entry,
        default_function_names(entry, identity, true)
    )
    local stream_bones = kind == "reference"
        and with_humanoid_reference_plane(
            entry,
            unique_functional_bones(entry, default_function_names(entry, identity, false))
        )
        or single_target_bone(entry, identity)
    local target_frames = kind == "target" and target_frames_for_bones(entry, stream_bones) or {}
    if kind == "target" then
        stream_bones = with_target_frame_bones(stream_bones, target_frames)
    end
    if kind == "target" then
        preferred_bones = single_target_bone(entry, identity)
    end

    return {
        kind = kind,
        source = "functional-skeleton-catalog-v1",
        role = entry.motion_role or entry.role,
        bone_names = stream_bones,
        preferred_bone_names = preferred_bones,
        target_frames = target_frames,
        source_bones = {},
    }, nil
end

return Contract
