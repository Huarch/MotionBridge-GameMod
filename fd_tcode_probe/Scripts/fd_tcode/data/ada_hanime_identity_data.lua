-- Ada Playtest HAnime allowlist.
--
-- Generated from the current Playtest Pak25/Pak26 package index on
-- 2026-08-28.  Keep this separate from the historical generated catalog so
-- an incremental game update cannot accidentally broaden the HAnime gate.

local Catalog = {
    by_montage = {},
    by_family = {},
}

local function normalized(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function add_family(hanime_id, category, partner_tag, assets)
    Catalog.by_family[hanime_id] = {
        hanime_id = hanime_id,
        category = category,
        participant_tags = { "Ada_01", partner_tag },
        catalog_refs = { "Ada/update-2026-08-28" },
    }
    for _, entry in ipairs(assets) do
        local asset, phase = entry[1], entry[2]
        Catalog.by_montage[normalized(asset)] = {
            asset = asset,
            asset_paths = {},
            catalog_refs = { "Ada/update-2026-08-28" },
            category = category,
            evidence = "pak25_pak26_exact_montage_index",
            hanime_id = hanime_id,
            participant_tag = partner_tag,
            phase = phase,
        }
    end
end

local function phases(normal, maximum, minimum)
    return {
        { normal, "normal" },
        { maximum, "max" },
        { minimum, "min" },
    }
end

add_family(
    "AdaHippocamp_Anal20260424_X", "anal", "Hippocamp_01",
    phases(
        "AdaHippocamp_Anal20260424_X_Hippocamp_01_Montage",
        "AdaHippocamp_Anal20260424_X_Hippocamp_01_Montage_MAX",
        "AdaHippocamp_Anal20260424_X_Hippocamp_01_Montage_MIN"
    )
)
add_family(
    "AM_AdaHippocamp_Vaginal20260527_QingChen", "vaginal", "Hippocamp_01",
    phases(
        "AM_AdaHippocamp_Vaginal20260527_QingChen_Hippocamp_01_Montage",
        "AM_AdaHippocamp_Vaginal20260527_QingChen_Hippocamp_01_Montage_MAX",
        "AM_AdaHippocamp_Vaginal20260527_QingChen_Hippocamp_01_Montage_MIN"
    )
)
add_family(
    "AdaNightgaunt_Vaginal20260601_Wumiao", "vaginal", "Nightgaunt_01",
    phases(
        "AdaNightgaunt_Vaginal20260601_Wumiao_Chair_Zaha_04MIN_Montage",
        "AdaNightgaunt_Vaginal20260601_Wumiao_Chair_Zaha_04MIN_Montage_MAX",
        "AdaNightgaunt_Vaginal20260601_Wumiao_Chair_Zaha_04MIN_Montage_MIN"
    )
)
add_family(
    "AdaShaggai_Vaginal20260530_QingChen", "vaginal", "Shaggai_A_01",
    phases(
        "AdaShaggai_Vaginal20260530_QingChen_Shaggai_A_01_Montage",
        "AdaShaggai_Vaginal20260530_QingChen_Shaggai_A_01_Montage_MAX",
        "AdaShaggai_Vaginal20260530_QingChen_Shaggai_A_01_Montage_MIN"
    )
)
add_family(
    "AdaTalon_Vaginal20260605_QingChen", "vaginal", "Talon_01",
    phases(
        "AdaTalon_Vaginal20260605_QingChen_ClubPillow_01_Montage",
        "AdaTalon_Vaginal20260605_QingChen_ClubPillow_01_Montage_MAX",
        "AdaTalon_Vaginal20260605_QingChen_ClubPillow_01_Montage_MIN"
    )
)
add_family(
    "AM_AdaDoubledildoA_Vaginal20260708_X", "vaginal", "DoubleDildo_A_01",
    phases(
        "AM_AdaDoubledildoA_Vaginal20260708_X_DoubleDildo_A_01_Montage",
        "AM_AdaDoubledildoA_Vaginal20260708_X_DoubleDildo_A_01_Montage_MAX",
        "AM_AdaDoubledildoA_Vaginal20260708_X_DoubleDildo_A_01_Montage_MIN"
    )
)

return Catalog
