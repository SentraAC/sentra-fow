-- ============================================
--  CONFIG
-- ============================================

local OFFSET_BASE    = 1.5
local OFFSET_MAX     = 5.0
local VEL_MAX        = 7.0

local RAYCAST_MARGIN = 0.5

local DISABLE_FOW_IN_INTERIORS = true

local REAL_Z_THRESHOLD = 0.50

local SHARED_VALUES_INTERVAL = 10

local VISIBLE_INTERVAL = 200

local SCAN_INTERVAL = 1000

local INTERIOR_SCAN_INTERVAL = 1000

local HIDDEN_WAIT_DEFAULT = 32
local HIDDEN_WAIT_TIERS = {
    { distance = 50,  wait = 64 },
    { distance = 100, wait = 128 },
    { distance = 150, wait = 256 },
}

local SIDES = {
    { lx =  1.0, ly = 0.0 },
    { lx = -1.0, ly = 0.0 },
    { lx =  0.0, ly = 1.0 },
    { lx =  0.0, ly =-1.0 },
}

local SIDES_MAX_DISTANCE = 100

local SEEN_RELEASE_GRACE  = 500
local SEEN_FLUSH_INTERVAL = 100

local OFFSCREEN_WAIT = 16

local TRANSPARENT_MATERIALS = {
    [937503243]   = true, -- GlassShootThrough
    [244521486]   = true, -- GlassBulletproof
    [1500272081]  = true, -- GlassOpaque
    [-1619794068] = true, -- Perspex
    [1247281098]  = true, -- CarGlassWeak
    [602884284]   = true, -- CarGlassMedium
    [1070994698]  = true, -- CarGlassStrong
    [-1721915930] = true, -- CarGlassBulletproof
    [513061559]   = true, -- CarGlassOpaque
    [2130571536]  = true, -- CarSofttopClear
    [-1859721013] = true, -- PlasticClear
    [772722531]   = true, -- PlasticHollowClear
    [-1338473170] = true, -- PlasticHighDensityClear
    [1501078253]  = true, -- EmissiveGlass
    [1429989756]  = true, -- Tvscreen
    [673696729]   = true, -- SlattedBlinds
    [762193613]   = true, -- MetalChainlinkSmall
    [125958708]   = true, -- MetalChainlinkLarge
    [-426118011]  = true, -- MetalGrille
}

-- ============================================
--  On script start, reset conceal state for every active
--  player. Prevents someone staying hidden from a leftover
--  conceal call if the script was restarted while they were
--  concealed. This runs once because the whole file re-runs
--  on every resource start/restart.
-- ============================================
CreateThread(function()
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if DoesEntityExist(ped) then
            NetworkConcealEntity(ped, false)
        end
    end
end)

local function localToWorld(lx, ly, heading)
    local rad = math.rad(-heading)
    local c, s = math.cos(rad), math.sin(rad)
    return lx * c - ly * s, lx * s + ly * c
end

local function isVisible(camPos, target, ignorePed)
    local realDist  = #(camPos - target)
    local ray       = StartShapeTestRay(camPos.x, camPos.y, camPos.z, target.x, target.y, target.z, 1, ignorePed, 0)
    local res, hit, hitPos, surfaceNormal, materialHash, entityHit = GetShapeTestResultIncludingMaterial(ray)
    if res ~= 2 or not hit then return true end
    if TRANSPARENT_MATERIALS[materialHash] then return true end

    if #(camPos - hitPos) >= (realDist - RAYCAST_MARGIN) then
        return true
    end

    return false
end

local isPointOnScreen = function(worldPos)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
    if not onScreen then return false end
    return screenX >= 0.0 and screenX <= 1.0 and screenY >= 0.0 and screenY <= 1.0
end

local hiddenWaitFor = function(distance2D)
    local waitTime = HIDDEN_WAIT_DEFAULT
    for _, tier in ipairs(HIDDEN_WAIT_TIERS) do
        if distance2D > tier.distance then
            waitTime = tier.wait
        end
    end
    return waitTime
end

-- ============================================
--  Publish our real Z only when it changes
-- ============================================
CreateThread(function()
    local lastZ = nil
    while true do
        Wait(100)
        local z = GetEntityCoords(PlayerPedId(), true).z
        if not lastZ or math.abs(z - lastZ) > REAL_Z_THRESHOLD then
            lastZ = z
            LocalPlayer.state:set("realZ", z, true)
        end
    end
end)

local function localPlayerIdFromStateBag(bagName)
    local playerId = GetPlayerFromStateBagName(bagName)
    if not playerId or playerId == -1 or playerId == 0 then return nil end

    return playerId
end

local sharedPlayerRealZ = {}

AddStateBagChangeHandler("realZ", "", function(bagName, _key, value)
    local playerId = localPlayerIdFromStateBag(bagName)
    if not playerId then return end

    sharedPlayerRealZ[playerId] = value
end)

-- ============================================
--  Shared values: camPos and local interior.
--  Updated once every SHARED_VALUES_INTERVAL ms instead of
--  every ped thread calling the natives on its own.
-- ============================================
local sharedCamPos        = vector3(0.0, 0.0, 0.0)
local sharedLocalInterior = 0
local sharedLocalCoords   = vector3(0.0, 0.0, 0.0)

CreateThread(function()
    while true do
        Wait(SHARED_VALUES_INTERVAL)
        local myPed = PlayerPedId()
        sharedCamPos        = GetGameplayCamCoord()
        sharedLocalInterior = GetInteriorFromEntity(myPed)
        sharedLocalCoords   = GetEntityCoords(myPed)
    end
end)

-- ============================================
--  Reciprocal visibility (event based)
-- ============================================
local seenByServerIds = {}
local reportedSeeing  = {}
local pendingUnsee    = {}

RegisterNetEvent("fow:seenBy", function(watcherServerId, seeing)
    watcherServerId = tonumber(watcherServerId)
    if not watcherServerId then return end

    if seeing then
        seenByServerIds[watcherServerId] = true
    else
        seenByServerIds[watcherServerId] = nil
    end
end)

local function reportSeeing(targetServerId, seeing)
    if not targetServerId or targetServerId <= 0 then return end

    if seeing then
        pendingUnsee[targetServerId] = nil
        if not reportedSeeing[targetServerId] then
            reportedSeeing[targetServerId] = true
            TriggerServerEvent("fow:setSeeing", targetServerId, true)
        end
    else
        if reportedSeeing[targetServerId] and not pendingUnsee[targetServerId] then
            pendingUnsee[targetServerId] = GetGameTimer() + SEEN_RELEASE_GRACE
        end
    end
end

CreateThread(function()
    while true do
        Wait(SEEN_FLUSH_INTERVAL)

        local now = GetGameTimer()
        for targetServerId, releaseAt in pairs(pendingUnsee) do
            if now >= releaseAt then
                pendingUnsee[targetServerId]   = nil
                reportedSeeing[targetServerId] = nil
                TriggerServerEvent("fow:setSeeing", targetServerId, false)
            end
        end
    end
end)

local activeThreads = {}

local sharedPlayerInteriors = {}

CreateThread(function()
    while true do
        Wait(INTERIOR_SCAN_INTERVAL)

        for _, playerId in ipairs(GetActivePlayers()) do
            if playerId ~= PlayerId() then
                local ped = GetPlayerPed(playerId)
                if DoesEntityExist(ped) then
                    local interior = GetInteriorFromEntity(ped)
                    if interior ~= 0 then
                        sharedPlayerInteriors[playerId] = interior
                    else
                        sharedPlayerInteriors[playerId] = nil
                    end
                end
            end
        end
    end
end)

-- ============================================
--  Dedicated thread per ped: lives while the ped exists
-- ============================================
local function startPlayerThread(playerId, ped)
    activeThreads[playerId] = true

    CreateThread(function()
        local hidden = false
        local lastDistance2D = 0
        local targetServerId = GetPlayerServerId(playerId)
        local offScreenReveal = false

        while DoesEntityExist(ped) do
            local waitTime = VISIBLE_INTERVAL
            if hidden then
                waitTime = hiddenWaitFor(lastDistance2D)
            elseif offScreenReveal then
                waitTime = OFFSCREEN_WAIT
            end
            Wait(waitTime)

            if not DoesEntityExist(ped) then break end

            offScreenReveal = false

            local coords = GetEntityCoords(ped)

            do
                local dx = sharedLocalCoords.x - coords.x
                local dy = sharedLocalCoords.y - coords.y
                lastDistance2D = math.sqrt(dx * dx + dy * dy)
            end

            local realZ = sharedPlayerRealZ[playerId]
            if not realZ then
                reportSeeing(targetServerId, true)
                if hidden then
                    hidden = false
                    NetworkConcealEntity(ped, false)
                end
                goto nextTick
            end

            if not isPointOnScreen(vector3(coords.x, coords.y, realZ)) then
                reportSeeing(targetServerId, false)
                offScreenReveal = true
                if hidden then
                    hidden = false
                    NetworkConcealEntity(ped, false)
                end
                goto nextTick
            end

            if IsEntityDead(ped) then
                reportSeeing(targetServerId, true)
                if hidden then
                    hidden = false
                    NetworkConcealEntity(ped, false)
                end
                goto nextTick
            end

            if DISABLE_FOW_IN_INTERIORS then
                local pedInterior = sharedPlayerInteriors[playerId] or 0
                if sharedLocalInterior ~= 0 or pedInterior ~= 0 then
                    reportSeeing(targetServerId, true)
                    if hidden then
                        hidden = false
                        NetworkConcealEntity(ped, false)
                    end
                    goto nextTick
                end
            end

            local camPos = sharedCamPos
            local baseZ  = realZ + 0.05

            local anyVisible = false

            local chest = vector3(coords.x, coords.y, baseZ + 0.7)
            if isVisible(camPos, chest, ped) then
                anyVisible = true
            end

            if not anyVisible then
                if lastDistance2D <= SIDES_MAX_DISTANCE then
                    local heading = GetEntityHeading(ped)
                    local vel     = GetEntityVelocity(ped)

                    local fwdX, fwdY = localToWorld(0.0, 1.0, heading)
                    local rgtX, rgtY = localToWorld(1.0, 0.0, heading)
                    local velForward = vel.x * fwdX + vel.y * fwdY
                    local velRight   = vel.x * rgtX + vel.y * rgtY

                    for _, side in ipairs(SIDES) do
                        local projectedVel = side.lx * velRight + side.ly * velForward
                        local distance     = OFFSET_BASE

                        if projectedVel > 0.0 then
                            distance = distance + math.min(projectedVel / VEL_MAX, 1.0) * (OFFSET_MAX - OFFSET_BASE)
                        end

                        local wx, wy    = localToWorld(side.lx * distance, side.ly * distance, heading)
                        local markerPos = vector3(coords.x + wx, coords.y + wy, baseZ)

                        if isVisible(camPos, markerPos, ped) then
                            anyVisible = true
                        end
                    end
                end
            end

            reportSeeing(targetServerId, anyVisible)

            local shouldHide = not anyVisible

            if shouldHide and seenByServerIds[targetServerId] then
                shouldHide = false
            end

            if hidden ~= shouldHide then
                hidden = shouldHide
                NetworkConcealEntity(ped, shouldHide)
            end

            ::nextTick::
        end

        if reportedSeeing[targetServerId] then
            reportedSeeing[targetServerId] = nil
            pendingUnsee[targetServerId]   = nil
            TriggerServerEvent("fow:setSeeing", targetServerId, false)
        end

        activeThreads[playerId] = nil
    end)
end

-- ============================================
--  Scanner: detects streamed-in players and
--  starts a dedicated thread for each one
-- ============================================
CreateThread(function()
    while true do
        Wait(SCAN_INTERVAL)

        for _, playerId in ipairs(GetActivePlayers()) do
            if playerId ~= PlayerId() and not activeThreads[playerId] then
                local ped = GetPlayerPed(playerId)
                if DoesEntityExist(ped) then
                    startPlayerThread(playerId, ped)
                end
            end
        end
    end
end)
