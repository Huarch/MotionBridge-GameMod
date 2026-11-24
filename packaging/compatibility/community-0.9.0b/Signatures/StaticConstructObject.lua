-- Fallen Doll Community 0.9.0b, tested build 7313, UE 5.7.4.
-- StaticConstructObject_Internal: RVA 0x15F7910.
-- Verified against NewObject callers and the class flags test (0x10000080).
function Register()
    return "48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 41 54 41 55 41 56 41 57 48 8D AC 24 60 FE FF FF 48 81 EC A0 02 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 90 01 00 00 4C 8B 31 33 DB 4C 8B 61 08 48 8B F9 44 8B 79 18 48 8B 71 28 41 F7 86 D4 00 00 00 80 00 00 10"
end

function OnMatchFound(MatchAddress)
    return MatchAddress
end
