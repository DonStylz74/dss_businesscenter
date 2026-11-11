local ESX = exports['es_extended']:getSharedObject()

local centerPed
local centerBlip
local worldBusinesses = {}
local signEntities = {}
local businessBlips = {}
local uiOpen = false
local certificateOpen = false
local placementActive = false
local signDetailsOpen = false
local expiredCertificateSlot

CreateThread(function()
    Wait(500)
    exports.ox_inventory:displayMetadata({
        business_name = 'Business',
        owner_name = 'Purchaser',
        purchase_price = 'Purchase Price',
        purchase_date = 'Purchase Date',
        certificate_number = 'Certificate No.'
    })
end)

local function notify(notifyType, description)
    lib.notify({
        title = 'Business Centre',
        type = notifyType or 'inform',
        description = description
    })
end

RegisterNetEvent('dss_businesscenter:client:notify', function(notifyType, description)
    notify(notifyType, description)
end)

-- GTA/FiveM model names never include the streamed file extension.
-- Keep this normalization local to model use so configured/database values cannot
-- accidentally pass `.ydr` (or a trailing dot) into joaat/IsModelValid.
local function normalizePropModelName(modelName)
    if type(modelName) ~= 'string' then return '' end
    modelName = modelName:match('^%s*(.-)%s*$') or ''

    while modelName:lower():sub(-4) == '.ydr' do
        modelName = modelName:sub(1, -5)
        modelName = modelName:match('^%s*(.-)%s*$') or ''
    end

    modelName = modelName:gsub('%.+$', '')
    return modelName
end

local function deleteEntitySafe(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

local function removeSign(id)
    if signEntities[id] then
        pcall(function()
            exports.ox_target:removeLocalEntity(signEntities[id], ('dss_businesscenter:sign_details:%s'):format(id))
        end)
        deleteEntitySafe(signEntities[id])
        signEntities[id] = nil
    end
end

local function removeBusinessBlips()
    for _, blip in pairs(businessBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    businessBlips = {}
end

local function createBusinessBlips()
    removeBusinessBlips()

    for _, business in ipairs(worldBusinesses) do
        local shouldShow = business.enable_blip
        if Config.BusinessBlips.ShowOnlyWhenForSale and business.status == 'owned' then
            shouldShow = false
        end

        if shouldShow and business.blip_coords then
            local coords = business.blip_coords
            local blip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
            SetBlipSprite(blip, tonumber(business.blip_sprite) or 475)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, tonumber(business.blip_scale) or Config.BusinessBlips.DefaultScale)
            SetBlipColour(blip, tonumber(business.blip_color) or 5)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(business.blip_name or business.name or 'Business')
            EndTextCommandSetBlipName(blip)
            businessBlips[business.id] = blip
        end
    end
end

local function spawnForSaleSign(business)
    if signEntities[business.id] or not business.sign_coords then return end

    local modelName = normalizePropModelName(business.sign_model)
    if modelName == '' then modelName = normalizePropModelName(Config.ForSaleSign.DefaultModel) end
    local model = joaat(modelName)

    if not IsModelValid(model) then
        if Config.Debug then
            print(('[dss_businesscenter] Invalid sign model for business %s: %s'):format(business.id, modelName))
        end
        return
    end

    local ok = pcall(lib.requestModel, model, 5000)
    if not ok or not HasModelLoaded(model) then
        if Config.Debug then
            print(('[dss_businesscenter] Unable to load sign model: %s'):format(modelName))
        end
        return
    end

    local coords = business.sign_coords
    local object = CreateObjectNoOffset(model, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
    if object == 0 then
        SetModelAsNoLongerNeeded(model)
        return
    end

    SetEntityHeading(object, coords.w + 0.0)
    FreezeEntityPosition(object, true)
    SetEntityInvincible(object, true)
    SetEntityCollision(object, Config.ForSaleSign.Collision == true, Config.ForSaleSign.Collision == true)
    SetEntityAlpha(object, tonumber(Config.ForSaleSign.Alpha) or 255, false)
    signEntities[business.id] = object

    exports.ox_target:addLocalEntity(object, {
        {
            name = ('dss_businesscenter:sign_details:%s'):format(business.id),
            icon = 'fa-solid fa-circle-info',
            label = 'View Business Details',
            distance = tonumber(Config.ForSaleSign.TargetDistance) or 2.5,
            onSelect = function()
                local details = lib.callback.await('dss_businesscenter:server:getPublicBusinessDetails', false, business.id)
                if not details or details.error then
                    notify('error', details and details.error or 'Unable to load business details.')
                    return
                end

                signDetailsOpen = true
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(false)
                SendNUIMessage({ action = 'showBusinessDetails', business = details })
            end
        }
    })

    SetModelAsNoLongerNeeded(model)
end

local function refreshWorldBusinesses(data)
    -- Recreate streamed signs after any server-side change so edited prop models/coords are applied immediately.
    for id in pairs(signEntities) do removeSign(id) end
    worldBusinesses = data or {}
    createBusinessBlips()
end

RegisterNetEvent('dss_businesscenter:client:syncWorld', function(data)
    refreshWorldBusinesses(data)
end)

local function setUiFocus(state)
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function closeBusinessUi()
    uiOpen = false
    SendNUIMessage({ action = 'close' })
    if not certificateOpen and not signDetailsOpen then setUiFocus(false) end
end

local function openBusinessUi(initialTab)
    if placementActive then return end

    local data = lib.callback.await('dss_businesscenter:server:getData', false)
    if not data then
        notify('error', 'Unable to load Business Centre data.')
        return
    end
    if data.error then
        notify('error', data.error)
        return
    end

    if initialTab == 'admin' and not data.canAdmin then
        notify('error', 'You do not have access to the admin panel.')
        return
    end

    uiOpen = true
    setUiFocus(true)
    SendNUIMessage({
        action = 'open',
        data = data,
        initialTab = initialTab or 'sale'
    })
end

RegisterNetEvent('dss_businesscenter:client:openAdmin', function()
    openBusinessUi('admin')
end)

local function sendUiResult(cb, result)
    result = result or { success = false, message = 'No response from server.' }
    if result.data then
        SendNUIMessage({ action = 'setData', data = result.data, selectedId = result.selectedId })
    end
    cb(result)
end

RegisterNUICallback('close', function(_, cb)
    closeBusinessUi()
    cb({ success = true })
end)

RegisterNUICallback('closeBusinessDetails', function(_, cb)
    signDetailsOpen = false
    SendNUIMessage({ action = 'hideBusinessDetails' })
    if not uiOpen and not certificateOpen then setUiFocus(false) end
    cb({ success = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    local data = lib.callback.await('dss_businesscenter:server:getData', false)
    if data and not data.error then
        SendNUIMessage({ action = 'setData', data = data })
        cb({ success = true })
    else
        cb({ success = false, message = data and data.error or 'Unable to refresh.' })
    end
end)

RegisterNUICallback('purchase', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:purchase', false, tonumber(data.id)))
end)

RegisterNUICallback('salePreflight', function(data, cb)
    cb(lib.callback.await('dss_businesscenter:server:salePreflight', false, tonumber(data.id), data.mode, tonumber(data.price)))
end)

RegisterNUICallback('sellInstant', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:sellInstant', false, tonumber(data.id), data.acceptMissingCertificateFee == true))
end)

RegisterNUICallback('listForSale', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:listForSale', false, tonumber(data.id), tonumber(data.price), data.acceptMissingCertificateFee == true))
end)

RegisterNUICallback('cancelListing', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:cancelListing', false, tonumber(data.id)))
end)

RegisterNUICallback('setActiveJob', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:setActiveJob', false, tonumber(data.id)))
end)

RegisterNUICallback('replacementCertificate', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:replacementCertificate', false, tonumber(data.id)))
end)

RegisterNUICallback('adminSave', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:adminSave', false, tonumber(data.id), data.payload or {}))
end)

RegisterNUICallback('adminRemoveOwner', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:adminRemoveOwner', false, tonumber(data.id), data.refund == true))
end)

RegisterNUICallback('adminClearListing', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:adminClearListing', false, tonumber(data.id)))
end)

RegisterNUICallback('adminDelete', function(data, cb)
    sendUiResult(cb, lib.callback.await('dss_businesscenter:server:adminDelete', false, tonumber(data.id)))
end)

local function validPlacementCoords(coords)
    return type(coords) == 'table' and tonumber(coords.x) and tonumber(coords.y) and tonumber(coords.z)
end

local function finishPlacement(entity, cancelled)
    local coords, heading
    if entity and DoesEntityExist(entity) then
        coords = GetEntityCoords(entity)
        heading = GetEntityHeading(entity)
        deleteEntitySafe(entity)
    end

    placementActive = false
    lib.hideTextUI()
    setUiFocus(true)

    if cancelled or not coords then
        SendNUIMessage({ action = 'placementCancelled' })
    else
        SendNUIMessage({
            action = 'placementResult',
            coords = {
                x = tonumber(('%0.4f'):format(coords.x)),
                y = tonumber(('%0.4f'):format(coords.y)),
                z = tonumber(('%0.4f'):format(coords.z)),
                w = tonumber(('%0.4f'):format(heading))
            }
        })
    end
end

local function startPlacement(modelName, initialCoords)
    if placementActive then return false, 'A placement session is already active.' end

    modelName = normalizePropModelName(modelName)
    if modelName == '' then modelName = normalizePropModelName(Config.ForSaleSign.DefaultModel) end
    local model = joaat(modelName)
    if not IsModelValid(model) then return false, ('Invalid prop model: %s'):format(modelName) end

    local ok = pcall(lib.requestModel, model, 5000)
    if not ok or not HasModelLoaded(model) then return false, ('Could not load prop model: %s'):format(modelName) end

    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local x, y, z, heading

    if validPlacementCoords(initialCoords) then
        local ix, iy, iz = tonumber(initialCoords.x), tonumber(initialCoords.y), tonumber(initialCoords.z)
        local distance = #(playerCoords - vector3(ix, iy, iz))
        if distance <= 60.0 then
            x, y, z = ix, iy, iz
            heading = tonumber(initialCoords.w) or GetEntityHeading(ped)
        end
    end

    if not x then
        local spawn = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.0)
        x, y, z = spawn.x, spawn.y, spawn.z - 0.8
        heading = GetEntityHeading(ped)
    end

    local object = CreateObjectNoOffset(model, x, y, z, false, false, false)
    if object == 0 then
        SetModelAsNoLongerNeeded(model)
        return false, 'Could not create the placement prop.'
    end

    SetEntityHeading(object, heading)
    SetEntityCollision(object, false, false)
    SetEntityAlpha(object, tonumber(Config.ForSaleSign.PlacementAlpha) or 155, false)
    SetEntityInvincible(object, true)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(model)

    placementActive = true
    uiOpen = true
    setUiFocus(false)
    SendNUIMessage({ action = 'placementMode' })

    lib.showTextUI('[ARROWS] Move  [Q/E] Rotate  [PGUP/PGDN] Height  [G] Snap to ground  [SHIFT] Fast  [ENTER] Confirm  [BACKSPACE] Cancel', {
        position = 'top-center',
        icon = 'building'
    })

    CreateThread(function()
        local moveStep = tonumber(Config.ForSaleSign.PlacementMoveStep) or 0.035
        local rotateStep = tonumber(Config.ForSaleSign.PlacementRotateStep) or 1.0
        local heightStep = tonumber(Config.ForSaleSign.PlacementHeightStep) or 0.02
        local fastMultiplier = tonumber(Config.ForSaleSign.PlacementFastMultiplier) or 4.0

        while placementActive and DoesEntityExist(object) do
            Wait(0)

            DisableControlAction(0, 172, true) -- arrow up
            DisableControlAction(0, 173, true) -- arrow down
            DisableControlAction(0, 174, true) -- arrow left
            DisableControlAction(0, 175, true) -- arrow right
            DisableControlAction(0, 44, true)  -- Q
            DisableControlAction(0, 38, true)  -- E
            DisableControlAction(0, 10, true)  -- PageUp
            DisableControlAction(0, 11, true)  -- PageDown
            DisableControlAction(0, 47, true)  -- G
            DisableControlAction(0, 201, true) -- Enter
            DisableControlAction(0, 177, true) -- Backspace
            DisableControlAction(0, 200, true) -- Esc
            DisableControlAction(0, 245, true) -- chat

            local multiplier = IsControlPressed(0, 21) and fastMultiplier or 1.0
            local current = GetEntityCoords(object)
            local currentHeading = GetEntityHeading(object)
            local rad = math.rad(currentHeading)
            local forwardX, forwardY = -math.sin(rad), math.cos(rad)
            local rightX, rightY = math.cos(rad), math.sin(rad)
            local dx, dy, dz = 0.0, 0.0, 0.0

            if IsDisabledControlPressed(0, 172) then dx, dy = dx + forwardX, dy + forwardY end
            if IsDisabledControlPressed(0, 173) then dx, dy = dx - forwardX, dy - forwardY end
            if IsDisabledControlPressed(0, 174) then dx, dy = dx - rightX, dy - rightY end
            if IsDisabledControlPressed(0, 175) then dx, dy = dx + rightX, dy + rightY end
            if IsDisabledControlPressed(0, 10) then dz = dz + heightStep * multiplier end
            if IsDisabledControlPressed(0, 11) then dz = dz - heightStep * multiplier end

            if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then
                SetEntityCoordsNoOffset(object,
                    current.x + (dx * moveStep * multiplier),
                    current.y + (dy * moveStep * multiplier),
                    current.z + dz,
                    false, false, false)
            end

            if IsDisabledControlPressed(0, 44) then
                SetEntityHeading(object, currentHeading + (rotateStep * multiplier))
            elseif IsDisabledControlPressed(0, 38) then
                SetEntityHeading(object, currentHeading - (rotateStep * multiplier))
            end

            if IsDisabledControlJustPressed(0, 47) then
                FreezeEntityPosition(object, false)
                SetEntityCollision(object, true, true)
                PlaceObjectOnGroundProperly(object)
                Wait(0)
                SetEntityCollision(object, false, false)
                FreezeEntityPosition(object, true)
            end

            if IsDisabledControlJustPressed(0, 201) then
                finishPlacement(object, false)
                break
            end

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
                finishPlacement(object, true)
                break
            end
        end
    end)

    return true
end

RegisterNUICallback('startSignPlacement', function(data, cb)
    local success, message = startPlacement(data.model, data.coords)
    cb({ success = success, message = message })
end)

RegisterNetEvent('dss_businesscenter:client:showCertificate', function(metadata, expiredSlot)
    certificateOpen = true
    expiredCertificateSlot = tonumber(expiredSlot)
    setUiFocus(true)
    SendNUIMessage({ action = 'showCertificate', certificate = metadata })
end)

RegisterNUICallback('closeCertificate', function(_, cb)
    local slotToRemove = expiredCertificateSlot
    expiredCertificateSlot = nil
    certificateOpen = false
    SendNUIMessage({ action = 'hideCertificate' })

    if slotToRemove then
        lib.callback.await('dss_businesscenter:server:removeExpiredCertificate', false, slotToRemove)
    end

    if not uiOpen and not signDetailsOpen then setUiFocus(false) end
    cb({ success = true })
end)

local function createCenterPed()
    local model = joaat(Config.BusinessCenter.PedModel)
    local ok = pcall(lib.requestModel, model, 5000)
    if not ok or not HasModelLoaded(model) then
        print('[dss_businesscenter] Failed to load Business Centre ped model.')
        return
    end

    local coords = Config.BusinessCenter.PedCoords
    centerPed = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityAsMissionEntity(centerPed, true, true)
    SetEntityInvincible(centerPed, true)
    FreezeEntityPosition(centerPed, true)
    SetBlockingOfNonTemporaryEvents(centerPed, true)
    SetPedCanRagdoll(centerPed, false)

    if Config.BusinessCenter.Scenario and Config.BusinessCenter.Scenario ~= '' then
        TaskStartScenarioInPlace(centerPed, Config.BusinessCenter.Scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(centerPed, {
        {
            name = 'dss_businesscenter:open',
            icon = 'fa-solid fa-building',
            label = 'Open Business Centre',
            distance = Config.BusinessCenter.TargetDistance,
            onSelect = function()
                openBusinessUi('sale')
            end
        }
    })

    SetModelAsNoLongerNeeded(model)
end

local function createCenterBlip()
    if not Config.BusinessCenter.EnableBlip then return end
    local coords = Config.BusinessCenter.BlipCoords
    centerBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(centerBlip, Config.BusinessCenter.BlipSprite)
    SetBlipDisplay(centerBlip, 4)
    SetBlipScale(centerBlip, Config.BusinessCenter.BlipScale)
    SetBlipColour(centerBlip, Config.BusinessCenter.BlipColor)
    SetBlipAsShortRange(centerBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.BusinessCenter.BlipName)
    EndTextCommandSetBlipName(centerBlip)
end

CreateThread(function()
    Wait(1000)
    createCenterPed()
    createCenterBlip()
    TriggerServerEvent('dss_businesscenter:server:requestWorldSync')
end)

-- Distance-stream for for-sale signs so large business lists do not keep every prop spawned map-wide.
CreateThread(function()
    while true do
        local sleep = 1500
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        for _, business in ipairs(worldBusinesses) do
            local forSale = business.status ~= 'owned'
            local signCoords = business.sign_coords

            if forSale and signCoords then
                local distance = #(coords - vector3(signCoords.x, signCoords.y, signCoords.z))
                if distance <= 300.0 then
                    if not signEntities[business.id] then spawnForSaleSign(business) end
                elseif distance > 350.0 then
                    removeSign(business.id)
                end
            else
                removeSign(business.id)
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(1000)
    TriggerServerEvent('dss_businesscenter:server:requestWorldSync')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if centerPed and DoesEntityExist(centerPed) then
        exports.ox_target:removeLocalEntity(centerPed, 'dss_businesscenter:open')
        deleteEntitySafe(centerPed)
    end

    if centerBlip and DoesBlipExist(centerBlip) then RemoveBlip(centerBlip) end
    removeBusinessBlips()
    for id in pairs(signEntities) do removeSign(id) end

    if placementActive then
        placementActive = false
        lib.hideTextUI()
    end

    setUiFocus(false)
end)
