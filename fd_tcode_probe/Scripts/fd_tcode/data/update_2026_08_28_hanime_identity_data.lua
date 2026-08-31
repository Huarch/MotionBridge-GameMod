-- Incremental HAnime identities from the Playtest update announced on
-- 2026-08-28. Every entry below is an exact Montage filename listed from the
-- installed Pak25/Pak26 archives; idle and expression Montages are excluded.

local Catalog = { by_montage = {}, by_family = {} }

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function add_asset(hanime_id, category, participant_tag, asset, phase)
    Catalog.by_montage[normalized(asset)] = {
        asset = asset,
        asset_paths = {},
        catalog_refs = { "Playtest/update-2026-08-28" },
        category = category,
        evidence = "pak25_pak26_exact_montage_index",
        hanime_id = hanime_id,
        participant_tag = participant_tag,
        phase = phase,
    }
end

local function add_family(hanime_id, category, participant_tags, assets)
    Catalog.by_family[hanime_id] = {
        hanime_id = hanime_id,
        category = category,
        participant_tags = participant_tags,
        catalog_refs = { "Playtest/update-2026-08-28" },
    }
    for _, asset in ipairs(assets) do
        add_asset(hanime_id, category, "scene_rig", asset, "normal")
        add_asset(hanime_id, category, "scene_rig", asset .. "_MAX", "max")
        add_asset(hanime_id, category, "scene_rig", asset .. "_MIN", "min")
    end
end

add_family("AM_GalaTalon_Mouth20251009_00", "mouth", { "Galatea_01", "Talon_01" }, {
    "AM_GalaTalon_Mouth20251009_00_ClubPillow_01_Montage",
})
add_family("GalaShantak_Vaginal20260312_tango", "vaginal", { "Galatea_01", "Shantak_01" }, {
    "GalaShantak_Vaginal20260312_tango_Shantak_01_Montage",
})
add_family("GalaSylph_Vaginal20260318_Tango", "vaginal", { "Galatea_01", "Sylph_01" }, {
    "GalaSylph_Vaginal20260318_Tango_SylphVibrator_01_Montage",
    "GalaSylph_Vaginal20260318_Tango_WorkshopCrate_01_Montage",
})
add_family("TalonDreamer_Foot01", "foot", { "Talon_01", "Dreamer_A_01" }, {
    "TalonDreamer_Foot01_Feetcuffs_A_01_Montage",
})
add_family("TalonDreamer_Mouth02", "mouth", { "Talon_01", "Dreamer_A_01" }, {
    "TalonDreamer_Mouth02_Handcuffs_A_01_Montage",
})
add_family("talonDreamer_Vaginal02", "vaginal", { "Talon_01", "Dreamer_A_01" }, {
    "talonDreamer_Vaginal02_Handcuffs_A_01_Montage",
})
add_family("TalonDremaerTchotcho_VaginalAnal01", "other", { "Talon_01", "Dreamer_A_01", "TchoTcho_A_01" }, {
    "TalonDremaerTchotcho_VaginalAnal01_Handcuffs_B_01_Montage",
})
add_family("TalonElderThing_Anal01", "anal", { "Talon_01", "ElderThing_01" }, {
    "TalonElderThing_Anal01_Chair_01_Montage",
})
add_family("TalonGhastShaggai_VaginalMouth01", "other", { "Talon_01", "Ghast_01", "Shaggai_A_01" }, {
    "TalonGhastShaggai_VaginalMouth01_Shaggai_A_01_Montage",
})
add_family("TalonGhoul_A_Anal01", "anal", { "Talon_01", "Ghoul_01" }, {
    "TalonGhoul_A_Anal01_Feetcuffs_A_01_Montage",
})
add_family("TalonGhoul_Mouth01", "mouth", { "Talon_01", "Ghoul_01" }, {
    "TalonGhoul_Mouth01_Chair_01_Montage",
})
add_family("TalonHippocamp_Vaginal01", "vaginal", { "Talon_01", "Hippocamp_01" }, {
    "TalonHippocamp_Vaginal01_Hippocamp_01_Montage",
})
add_family("TalonHippocampElderthing_VaginalAnal01", "other", { "Talon_01", "Hippocamp_01", "ElderThing_01" }, {
    "TalonHippocampElderthing_VaginalAnal01_Hippocamp_01_Montage",
})
add_family("TalonShaggai_Breast01", "breast", { "Talon_01", "Shaggai_A_01" }, {
    "TalonShaggai_Breast01_Shaggai_A_01_Montage",
})
add_family("TalonShaggaiGug_AnalMouth01", "other", { "Talon_01", "Shaggai_A_01", "Gug_01" }, {
    "TalonShaggaiGug_AnalMouth01_Shaggai_A_01_Montage",
})
add_family("TalonShaggaiSaaitii_VaginalAnal01", "other", { "Talon_01", "Shaggai_A_01", "Saaitii_01" }, {
    "TalonShaggaiSaaitii_VaginalAnal01_Shaggai_A_01_Montage",
})
add_family("TalonShantak_Vaginal20260303_Kame", "vaginal", { "Talon_01", "Shantak_01" }, {
    "TalonShantak_Vaginal20260303_Kame_Shantak_01_Montage",
})
add_family("TalonSylph_Vaginal01", "vaginal", { "Talon_01", "Sylph_01" }, {
    "TalonSylph_Vaginal01_Mesh_BarChair_01_Montage",
    "TalonSylph_Vaginal01_SylphDildo_01_Montage",
})
add_family("TalonTchotcho_Anal01", "anal", { "Talon_01", "TchoTcho_A_01" }, {
    "TalonTchotcho_Anal01_Handcuffs_A_01_Montage",
})
add_family("TalonTchotcho_Anal02", "anal", { "Talon_01", "TchoTcho_A_01" }, {
    "TalonTchotcho_Anal02_Pillow_rig_01_Montage",
})
add_family("TalonTchotchoAB_MouthAnal01", "other", { "Talon_01", "TchoTcho_A_01", "TchoTcho_B_01" }, {
    "TalonTchotchoAB_MouthAnal01_Chair_01_Montage",
})
add_family("TalonTchotchoHound_HandAnal01", "other", { "Talon_01", "TchoTcho_A_01", "Hound_01" }, {
    "TalonTchotchoHound_HandAnal01_Chair_01_Montage",
})
add_family("YanshiDoubledildoA_Vaginal20260330_X", "vaginal", { "Yanshi_01", "DoubleDildo_A_01" }, {
    "YanshiDoubledildoA_Vaginal20260330_X_DoubleDildo_A_01_Montage",
})

return Catalog
