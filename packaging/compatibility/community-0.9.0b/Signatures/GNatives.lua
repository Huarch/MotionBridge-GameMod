-- Fallen Doll Community 0.9.0b, tested build 7313, UE 5.7.4.
-- GNatives LEA in UObject::SkipFunction; table RVA 0xAB0C6D0.
-- The function indexes the resolved table by the bytecode token and calls it.
function Register()
    return "4C 8D 2D ?? ?? ?? ?? 0F 1F 40 00 66 66 0F 1F 84 00 00 00 00 00 4C 89 63 38 4C 89 63 40 8B 46 38"
end

function OnMatchFound(MatchAddress)
    return MatchAddress + 7 + DerefToInt32(MatchAddress + 3)
end
