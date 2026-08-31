-- Static runtime component identities read from the unpacked Blueprint export
-- table in demo-ue425-package-index.txt.  These are Blueprint class/component
-- identities, not inferred mesh-name aliases.  Only the animated primary body
-- component is listed; opacity/helper components are deliberately excluded.
return {
    ["demo-ue4.25"] = {
        ["Byakhee"] = {
            ownerClass = "CharacterByakhee_C",
            templateName = "Mesh_Byakhee_GEN_VARIABLE",
            componentName = "Mesh_Byakhee",
        },
        ["DeepOne"] = {
            ownerClass = "CharacterDeepOne_C",
            templateName = "Mesh_DeepOne_GEN_VARIABLE",
            componentName = "Mesh_DeepOne",
        },
        ["ElderThingSupplemental"] = {
            ownerClass = "CharacterElderThing_C",
            templateName = "Mesh_ElderThing_GEN_VARIABLE",
            componentName = "Mesh_ElderThing",
        },
        ["Ghast"] = {
            ownerClass = "CharacterGhast_C",
            templateName = "Mesh_Ghast_GEN_VARIABLE",
            componentName = "Mesh_Ghast",
        },
        ["Hound"] = {
            ownerClass = "CharacterHound_C",
            templateName = "Mesh_Hound_GEN_VARIABLE",
            componentName = "Mesh_Hound",
        },
        ["Lloigor"] = {
            ownerClass = "CharacterLloigor_C",
            templateName = "Mesh_Lloigor_GEN_VARIABLE",
            componentName = "Mesh_Lloigor",
        },
        -- Demo uses its generic Drone actor for the Shaggai animation family.
        ["ShaggaiSupplemental"] = {
            ownerClass = "CharacterDrone_C",
            templateName = "Mesh_Drone_GEN_VARIABLE",
            componentName = "Mesh_Drone",
        },
        ["SkorpiosSupplemental"] = {
            ownerClass = "CharacterSkorpion_C",
            templateName = "Mesh_Skorpios_Crawler_GEN_VARIABLE",
            componentName = "Mesh_Skorpios_Crawler",
        },
        ["Sylph"] = {
            ownerClass = "CharacterSylph_C",
            templateName = "Mesh_Sylph_GEN_VARIABLE",
            componentName = "Mesh_Sylph",
        },
        ["Tentacle"] = {
            ownerClass = "CharacterTentacle_C",
            templateName = "Mesh_Tentacle_GEN_VARIABLE",
            componentName = "Mesh_Tentacle",
        },
    },
}
