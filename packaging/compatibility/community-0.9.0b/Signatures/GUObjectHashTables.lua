-- Fallen Doll Community 0.9.0b, tested build 7313, UE 5.7.4.
-- Call to FUObjectHashTables::Get at RVA 0x15EEC14; target RVA 0x15E8630.
function Register()
    return "CC 48 83 EC 28 E8 ?? ?? ?? ?? 48 8B C8 48 83 C4 28 48 FF"
end

function OnMatchFound(MatchAddress)
    local DisplacementAddress = MatchAddress + 6
    return DisplacementAddress + 4 + DerefToInt32(DisplacementAddress)
end
