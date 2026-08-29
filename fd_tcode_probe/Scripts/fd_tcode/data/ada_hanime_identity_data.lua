-- Ada Playtest HAnime allowlist.
--
-- Derived from the installed Playtest TableHAnim in
-- D:\zhifu\Desktop\data\mmd\extracted on 2026-08-29.  Every entry is a
-- TableHAnim family member; idle, expression, drink, dance, and ordinary
-- interaction Montages are intentionally excluded.

local Catalog = { by_montage = {}, by_family = {} }

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function add_asset(hanime_id, category, participant_tag, asset, phase)
    Catalog.by_montage[normalized(asset)] = {
        asset = asset,
        asset_paths = {},
        catalog_refs = { "Ada/TableHAnim/extracted-2026-08-29" },
        category = category,
        evidence = "table_hanim_exact_all_participant_montages",
        hanime_id = hanime_id,
        participant_tag = participant_tag,
        phase = phase,
    }
end

local function add_family(hanime_id, category, participant_tags, montage_owners)
    Catalog.by_family[hanime_id] = {
        hanime_id = hanime_id,
        category = category,
        participant_tags = participant_tags,
        catalog_refs = { "Ada/TableHAnim/extracted-2026-08-29" },
    }
    for _, owner in ipairs(montage_owners) do
        -- owner[2] is the exact suffix from TableHAnim, including scene rigs.
        -- A scene rig has no catalog role and therefore can establish identity
        -- only; it can never be selected as a character participant.
        local montage = owner[3] or (hanime_id .. owner[2] .. "_Montage")
        add_asset(hanime_id, category, owner[1], montage, "normal")
        add_asset(hanime_id, category, owner[1], montage .. "_MAX", "max")
        add_asset(hanime_id, category, owner[1], montage .. "_MIN", "min")
    end
end

add_family("AM_AdaGhastTchotcho_Vaginal20250512_BETAROB", "other",
    { "Ada_01", "Ghast_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "Ghast_01", "_Ghast_01" },
        { "TchoTcho_01", "_TchoTcho_01" },
    })
add_family("AM_AdaElderthing_Anal20260522_X", "anal",
    { "Ada_01", "ElderThing_01" }, {
        { "Ada_01", "_Ada_01" }, { "ElderThing_01", "_ElderThing_01" },
    })
add_family("AdaGhast_Hand20260702_QingChen", "hand",
    { "Ada_01", "Ghast_01" }, {
        { "Ada_01", "_Ada_01" }, { "Ghast_01", "_Ghast_01" },
    })
add_family("AdaGhoul_Anal20260520_Prince", "anal",
    { "Ada_01", "Ghoul_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Ghoul_A_01", "_Ghoul_A_01" },
    })
add_family("AM_AdaGhoul_Anal20260630_Prince", "anal",
    { "Ada_01", "Ghoul_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Ghoul_A_01", "_Ghoul_A_01" },
    })
add_family("AdaHippocamp_Anal20260424_X", "anal",
    { "Ada_01", "Hippocamp_01" }, {
        { "Ada_01", "_Ada_01" }, { "Hippocamp_01", "_Hippocamp_01" },
        { "scene_rig", "_WorkshopCrate2_01" },
    })
add_family("AM_AdaHippocamp_Vaginal20260527_QingChen", "vaginal",
    { "Ada_01", "Hippocamp_01" }, {
        { "Ada_01", "_Ada_01" }, { "Hippocamp_01", "_Hippocamp_01" },
    })
add_family("AM_AdaDreamer_Boob20260706_Slime", "breast",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" },
        { "Dreamer_A_01", "_Dreamer_A_01", "AdaDreamer_Boob20260706_Slime_Dreamer_A_01_Montage" },
    })
add_family("AdaDreamer_Foot20260601_Wumiao", "foot",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Dreamer_A_01", "_Dreamer_A_01" },
    })
-- The TableHAnim path is Male/Mouth01; the historical family name is not
-- used as a category guess.
add_family("AdaDreamer_Vaginal20260613_00", "mouth",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Dreamer_A_01", "_Dreamer_A_01" },
    })
add_family("AdaDreamer_Vaginal20260516_Slime", "vaginal",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Dreamer_A_01", "_Dreamer_A_01" },
    })
add_family("AM_AdaDreamer_Vaginal20260701_Kame", "vaginal",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Dreamer_A_01", "_Dreamer_A_01" },
    })
add_family("AM_AdaDramer_FaceVaginal20260616_Kiana", "other",
    { "Ada_01", "Dreamer_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Dreamer_A_01", "_Dreamer_A_01" },
    })
add_family("AdaNightgaunt_Vaginal20260601_Wumiao", "vaginal",
    { "Ada_01", "Nightgaunt_01" }, {
        { "Ada_01", "_Ada_01" }, { "Nightgaunt_01", "_Nightgaunt_01" },
        { "scene_rig", "_Chair_Zaha_04MIN" },
    })
add_family("AdaShaggai_Vaginal20260530_QingChen", "vaginal",
    { "Ada_01", "Shaggai_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "Shaggai_A_01", "_Shaggai_A_01" },
    })
add_family("AM_AdaDoubledildoA_Vaginal20260708_X", "vaginal",
    { "Ada_01", "DoubleDildo_A_01" }, {
        { "Ada_01", "_Ada_01" }, { "DoubleDildo_A_01", "_DoubleDildo_A_01" },
    })
add_family("Ada_MasturbateClub20270801_Tango", "hand", { "Ada_01" }, {
    { "Ada_01", "_Ada_01" },
})
add_family("AdaTalon_Vaginal20260605_QingChen", "vaginal",
    { "Ada_01", "Talon_01" }, {
        { "Ada_01", "_Ada_01" }, { "Talon_01", "_Talon_01" },
        { "scene_rig", "_ClubPillow_01" },
    })
add_family("AdaTchotcho_Anal20260420_X", "anal",
    { "Ada_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "TchoTcho_01", "_TchoTcho_01" },
    })
add_family("AM_AdaTchotcho_Anal20260613_Tango", "anal",
    { "Ada_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "TchoTcho_01", "_TchoTcho_01" },
    })
add_family("AdaTchotcho_Anal20260704_Slime", "anal",
    { "Ada_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "TchoTcho_01", "_TchoTcho_01" },
    })
add_family("AM_AdaTchotcho_Foot20260629_Wumiao", "foot",
    { "Ada_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "TchoTcho_01", "_TchoTcho_01" },
    })
add_family("AdaTchotcho_Vaginal20260406_Kiana", "vaginal",
    { "Ada_01", "TchoTcho_01" }, {
        { "Ada_01", "_Ada_01" }, { "TchoTcho_01", "_TchoTcho_01" },
    })

return Catalog
