-- Playtest development link marker.  The installed Playtest Mod's Scripts
-- directory is a junction to this checkout, so it must declare its edition
-- here; Demo copies carry their own local markers.
return {
    schema_version = 1,
    edition = "playtest-ue5",
    source = "workspace-sync:Playtest-junction",
}
