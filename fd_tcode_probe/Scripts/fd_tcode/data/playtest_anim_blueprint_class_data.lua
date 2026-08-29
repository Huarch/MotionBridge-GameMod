-- Generated from the UE 5.7 Playtest full extraction on 2026-08-29.
-- Source query: Characters/**/AMBP_*.uasset. Runtime code still requires an
-- exact skeleton-catalog match, so furniture/prop AnimBPs cannot become a
-- participant merely by appearing in this inventory.

local names = {
    "AMBP_ADA_C",
    "AMBP_Alet_HAnim_C",
    "AMBP_Anya_H_Anim_C",
    "AMBP_Bar_piano_Bench_C",
    "AMBP_Bar_Stool_C",
    "AMBP_Box1_C",
    "AMBP_BOX2_C",
    "AMBP_Box3_C",
    "AMBP_Box4_C",
    "AMBP_Byakhee_C",
    "AMBP_Celia_C",
    "AMBP_Chair_C",
    "AMBP_ChairZaha_C",
    "AMBP_ControlTable_6_C",
    "AMBP_DeepOne_C",
    "AMBP_DoubleDildo_C",
    "AMBP_DoubleDildo_02_C",
    "AMBP_Drone_C",
    "AMBP_ElderThing_C",
    "AMBP_Elizabeth_C",
    "AMBP_Erika_C",
    "AMBP_Feetcuff_C",
    "AMBP_Gala_C",
    "AMBP_Ghast_C",
    "AMBP_Ghoul_C",
    "AMBP_Gug_C",
    "AMBP_Handcuff_C",
    "AMBP_Handcuff2_C",
    "AMBP_Hippocamp_C",
    "AMBP_Hole_Box_C",
    "AMBP_Hound_HAnim_C",
    "AMBP_Juzi_C",
    "AMBP_Lloigor_C",
    "AMBP_Male_C",
    "AMBP_Migo_warrior_C",
    "AMBP_nightgaunt_C",
    "AMBP_Op_bed_C",
    "AMBP_Pillow_C",
    "AMBP_Saaitii_C",
    "AMBP_Shantak_C",
    "AMBP_Skorpios_C",
    "AMBP_Sylph_C",
    "AMBP_Talon_C",
    "AMBP_TchoTcho_C",
    "AMBP_Tentacle_C",
    "AMBP_Wineglass3_C",
    "AMBP_WorkshopArm_C",
    "AMBP_WorkshopArm2_C",
    "AMBP_Yanshi_C",
    "AMBP_Yanshi_Mech_C",
}

local by_class = {}
for _, name in ipairs(names) do
    by_class[name] = true
end

return {
    edition = "playtest-ue5",
    engine = "UE5.7",
    source = "unpacked Characters/**/AMBP_*.uasset",
    names = names,
    by_class = by_class,
}
