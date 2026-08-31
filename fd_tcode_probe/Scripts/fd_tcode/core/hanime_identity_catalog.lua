-- Merge edition-specific generated identity tables without changing either
-- source artifact. Duplicate Montage keys are accepted only when both builds
-- identify the same HAnime family.

local Playtest = require("fd_tcode.data.hanime_identity_data")
local Demo = require("fd_tcode.data.demo_hanime_identity_data")

local Catalog = {
    by_montage = {},
    by_family = {},
    conflicts = {},
}

local function merge(source, edition)
    for key, identity in pairs(source.by_montage or {}) do
        local existing = Catalog.by_montage[key]
        if existing == nil then
            Catalog.by_montage[key] = identity
        elseif tostring(existing.hanime_id) ~= tostring(identity.hanime_id) then
            table.insert(Catalog.conflicts, {
                key = key,
                edition = edition,
                existing = existing.hanime_id,
                incoming = identity.hanime_id,
            })
        end
    end

    -- Family metadata can contain participant roles proven by TableHAnim
    -- even when a broken table row omits one participant's Montage. Keep it
    -- alongside the exact Montage whitelist so the runtime can bind all
    -- participants without treating AnimSequences as activation signals.
    for hanime_id, metadata in pairs(source.by_family or {}) do
        local family = Catalog.by_family[hanime_id]
        if family == nil then
            family = {
                hanime_id = metadata.hanime_id or hanime_id,
                category = metadata.category,
                participant_tags = {},
                catalog_refs = {},
            }
            Catalog.by_family[hanime_id] = family
        elseif family.category ~= nil
            and metadata.category ~= nil
            and tostring(family.category) ~= tostring(metadata.category)
        then
            table.insert(Catalog.conflicts, {
                key = hanime_id,
                edition = edition,
                existing = family.category,
                incoming = metadata.category,
            })
        end

        local function append_unique(field, values)
            local seen = {}
            for _, value in ipairs(family[field]) do
                seen[tostring(value)] = true
            end
            for _, value in ipairs(values or {}) do
                local key = tostring(value)
                if not seen[key] then
                    seen[key] = true
                    table.insert(family[field], value)
                end
            end
        end

        append_unique("participant_tags", metadata.participant_tags)
        append_unique("catalog_refs", metadata.catalog_refs)
    end
end

merge(Playtest, "playtest")
merge(Demo, "demo")

return Catalog
