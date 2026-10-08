-- Relay: when player A reports "I see player B (targetServerId)",
-- forward that to player B so they know they're being watched.
-- The client uses this for reciprocal visibility (seenByServerIds).

RegisterNetEvent("fow:setSeeing", function(targetServerId, seeing)
    local watcherServerId = source
    TriggerClientEvent("fow:seenBy", targetServerId, watcherServerId, seeing)
end)
