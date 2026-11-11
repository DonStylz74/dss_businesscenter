local ESX = exports['es_extended']:getSharedObject()
local ox_inventory = exports.ox_inventory

local RESOURCE = GetCurrentResourceName()
local offlineBankSchema
local databaseReady = false

local function debugPrint(...)
    if Config.Debug then
        print(('^5[%s]^7'):format(RESOURCE), ...)
    end
end

local function notify(src, notifyType, description)
    TriggerClientEvent('dss_businesscenter:client:notify', src, notifyType or 'inform', description)
end

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return value:match('^%s*(.-)%s*$') or ''
end

local function normalizePropModelName(modelName)
    modelName = trim(modelName)

    while modelName:lower():sub(-4) == '.ydr' do
        modelName = trim(modelName:sub(1, -5))
    end

    modelName = modelName:gsub('%.+$', '')
    return modelName
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function toInteger(value, default)
    local number = tonumber(value)
    if not number then return default end
    return math.floor(number + 0.0)
end

local function truthy(value)
    return value == true or value == 1 or value == '1' or value == 'true'
end

local function getIdentifier(xPlayer)
    if not xPlayer then return nil end
    if xPlayer.getIdentifier then return xPlayer.getIdentifier() end
    return xPlayer.identifier
end

local function getCharacterSlot(identifier)
    if type(identifier) ~= 'string' then return nil end
    return tonumber(identifier:match('^char(%d+):'))
end

local function getPlayerDisplayName(src, xPlayer)
    if xPlayer and xPlayer.getName then
        local ok, name = pcall(xPlayer.getName, xPlayer)
        if ok and name and name ~= '' then return name end
    end
    return GetPlayerName(src) or 'Unknown'
end

local function getLicense(src)
    if GetPlayerIdentifierByType then
        return GetPlayerIdentifierByType(src, 'license')
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == 'license:' then
            return identifier
        end
    end
end

local function getOnlinePlayerByIdentifier(identifier)
    if not identifier then return nil end
    local players = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or ESX.GetPlayers()

    for _, value in pairs(players) do
        local xPlayer = type(value) == 'number' and ESX.GetPlayerFromId(value) or value
        if xPlayer and getIdentifier(xPlayer) == identifier then
            return xPlayer
        end
    end
end

local function isAdmin(src, xPlayer)
    if src == 0 then return true end

    if Config.Admin.AcePermission and Config.Admin.AcePermission ~= '' and IsPlayerAceAllowed(src, Config.Admin.AcePermission) then
        return true
    end

    xPlayer = xPlayer or ESX.GetPlayerFromId(src)
    if not xPlayer or not xPlayer.job then return false end

    for _, permission in ipairs(Config.Admin.AllowedJobs or {}) do
        if xPlayer.job.name == permission.job and tonumber(xPlayer.job.grade or 0) >= tonumber(permission.grade or 0) then
            return true
        end
    end

    return false
end

local function isNearBusinessCenter(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local center = Config.BusinessCenter.PedCoords
    local dx, dy, dz = coords.x - center.x, coords.y - center.y, coords.z - center.z
    local maxDistance = tonumber(Config.BusinessCenter.ServerValidationDistance) or 6.0
    return (dx * dx + dy * dy + dz * dz) <= (maxDistance * maxDistance)
end

local function requireBusinessCenter(src)
    if isNearBusinessCenter(src) then return true end
    return false, 'You must be at the Business Centre to do this.'
end

local function isCashAccount(account)
    account = tostring(account or ''):lower()
    return account == 'money' or account == 'cash'
end

local function getPlayerSource(xPlayer)
    if not xPlayer then return nil end
    return tonumber(xPlayer.source or xPlayer.playerId)
end

local function getBalance(xPlayer, account)
    if isCashAccount(account) then
        local src = getPlayerSource(xPlayer)
        if not src then return 0 end

        return tonumber(ox_inventory:Search(src, 'count', Config.CashItem or 'money')) or 0
    end

    local accountData = xPlayer.getAccount(account)
    return accountData and tonumber(accountData.money) or 0
end

local function removeFunds(xPlayer, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end

    if isCashAccount(account) then
        local src = getPlayerSource(xPlayer)
        if not src then return false end

        local cashItem = Config.CashItem or 'money'
        local balance = tonumber(ox_inventory:Search(src, 'count', cashItem)) or 0
        if balance < amount then return false end

        local success, response = ox_inventory:RemoveItem(src, cashItem, amount)
        if not success then
            debugPrint(('ox_inventory failed to remove %s x%s from player %s: %s'):format(cashItem, amount, src, tostring(response)))
            return false
        end

        return true
    end

    local accountData = xPlayer.getAccount(account)
    local balance = accountData and tonumber(accountData.money) or 0
    if balance < amount then return false end

    xPlayer.removeAccountMoney(account, amount, reason or 'Business transaction')
    return true
end

local function addFunds(xPlayer, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end

    if isCashAccount(account) then
        local src = getPlayerSource(xPlayer)
        if not src then return false end

        local cashItem = Config.CashItem or 'money'
        local success, response = ox_inventory:AddItem(src, cashItem, amount)
        if not success then
            debugPrint(('ox_inventory failed to add %s x%s to player %s: %s'):format(cashItem, amount, src, tostring(response)))
            return false
        end

        return true
    end

    xPlayer.addAccountMoney(account, amount, reason or 'Business transaction')
    return true
end

local function addPendingPayout(identifier, amount, reason, businessId)
    if not identifier or not amount or amount <= 0 then return end
    MySQL.insert.await([[
        INSERT INTO dss_business_payouts (identifier, business_id, amount, reason, status)
        VALUES (?, ?, ?, ?, 'pending')
    ]], { identifier, businessId, math.floor(amount), reason or 'Business payout' })
end

local function creditIdentifierBank(identifier, amount, reason, businessId)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not identifier then return true end

    local online = getOnlinePlayerByIdentifier(identifier)
    if online then
        online.addAccountMoney('bank', amount, reason or 'Business payout')
        return true
    end

    if offlineBankSchema == 'accounts' then
        local row = MySQL.single.await('SELECT accounts FROM users WHERE identifier = ? LIMIT 1', { identifier })
        if row and row.accounts then
            local ok, accounts = pcall(json.decode, row.accounts)
            if ok and type(accounts) == 'table' then
                local updated = false

                if accounts.bank ~= nil and tonumber(accounts.bank) then
                    accounts.bank = tonumber(accounts.bank) + amount
                    updated = true
                else
                    for _, account in pairs(accounts) do
                        if type(account) == 'table' and account.name == 'bank' then
                            account.money = (tonumber(account.money) or 0) + amount
                            updated = true
                            break
                        end
                    end
                end

                if updated then
                    local affected = MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { json.encode(accounts), identifier })
                    if affected and affected > 0 then return true end
                end
            end
        end
    elseif offlineBankSchema == 'bank' then
        local affected = MySQL.update.await('UPDATE users SET bank = COALESCE(bank, 0) + ? WHERE identifier = ?', { amount, identifier })
        if affected and affected > 0 then return true end
    end

    addPendingPayout(identifier, amount, reason, businessId)
    return false
end

local function processPendingPayouts(xPlayer)
    if not xPlayer then return end
    local identifier = getIdentifier(xPlayer)
    if not identifier then return end

    local payouts = MySQL.query.await([[
        SELECT id, amount FROM dss_business_payouts
        WHERE identifier = ? AND status = 'pending'
        ORDER BY id ASC
    ]], { identifier }) or {}

    if #payouts == 0 then return end

    local total, ids = 0, {}
    for _, payout in ipairs(payouts) do
        total = total + (tonumber(payout.amount) or 0)
        ids[#ids + 1] = tonumber(payout.id)
    end

    if total <= 0 then return end

    xPlayer.addAccountMoney('bank', total, 'Pending business payouts')
    for _, id in ipairs(ids) do
        MySQL.update.await("UPDATE dss_business_payouts SET status = 'paid', paid_at = NOW() WHERE id = ? AND status = 'pending'", { id })
    end

    notify(xPlayer.source, 'success', ('$%s in pending business proceeds has been deposited into your bank.'):format(total))
end

local function writeHistory(businessId, action, actorIdentifier, actorName, details)
    MySQL.insert.await([[
        INSERT INTO dss_business_history (business_id, action, actor_identifier, actor_name, details)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        businessId,
        action,
        actorIdentifier,
        actorName,
        details and json.encode(details) or nil
    })
end

local function getBusiness(id)
    return MySQL.single.await('SELECT * FROM dss_businesses WHERE id = ? LIMIT 1', { tonumber(id) })
end

local function getOwnedCount(identifier)
    return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM dss_businesses WHERE status = 'owned' AND owner_identifier = ?", { identifier })) or 0
end

local function getJobGrade(jobName, grade)
    local jobs = ESX.GetJobs and ESX.GetJobs() or nil
    if not jobs or not jobs[jobName] then return nil, 'The ESX job does not exist.' end

    grade = tonumber(grade)
    local grades = jobs[jobName].grades or {}
    local gradeData = grades[tostring(grade)] or grades[grade]

    if not gradeData then
        for key, data in pairs(grades) do
            if tonumber(key) == grade or tonumber(data.grade) == grade then
                gradeData = data
                break
            end
        end
    end

    if not gradeData then return nil, 'The configured ESX job grade does not exist.' end

    if Config.RequireConfiguredGradeToBeBoss and gradeData.name ~= 'boss' then
        return nil, ('Grade %s for job %s is not the boss grade.'):format(grade, jobName)
    end

    return gradeData
end


local function getJobDisplay(jobName, grade)
    local jobs = ESX.GetJobs and ESX.GetJobs() or {}
    local job = jobs and jobs[jobName]
    if not job then return jobName or 'Unknown', tostring(grade or '') end

    local gradeData
    local grades = job.grades or {}
    grade = tonumber(grade)
    gradeData = grades[tostring(grade)] or grades[grade]
    if not gradeData then
        for key, data in pairs(grades) do
            if tonumber(key) == grade or tonumber(data.grade) == grade then
                gradeData = data
                break
            end
        end
    end

    local jobLabel = job.label or jobName or 'Unknown'
    local gradeLabel = gradeData and (gradeData.label or gradeData.name) or tostring(grade or '')
    return jobLabel, gradeLabel
end

local function getAvailableSignModels()
    local models, seen = {}, {}

    local function add(model)
        model = normalizePropModelName(model)
        if model ~= '' and not seen[model] then
            seen[model] = true
            models[#models + 1] = model
        end
    end

    -- The creator receives GTA model names, never streamed .ydr filenames.
    add(Config.ForSaleSign.DefaultModel or 'prop_forsale_sign_fs')

    if Config.ZeroDazedAdvertBillboards and Config.ZeroDazedAdvertBillboards.Enabled then
        -- Keep these explicit so the creator always shows both addon models even if
        -- an older config contains filename-style values such as *.ydr.
        add('zero_advertisement_small')
        add('zero_advertisement_large')
    end

    return models
end

local function formatCertificateDate(value)
    if value == nil then return os.date('%d/%m/%Y %H:%M') end

    local numeric = tonumber(value)
    if numeric then
        if numeric > 100000000000 then numeric = numeric / 1000 end
        if numeric > 1000000000 then
            return os.date('%d/%m/%Y %H:%M', math.floor(numeric))
        end
    end

    local text = tostring(value)
    local y, m, d, hh, mm = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[ T](%d%d):(%d%d)')
    if y then return ('%s/%s/%s %s:%s'):format(d, m, y, hh, mm) end
    return text
end

local function generateOwnershipToken(businessId, identifier)
    return ('%s:%s:%s:%06d'):format(tonumber(businessId) or 0, os.time(), tostring(identifier or 'unknown'):sub(-12), math.random(0, 999999))
end

local function certificateMatchesOwnership(row, metadata, identifier)
    if not row or type(metadata) ~= 'table' or not identifier then return false end
    if row.status ~= 'owned' or row.owner_identifier ~= identifier then return false end
    if tonumber(metadata.business_id) ~= tonumber(row.id) then return false end
    if metadata.owner_identifier ~= identifier then return false end

    local currentToken = trim(row.ownership_token)
    if currentToken ~= '' then
        return trim(metadata.ownership_token) == currentToken
    end

    -- Legacy ownerships created before ownership tokens were introduced remain valid until
    -- the ownership changes or a replacement certificate is issued.
    return true
end

local function findValidCertificate(src, row, identifier)
    local slots = exports.ox_inventory:Search(src, 'slots', Config.Certificate.ItemName) or {}
    for _, slotData in pairs(slots) do
        if slotData and certificateMatchesOwnership(row, slotData.metadata or {}, identifier) then
            return slotData
        end
    end
end

local function removeValidCertificates(src, row, identifier)
    local slots = exports.ox_inventory:Search(src, 'slots', Config.Certificate.ItemName) or {}
    local removed = 0
    for _, slotData in pairs(slots) do
        if slotData and certificateMatchesOwnership(row, slotData.metadata or {}, identifier) then
            local ok = exports.ox_inventory:RemoveItem(src, Config.Certificate.ItemName, 1, nil, slotData.slot)
            if ok then removed = removed + 1 end
        end
    end
    return removed
end

local function certificateSaleAmounts(gross, hasValidCertificate)
    gross = math.max(0, math.floor(tonumber(gross) or 0))
    local percentage = math.max(0, tonumber(Config.Certificate.MissingCertificateSaleFeePercentage) or 2.5)
    local fee = hasValidCertificate and 0 or math.floor(gross * (percentage / 100))
    return gross, fee, math.max(0, gross - fee), percentage
end

local function validateCoords(coords)
    if type(coords) ~= 'table' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    local w = tonumber(coords.w or coords.heading or 0.0)
    if not x or not y or not z or not w then return nil end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or z < -1000 or z > 3000 then return nil end
    w = w % 360.0
    return { x = x, y = y, z = z, w = w }
end

local function validateBusinessPayload(payload)
    if type(payload) ~= 'table' then return nil, 'Invalid business data.' end

    local data = {}
    data.name = trim(payload.name or payload.BusinessName):sub(1, 80)
    data.business_type = trim(payload.business_type or payload.BusinessType):sub(1, 60)
    data.description = trim(payload.description or payload.Description):sub(1, 600)
    data.price = toInteger(payload.price or payload.BusinessPrice, 0)
    data.job = trim(payload.job or payload.BusinessJob):sub(1, 50)
    data.job_grade = toInteger(payload.job_grade or payload.BusinessGrade, -1)
    data.sell_back_percentage = tonumber(payload.sell_back_percentage or payload.SellBackPercentage)
    data.image = trim(payload.image or payload.BusinessImage):sub(1, 255)
    data.sign_model = normalizePropModelName(payload.sign_model or payload.SignModel):sub(1, 80)
    data.sign_coords = validateCoords(payload.sign_coords or payload.SignCoords)
    data.enable_blip = truthy(payload.enable_blip or payload.EnableBlip)
    data.blip_coords = validateCoords(payload.blip_coords or payload.BlipCoords)
    data.blip_sprite = toInteger(payload.blip_sprite or payload.BlipSprite, 475)
    data.blip_color = toInteger(payload.blip_color or payload.BlipColor, 5)
    data.blip_scale = tonumber(payload.blip_scale or payload.BlipScale) or tonumber(Config.BusinessBlips.DefaultScale) or 0.65
    data.blip_name = trim(payload.blip_name or payload.BlipName):sub(1, 80)

    if data.name == '' then return nil, 'Business name is required.' end
    if data.price < 1 then return nil, 'Business price must be greater than $0.' end
    if data.job == '' or not data.job:match('^[%w_%-]+$') then return nil, 'A valid ESX job name is required.' end
    if data.job_grade < 0 then return nil, 'Business grade is required.' end
    if not data.sell_back_percentage or data.sell_back_percentage < 0 or data.sell_back_percentage > 100 then
        return nil, 'Sell-back percentage must be between 0 and 100.'
    end
    if data.blip_scale < 0.10 or data.blip_scale > 5.00 then
        return nil, 'Blip size must be between 0.10 and 5.00.'
    end
    if not data.sign_coords then return nil, 'Valid sign coordinates are required.' end
    if data.sign_model == '' then data.sign_model = Config.ForSaleSign.DefaultModel end
    if data.image == '' then data.image = 'assets/businesses/default-business.svg' end
    if data.business_type == '' then data.business_type = 'Commercial Business' end
    if data.blip_name == '' then data.blip_name = data.name end

    if data.enable_blip and not data.blip_coords then
        data.blip_coords = { x = data.sign_coords.x, y = data.sign_coords.y, z = data.sign_coords.z, w = 0.0 }
    end

    local _, gradeError = getJobGrade(data.job, data.job_grade)
    if gradeError then return nil, gradeError end

    return data
end

local function worldRow(row)
    return {
        id = tonumber(row.id),
        name = row.name,
        status = row.status,
        sign_model = row.sign_model,
        sign_coords = {
            x = tonumber(row.sign_x), y = tonumber(row.sign_y), z = tonumber(row.sign_z), w = tonumber(row.sign_w)
        },
        enable_blip = truthy(row.enable_blip),
        blip_coords = {
            x = tonumber(row.blip_x), y = tonumber(row.blip_y), z = tonumber(row.blip_z)
        },
        blip_sprite = tonumber(row.blip_sprite),
        blip_color = tonumber(row.blip_color),
        blip_scale = tonumber(row.blip_scale) or Config.BusinessBlips.DefaultScale,
        blip_name = row.blip_name
    }
end

local function sendWorldSync(target)
    local rows = MySQL.query.await('SELECT * FROM dss_businesses ORDER BY id ASC') or {}
    local output = {}
    for _, row in ipairs(rows) do output[#output + 1] = worldRow(row) end
    TriggerClientEvent('dss_businesscenter:client:syncWorld', target, output)
end

local function broadcastWorldSync()
    sendWorldSync(-1)
end

local function businessForUI(row, identifier, admin)
    local isOwner = identifier and row.owner_identifier == identifier or false
    local isSeller = identifier and row.seller_identifier == identifier or false
    local jobLabel, jobGradeLabel = getJobDisplay(row.job, row.job_grade)
    local result = {
        id = tonumber(row.id),
        name = row.name,
        businessType = row.business_type,
        description = row.description,
        price = tonumber(row.price),
        job = row.job,
        jobLabel = jobLabel,
        jobGrade = tonumber(row.job_grade),
        jobGradeLabel = jobGradeLabel,
        sellBackPercentage = tonumber(row.sell_back_percentage),
        sellBackValue = math.floor((tonumber(row.price) or 0) * ((tonumber(row.sell_back_percentage) or 0) / 100)),
        image = row.image,
        signModel = row.sign_model,
        signCoords = { x = tonumber(row.sign_x), y = tonumber(row.sign_y), z = tonumber(row.sign_z), w = tonumber(row.sign_w) },
        enableBlip = truthy(row.enable_blip),
        blipCoords = { x = tonumber(row.blip_x), y = tonumber(row.blip_y), z = tonumber(row.blip_z), w = 0.0 },
        blipSprite = tonumber(row.blip_sprite),
        blipColor = tonumber(row.blip_color),
        blipScale = tonumber(row.blip_scale),
        blipName = row.blip_name,
        status = row.status,
        ownerName = row.owner_name,
        purchasePrice = tonumber(row.purchase_price),
        purchasedAt = row.purchased_at,
        lastActive = row.last_active,
        listingPrice = tonumber(row.listing_price),
        sellerName = row.seller_name,
        listedAt = row.listed_at,
        sellerCertificateFee = tonumber(row.seller_certificate_fee) or 0,
        isOwner = isOwner,
        isSeller = isSeller
    }

    if admin then
        result.ownerIdentifier = row.owner_identifier
        result.ownerLicense = row.owner_license
        result.ownerCharacterSlot = tonumber(row.owner_char_slot)
        result.sellerIdentifier = row.seller_identifier
        result.sellerLicense = row.seller_license
        result.createdBy = row.created_by
        result.createdAt = row.created_at
        result.updatedAt = row.updated_at
    end

    return result
end

local function getUIData(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local identifier = getIdentifier(xPlayer)
    local admin = isAdmin(src, xPlayer)
    local rows = MySQL.query.await('SELECT * FROM dss_businesses ORDER BY name ASC') or {}
    local businesses = {}

    for _, row in ipairs(rows) do
        businesses[#businesses + 1] = businessForUI(row, identifier, admin)
    end

    return {
        businesses = businesses,
        canAdmin = admin,
        ownedCount = getOwnedCount(identifier),
        maxBusinesses = Config.MaxBusinessesPerCharacter,
        listingMinPercentage = Config.PlayerListing.MinPercentage,
        listingMaxPercentage = Config.PlayerListing.MaxPercentage,
        replacementFee = Config.Certificate.ReplacementFee,
        missingCertificateFeePercentage = tonumber(Config.Certificate.MissingCertificateSaleFeePercentage) or 2.5,
        multiJobEnabled = not Config.MultiJob or Config.MultiJob.Enabled ~= false,
        signModels = getAvailableSignModels(),
        defaultBlipScale = tonumber(Config.BusinessBlips.DefaultScale) or 0.65,
        inactivityDays = Config.Inactivity.Days,
        inactivityRefundPercentage = Config.Inactivity.RefundPercentage,
        adminRemovalRefundPercentage = Config.Admin.RemovalRefundPercentage,
        nearBusinessCenter = isNearBusinessCenter(src)
    }
end

local function certificateMetadata(row, ownerName, identifier, paidPrice, purchasedAt)
    local serial = ('LSBC-%05d-%d-%04d'):format(tonumber(row.id) or 0, os.time(), math.random(1000, 9999))
    return {
        label = ('Ownership Certificate - %s'):format(row.name),
        description = ('Los Santos Business Center purchase certificate for %s.'):format(row.name),
        type = 'Business Ownership Certificate',
        business_id = tonumber(row.id),
        business_name = row.name,
        business_type = row.business_type,
        owner_name = ownerName,
        owner_identifier = identifier,
        owner_character = getCharacterSlot(identifier),
        ownership_token = row.ownership_token,
        purchase_price = math.floor(tonumber(paidPrice) or tonumber(row.price) or 0),
        purchase_date = formatCertificateDate(purchasedAt),
        certificate_number = serial,
        image = 'business_certificate.png'
    }
end

local function giveCertificate(src, row, paidPrice, purchasedAt)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false, 'Player not found.' end
    local identifier = getIdentifier(xPlayer)
    local metadata = certificateMetadata(row, getPlayerDisplayName(src, xPlayer), identifier, paidPrice, purchasedAt)

    local canCarry = exports.ox_inventory:CanCarryItem(src, Config.Certificate.ItemName, 1, metadata)
    if not canCarry then return false, 'No inventory space for the business certificate.' end

    local success, response = exports.ox_inventory:AddItem(src, Config.Certificate.ItemName, 1, metadata)
    if not success then return false, response or 'Unable to issue certificate.' end
    return true
end

local function setFallbackJobIfNeeded(xPlayer, businessJob)
    if xPlayer and xPlayer.job and xPlayer.job.name == businessJob then
        xPlayer.setJob(Config.DefaultJobAfterSale.name, Config.DefaultJobAfterSale.grade)
    end
end

local function hasRequiredLicense(src)
    if not Config.RequireBusinessLicense then return true end
    local count = exports.ox_inventory:GetItemCount(src, Config.BusinessLicenseItem)
    return (tonumber(count) or 0) > 0
end

lib.callback.register('dss_businesscenter:server:getData', function(src)
    if not databaseReady then return { error = 'Business database is still starting.' } end
    return getUIData(src)
end)


lib.callback.register('dss_businesscenter:server:getPublicBusinessDetails', function(src, businessId)
    if not databaseReady then return { error = 'Business database is still starting.' } end
    local row = getBusiness(businessId)
    if not row or (row.status ~= 'for_sale' and row.status ~= 'listed') or row.owner_identifier then
        return { error = 'This business is no longer for sale.' }
    end
    return businessForUI(row, nil, false)
end)

lib.callback.register('dss_businesscenter:server:salePreflight', function(src, businessId, mode, requestedPrice)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)
    if not row or row.status ~= 'owned' or row.owner_identifier ~= identifier then
        return { success = false, message = 'Only the recorded purchaser can sell this business.' }
    end

    local gross
    if mode == 'listing' then
        local basePrice = tonumber(row.price) or 0
        local minPrice = math.floor(basePrice * (Config.PlayerListing.MinPercentage / 100))
        local maxPrice = math.floor(basePrice * (Config.PlayerListing.MaxPercentage / 100))
        gross = toInteger(requestedPrice, 0)
        if gross < minPrice or gross > maxPrice then
            return { success = false, message = ('Listing price must be between $%s and $%s.'):format(minPrice, maxPrice) }
        end
    else
        gross = math.floor((tonumber(row.price) or 0) * ((tonumber(row.sell_back_percentage) or 0) / 100))
    end

    local hasValidCertificate = findValidCertificate(src, row, identifier) ~= nil
    local saleGross, fee, net, feePercentage = certificateSaleAmounts(gross, hasValidCertificate)
    return {
        success = true,
        hasValidCertificate = hasValidCertificate,
        gross = saleGross,
        fee = fee,
        net = net,
        feePercentage = feePercentage
    }
end)

lib.callback.register('dss_businesscenter:server:purchase', function(src, businessId)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or (row.status ~= 'for_sale' and row.status ~= 'listed') or row.owner_identifier then
        return { success = false, message = 'This business is no longer available.' }
    end

    if row.seller_identifier and row.seller_identifier == identifier then
        return { success = false, message = 'This is your own listing. Cancel the listing instead of buying it.' }
    end

    if getOwnedCount(identifier) >= Config.MaxBusinessesPerCharacter then
        return { success = false, message = ('You can own a maximum of %s businesses.'):format(Config.MaxBusinessesPerCharacter) }
    end

    if not hasRequiredLicense(src) then
        return { success = false, message = 'You need a business license to purchase a business.' }
    end

    local _, gradeError = getJobGrade(row.job, row.job_grade)
    if gradeError then return { success = false, message = gradeError } end

    local price = row.status == 'listed' and tonumber(row.listing_price) or tonumber(row.price)
    if not price or price <= 0 then return { success = false, message = 'This business has an invalid sale price.' } end

    if not removeFunds(xPlayer, Config.PurchaseAccount, price, ('Purchase: %s'):format(row.name)) then
        return { success = false, message = 'You do not have enough money for this business.' }
    end

    local ownerName = getPlayerDisplayName(src, xPlayer)
    local ownerLicense = getLicense(src)
    local sellerIdentifier = row.seller_identifier
    local sellerName = row.seller_name
    local sellerCertificateFee = math.max(0, tonumber(row.seller_certificate_fee) or 0)
    local ownershipToken = generateOwnershipToken(row.id, identifier)

    local affected = MySQL.update.await([[
        UPDATE dss_businesses
        SET status = 'owned',
            owner_identifier = ?, owner_license = ?, owner_name = ?, owner_char_slot = ?, ownership_token = ?,
            purchase_price = ?, purchased_at = NOW(), last_active = NOW(),
            seller_identifier = NULL, seller_license = NULL, seller_name = NULL,
            listing_price = NULL, listed_at = NULL, seller_certificate_fee = 0
        WHERE id = ? AND owner_identifier IS NULL AND status IN ('for_sale', 'listed')
    ]], {
        identifier, ownerLicense, ownerName, getCharacterSlot(identifier), ownershipToken, price, tonumber(row.id)
    })

    if not affected or affected ~= 1 then
        addFunds(xPlayer, Config.PurchaseAccount, price, 'Refund - business purchase race')
        return { success = false, message = 'Someone else purchased this business first. Your money was refunded.' }
    end

    local sellerPayout = price
    if sellerIdentifier then
        sellerPayout = math.max(0, price - sellerCertificateFee)
        creditIdentifierBank(sellerIdentifier, sellerPayout, ('Sale proceeds: %s'):format(row.name), row.id)
        local onlineSeller = getOnlinePlayerByIdentifier(sellerIdentifier)
        if onlineSeller and sellerCertificateFee > 0 then
            notify(onlineSeller.source, 'inform', ('%s sold for $%s. A $%s missing-certificate fee was deducted; $%s was deposited to your bank.'):format(row.name, price, sellerCertificateFee, sellerPayout))
        end
    end

    xPlayer.setJob(row.job, tonumber(row.job_grade))

    local updated = getBusiness(row.id)
    local certificateOk, certificateError = giveCertificate(src, updated, price, updated.purchased_at)

    writeHistory(row.id, sellerIdentifier and 'player_listing_purchased' or 'business_purchased', identifier, ownerName, {
        price = price,
        seller = sellerIdentifier,
        sellerName = sellerName,
        sellerCertificateFee = sellerCertificateFee,
        sellerPayout = sellerPayout
    })

    broadcastWorldSync()

    local message = ('You purchased %s for $%s and were assigned as the business boss.'):format(row.name, price)
    if not certificateOk then
        message = message .. (' Certificate was not issued: %s You can request a replacement at the Business Centre.'):format(certificateError or 'unknown error')
    end

    return { success = true, message = message, data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:sellInstant', function(src, businessId, acceptMissingCertificateFee)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or row.status ~= 'owned' or row.owner_identifier ~= identifier then
        return { success = false, message = 'Only the recorded purchaser can sell this business.' }
    end

    local grossRefund = math.floor((tonumber(row.price) or 0) * ((tonumber(row.sell_back_percentage) or 0) / 100))
    local validCertificate = findValidCertificate(src, row, identifier)
    local gross, fee, refund, feePercentage = certificateSaleAmounts(grossRefund, validCertificate ~= nil)
    if not validCertificate and not truthy(acceptMissingCertificateFee) then
        return {
            success = false,
            requiresCertificateDecision = true,
            message = 'A valid business ownership certificate was not found.',
            gross = gross, fee = fee, net = refund, feePercentage = feePercentage
        }
    end

    local affected = MySQL.update.await([[
        UPDATE dss_businesses
        SET status = 'for_sale', owner_identifier = NULL, owner_license = NULL, owner_name = NULL,
            owner_char_slot = NULL, ownership_token = NULL, purchase_price = NULL, purchased_at = NULL, last_active = NULL,
            seller_identifier = NULL, seller_license = NULL, seller_name = NULL, listing_price = NULL, listed_at = NULL,
            seller_certificate_fee = 0
        WHERE id = ? AND owner_identifier = ? AND status = 'owned'
    ]], { tonumber(row.id), identifier })

    if not affected or affected ~= 1 then
        return { success = false, message = 'The business ownership changed before the sale could complete.' }
    end

    if validCertificate then removeValidCertificates(src, row, identifier) end
    addFunds(xPlayer, Config.OwnerSalePayoutAccount, refund, ('Business Centre buyback: %s'):format(row.name))
    setFallbackJobIfNeeded(xPlayer, row.job)

    writeHistory(row.id, 'business_sold_to_center', identifier, getPlayerDisplayName(src, xPlayer), {
        gross = gross, certificateFee = fee, payout = refund, hadValidCertificate = validCertificate ~= nil
    })
    broadcastWorldSync()

    local message
    if fee > 0 then
        message = ('%s was sold back for $%s. A %s%% missing-certificate fee ($%s) was deducted; you received $%s.'):format(row.name, gross, feePercentage, fee, refund)
    else
        message = ('%s was sold back to the Business Centre for $%s.'):format(row.name, refund)
    end
    return { success = true, message = message, data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:listForSale', function(src, businessId, requestedPrice, acceptMissingCertificateFee)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or row.status ~= 'owned' or row.owner_identifier ~= identifier then
        return { success = false, message = 'Only the recorded purchaser can list this business.' }
    end

    local basePrice = tonumber(row.price) or 0
    local minPrice = math.floor(basePrice * (Config.PlayerListing.MinPercentage / 100))
    local maxPrice = math.floor(basePrice * (Config.PlayerListing.MaxPercentage / 100))
    local listingPrice = toInteger(requestedPrice, 0)

    if listingPrice < minPrice or listingPrice > maxPrice then
        return { success = false, message = ('Listing price must be between $%s and $%s.'):format(minPrice, maxPrice) }
    end

    local validCertificate = findValidCertificate(src, row, identifier)
    local gross, certificateFee, net, feePercentage = certificateSaleAmounts(listingPrice, validCertificate ~= nil)
    if not validCertificate and not truthy(acceptMissingCertificateFee) then
        return {
            success = false,
            requiresCertificateDecision = true,
            message = 'A valid business ownership certificate was not found.',
            gross = gross, fee = certificateFee, net = net, feePercentage = feePercentage
        }
    end

    local affected = MySQL.update.await([[
        UPDATE dss_businesses
        SET status = 'listed',
            seller_identifier = owner_identifier, seller_license = owner_license, seller_name = owner_name,
            listing_price = ?, listed_at = NOW(), seller_certificate_fee = ?,
            owner_identifier = NULL, owner_license = NULL, owner_name = NULL, owner_char_slot = NULL,
            last_active = NULL
        WHERE id = ? AND owner_identifier = ? AND status = 'owned'
    ]], { listingPrice, certificateFee, tonumber(row.id), identifier })

    if not affected or affected ~= 1 then
        return { success = false, message = 'The listing could not be created because ownership changed.' }
    end

    setFallbackJobIfNeeded(xPlayer, row.job)
    writeHistory(row.id, 'business_listed_by_owner', identifier, getPlayerDisplayName(src, xPlayer), {
        listingPrice = listingPrice, certificateFee = certificateFee, expectedNet = net, hadValidCertificate = validCertificate ~= nil
    })
    broadcastWorldSync()

    local message = ('%s is now listed for $%s. You will be paid when another player buys it.'):format(row.name, listingPrice)
    if certificateFee > 0 then
        message = message .. (' A %s%% missing-certificate fee ($%s) will be deducted from the sale proceeds.'):format(feePercentage, certificateFee)
    end
    return { success = true, message = message, data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:cancelListing', function(src, businessId)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or row.status ~= 'listed' or row.seller_identifier ~= identifier then
        return { success = false, message = 'You are not the seller of this listing.' }
    end

    if getOwnedCount(identifier) >= Config.MaxBusinessesPerCharacter then
        return { success = false, message = 'You are already at your ownership limit. Sell another business before cancelling this listing.' }
    end

    local _, gradeError = getJobGrade(row.job, row.job_grade)
    if gradeError then return { success = false, message = gradeError } end

    local affected = MySQL.update.await([[
        UPDATE dss_businesses
        SET status = 'owned',
            owner_identifier = seller_identifier, owner_license = seller_license, owner_name = seller_name,
            owner_char_slot = ?, seller_identifier = NULL, seller_license = NULL, seller_name = NULL,
            listing_price = NULL, listed_at = NULL, seller_certificate_fee = 0, last_active = NOW()
        WHERE id = ? AND status = 'listed' AND seller_identifier = ?
    ]], { getCharacterSlot(identifier), tonumber(row.id), identifier })

    if not affected or affected ~= 1 then return { success = false, message = 'The listing changed before it could be cancelled.' } end

    xPlayer.setJob(row.job, tonumber(row.job_grade))
    writeHistory(row.id, 'business_listing_cancelled', identifier, getPlayerDisplayName(src, xPlayer))
    broadcastWorldSync()

    return { success = true, message = ('The listing for %s was cancelled and ownership was restored.'):format(row.name), data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:setActiveJob', function(src, businessId)
    if Config.MultiJob and Config.MultiJob.Enabled == false then
        return { success = false, message = 'Business job switching is disabled in config.lua.' }
    end

    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or row.status ~= 'owned' or row.owner_identifier ~= identifier then
        return { success = false, message = 'You do not own this business.' }
    end

    local _, gradeError = getJobGrade(row.job, row.job_grade)
    if gradeError then return { success = false, message = gradeError } end

    xPlayer.setJob(row.job, tonumber(row.job_grade))
    MySQL.update.await('UPDATE dss_businesses SET last_active = NOW() WHERE id = ?', { row.id })
    return { success = true, message = ('Your active job is now %s.'):format(row.name), data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:replacementCertificate', function(src, businessId)
    local atCenter, centerError = requireBusinessCenter(src)
    if not atCenter then return { success = false, message = centerError } end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return { success = false, message = 'Player not found.' } end
    local identifier = getIdentifier(xPlayer)
    local row = getBusiness(businessId)

    if not row or row.status ~= 'owned' or row.owner_identifier ~= identifier then
        return { success = false, message = 'A replacement certificate can only be issued to the recorded owner.' }
    end

    local fee = math.max(0, tonumber(Config.Certificate.ReplacementFee) or 0)
    if fee > 0 and getBalance(xPlayer, Config.Certificate.ReplacementFeeAccount) < fee then
        return { success = false, message = ('You need $%s for the replacement certificate fee.'):format(fee) }
    end

    -- Every replacement rotates the ownership token. This makes a lost/stolen previous
    -- certificate expire immediately while keeping the current ownership itself unchanged.
    row.ownership_token = generateOwnershipToken(row.id, identifier)
    MySQL.update.await('UPDATE dss_businesses SET ownership_token = ? WHERE id = ? AND owner_identifier = ? AND status = \'owned\'', { row.ownership_token, row.id, identifier })

    local metadata = certificateMetadata(row, getPlayerDisplayName(src, xPlayer), identifier, row.purchase_price or row.price, row.purchased_at)
    if not exports.ox_inventory:CanCarryItem(src, Config.Certificate.ItemName, 1, metadata) then
        return { success = false, message = 'You do not have enough inventory space for the certificate.' }
    end

    if fee > 0 then
        removeFunds(xPlayer, Config.Certificate.ReplacementFeeAccount, fee, 'Replacement business certificate')
    end

    local success, response = exports.ox_inventory:AddItem(src, Config.Certificate.ItemName, 1, metadata)
    if not success then
        if fee > 0 then addFunds(xPlayer, Config.Certificate.ReplacementFeeAccount, fee, 'Certificate fee refund') end
        return { success = false, message = response or 'The replacement certificate could not be issued.' }
    end

    writeHistory(row.id, 'replacement_certificate_issued', identifier, getPlayerDisplayName(src, xPlayer), { fee = fee })
    return { success = true, message = ('A replacement certificate was issued for $%s.'):format(fee), data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:adminSave', function(src, businessId, payload)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not isAdmin(src, xPlayer) then return { success = false, message = 'You do not have permission to manage businesses.' } end

    local data, validationError = validateBusinessPayload(payload)
    if not data then return { success = false, message = validationError } end

    local actorIdentifier = xPlayer and getIdentifier(xPlayer) or 'console'
    local actorName = xPlayer and getPlayerDisplayName(src, xPlayer) or 'Console'
    local id = tonumber(businessId)

    if not id then
        id = MySQL.insert.await([[
            INSERT INTO dss_businesses
            (name, business_type, description, price, job, job_grade, sell_back_percentage, image,
             sign_model, sign_x, sign_y, sign_z, sign_w,
             enable_blip, blip_x, blip_y, blip_z, blip_sprite, blip_color, blip_scale, blip_name,
             status, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'for_sale', ?)
        ]], {
            data.name, data.business_type, data.description, data.price, data.job, data.job_grade, data.sell_back_percentage, data.image,
            data.sign_model, data.sign_coords.x, data.sign_coords.y, data.sign_coords.z, data.sign_coords.w,
            data.enable_blip and 1 or 0,
            data.blip_coords and data.blip_coords.x or data.sign_coords.x,
            data.blip_coords and data.blip_coords.y or data.sign_coords.y,
            data.blip_coords and data.blip_coords.z or data.sign_coords.z,
            data.blip_sprite, data.blip_color, data.blip_scale, data.blip_name,
            actorIdentifier
        })

        writeHistory(id, 'business_created', actorIdentifier, actorName, { name = data.name })
    else
        local existing = getBusiness(id)
        if not existing then return { success = false, message = 'Business not found.' } end

        local minListing = math.floor(data.price * (Config.PlayerListing.MinPercentage / 100))
        local maxListing = math.floor(data.price * (Config.PlayerListing.MaxPercentage / 100))
        local listingPrice = existing.listing_price and clamp(tonumber(existing.listing_price), minListing, maxListing) or nil

        MySQL.update.await([[
            UPDATE dss_businesses SET
                name = ?, business_type = ?, description = ?, price = ?, job = ?, job_grade = ?,
                sell_back_percentage = ?, image = ?, sign_model = ?, sign_x = ?, sign_y = ?, sign_z = ?, sign_w = ?,
                enable_blip = ?, blip_x = ?, blip_y = ?, blip_z = ?, blip_sprite = ?, blip_color = ?, blip_scale = ?, blip_name = ?,
                listing_price = ?, updated_at = NOW()
            WHERE id = ?
        ]], {
            data.name, data.business_type, data.description, data.price, data.job, data.job_grade,
            data.sell_back_percentage, data.image, data.sign_model,
            data.sign_coords.x, data.sign_coords.y, data.sign_coords.z, data.sign_coords.w,
            data.enable_blip and 1 or 0,
            data.blip_coords and data.blip_coords.x or data.sign_coords.x,
            data.blip_coords and data.blip_coords.y or data.sign_coords.y,
            data.blip_coords and data.blip_coords.z or data.sign_coords.z,
            data.blip_sprite, data.blip_color, data.blip_scale, data.blip_name, listingPrice, id
        })

        if existing.status == 'owned' and existing.owner_identifier and existing.job ~= data.job then
            local owner = getOnlinePlayerByIdentifier(existing.owner_identifier)
            if owner and owner.job and owner.job.name == existing.job then
                owner.setJob(data.job, data.job_grade)
            end
        elseif existing.status == 'owned' and existing.owner_identifier and tonumber(existing.job_grade) ~= data.job_grade then
            local owner = getOnlinePlayerByIdentifier(existing.owner_identifier)
            if owner and owner.job and owner.job.name == data.job then owner.setJob(data.job, data.job_grade) end
        end

        writeHistory(id, 'business_edited', actorIdentifier, actorName, { name = data.name })
    end

    broadcastWorldSync()
    return { success = true, message = 'Business saved successfully.', data = getUIData(src), selectedId = id }
end)

lib.callback.register('dss_businesscenter:server:adminRemoveOwner', function(src, businessId, issueRefund)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not isAdmin(src, xPlayer) then return { success = false, message = 'You do not have permission.' } end

    local row = getBusiness(businessId)
    if not row or row.status ~= 'owned' or not row.owner_identifier then
        return { success = false, message = 'This business does not currently have an owner.' }
    end

    local ownerIdentifier = row.owner_identifier
    local refund = 0
    if truthy(issueRefund) then
        refund = math.floor((tonumber(row.price) or 0) * ((tonumber(Config.Admin.RemovalRefundPercentage) or 0) / 100))
    end

    local affected = MySQL.update.await([[
        UPDATE dss_businesses SET
            status = 'for_sale', owner_identifier = NULL, owner_license = NULL, owner_name = NULL, owner_char_slot = NULL,
            ownership_token = NULL, purchase_price = NULL, purchased_at = NULL, last_active = NULL,
            seller_identifier = NULL, seller_license = NULL, seller_name = NULL, listing_price = NULL, listed_at = NULL,
            seller_certificate_fee = 0
        WHERE id = ? AND owner_identifier = ?
    ]], { row.id, ownerIdentifier })

    if not affected or affected ~= 1 then return { success = false, message = 'Ownership changed before it could be removed.' } end

    local onlineOwner = getOnlinePlayerByIdentifier(ownerIdentifier)
    if onlineOwner then setFallbackJobIfNeeded(onlineOwner, row.job) end
    if refund > 0 then creditIdentifierBank(ownerIdentifier, refund, ('Administrative business removal: %s'):format(row.name), row.id) end

    local actorIdentifier = xPlayer and getIdentifier(xPlayer) or 'console'
    local actorName = xPlayer and getPlayerDisplayName(src, xPlayer) or 'Console'
    writeHistory(row.id, 'owner_removed_by_admin', actorIdentifier, actorName, { previousOwner = ownerIdentifier, refund = refund })
    broadcastWorldSync()

    return { success = true, message = refund > 0 and ('Owner removed and $%s refund issued.'):format(refund) or 'Owner removed without a refund.', data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:adminClearListing', function(src, businessId)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not isAdmin(src, xPlayer) then return { success = false, message = 'You do not have permission.' } end

    local row = getBusiness(businessId)
    if not row or row.status ~= 'listed' then return { success = false, message = 'This business is not player-listed.' } end

    MySQL.update.await([[
        UPDATE dss_businesses SET status = 'for_sale', seller_identifier = NULL, seller_license = NULL,
        seller_name = NULL, listing_price = NULL, listed_at = NULL, seller_certificate_fee = 0,
        ownership_token = NULL, purchase_price = NULL, purchased_at = NULL
        WHERE id = ? AND status = 'listed'
    ]], { row.id })

    local actorIdentifier = xPlayer and getIdentifier(xPlayer) or 'console'
    local actorName = xPlayer and getPlayerDisplayName(src, xPlayer) or 'Console'
    writeHistory(row.id, 'player_listing_cleared_by_admin', actorIdentifier, actorName, { seller = row.seller_identifier })
    broadcastWorldSync()
    return { success = true, message = 'Player listing cleared. The business is now a standard Business Centre sale.', data = getUIData(src) }
end)

lib.callback.register('dss_businesscenter:server:adminDelete', function(src, businessId)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not isAdmin(src, xPlayer) then return { success = false, message = 'You do not have permission.' } end

    local row = getBusiness(businessId)
    if not row then return { success = false, message = 'Business not found.' } end
    if row.status == 'owned' then return { success = false, message = 'Remove the owner before deleting this business.' } end
    if row.status == 'listed' then return { success = false, message = 'Clear the player listing before deleting this business.' } end

    local actorIdentifier = xPlayer and getIdentifier(xPlayer) or 'console'
    local actorName = xPlayer and getPlayerDisplayName(src, xPlayer) or 'Console'
    writeHistory(row.id, 'business_deleted', actorIdentifier, actorName, { name = row.name })
    MySQL.update.await('DELETE FROM dss_businesses WHERE id = ?', { row.id })
    broadcastWorldSync()

    return { success = true, message = 'Business deleted.', data = getUIData(src) }
end)

RegisterNetEvent('dss_businesscenter:server:requestWorldSync', function()
    if databaseReady then sendWorldSync(source) end
end)

RegisterCommand(Config.Admin.Command, function(source)
    if source == 0 then
        print(('[%s] The in-game admin UI must be opened by a player.'):format(RESOURCE))
        return
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not isAdmin(source, xPlayer) then
        notify(source, 'error', 'You do not have permission to use the Business Centre admin panel.')
        return
    end

    TriggerClientEvent('dss_businesscenter:client:openAdmin', source)
end, false)

local function findClosestPlayer(src, maxDistance)
    local sourcePed = GetPlayerPed(src)
    if not sourcePed or sourcePed == 0 then return nil end
    local sourceCoords = GetEntityCoords(sourcePed)
    local closest, closestDistance

    for _, idString in ipairs(GetPlayers()) do
        local id = tonumber(idString)
        if id and id ~= src then
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local dx, dy, dz = sourceCoords.x - coords.x, sourceCoords.y - coords.y, sourceCoords.z - coords.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if distance <= maxDistance and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = id, distance
                end
            end
        end
    end

    return closest
end

local function safeCertificateMetadata(metadata, expired)
    return {
        businessId = metadata.business_id,
        businessName = metadata.business_name or 'Unknown Business',
        businessType = metadata.business_type or 'Commercial Business',
        ownerName = metadata.owner_name or 'Unknown',
        ownerCharacter = metadata.owner_character,
        purchasePrice = tonumber(metadata.purchase_price) or 0,
        purchaseDate = formatCertificateDate(metadata.purchase_date or 'Unknown'),
        certificateNumber = metadata.certificate_number or 'Unknown',
        expired = expired == true
    }
end

local function certificateIsCurrentlyValid(metadata)
    if type(metadata) ~= 'table' then return false end
    local row = getBusiness(metadata.business_id)
    if not row or not row.owner_identifier then return false end
    return certificateMatchesOwnership(row, metadata, row.owner_identifier)
end

exports('business_certificate', function(event, item, inventory, slot)
    if event ~= 'usingItem' then return end
    if not inventory or not inventory.id then return false end

    local src = tonumber(inventory.id)
    if not src then return false end
    local slotData = exports.ox_inventory:GetSlot(src, slot)
    if not slotData or slotData.name ~= Config.Certificate.ItemName then return false end

    local metadata = slotData.metadata or {}
    local expired = not certificateIsCurrentlyValid(metadata)
    local safe = safeCertificateMetadata(metadata, expired)
    local targets = { [src] = true }

    local closest = findClosestPlayer(src, tonumber(Config.Certificate.ShowDistance) or 3.0)
    if closest then targets[closest] = true end

    if metadata.owner_identifier then
        local owner = getOnlinePlayerByIdentifier(metadata.owner_identifier)
        if owner and owner.source then targets[owner.source] = true end
    end

    for target in pairs(targets) do
        TriggerClientEvent('dss_businesscenter:client:showCertificate', target, safe, target == src and expired and tonumber(slot) or nil)
    end

    return true
end)

lib.callback.register('dss_businesscenter:server:removeExpiredCertificate', function(src, slot)
    slot = tonumber(slot)
    if not slot then return { success = false } end

    local slotData = exports.ox_inventory:GetSlot(src, slot)
    if not slotData or slotData.name ~= Config.Certificate.ItemName then return { success = false } end
    if certificateIsCurrentlyValid(slotData.metadata or {}) then return { success = false } end

    local success = exports.ox_inventory:RemoveItem(src, Config.Certificate.ItemName, 1, nil, slot)
    if success then
        notify(src, 'inform', 'The expired business certificate has been removed from your inventory.')
    end
    return { success = success == true }
end)

local function updateActivityForOnlineJobs()
    if not databaseReady or not Config.Inactivity.Enabled then return end
    local seenJobs = {}
    local players = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or ESX.GetPlayers()

    for _, value in pairs(players) do
        local xPlayer = type(value) == 'number' and ESX.GetPlayerFromId(value) or value
        if xPlayer and xPlayer.job and xPlayer.job.name and not seenJobs[xPlayer.job.name] then
            seenJobs[xPlayer.job.name] = true
            MySQL.update.await("UPDATE dss_businesses SET last_active = NOW() WHERE status = 'owned' AND job = ?", { xPlayer.job.name })
        end
    end
end

local function runInactivityCheck()
    if not databaseReady or not Config.Inactivity.Enabled then return end
    local days = math.max(1, tonumber(Config.Inactivity.Days) or 30)
    local cutoff = os.date('%Y-%m-%d %H:%M:%S', os.time() - (days * 86400))
    local rows = MySQL.query.await([[
        SELECT * FROM dss_businesses
        WHERE status = 'owned' AND owner_identifier IS NOT NULL AND last_active IS NOT NULL AND last_active < ?
    ]], { cutoff }) or {}

    local changed = false
    for _, row in ipairs(rows) do
        local affected = MySQL.update.await([[
            UPDATE dss_businesses SET
                status = 'for_sale', owner_identifier = NULL, owner_license = NULL, owner_name = NULL, owner_char_slot = NULL,
                ownership_token = NULL, purchase_price = NULL, purchased_at = NULL, last_active = NULL,
                seller_identifier = NULL, seller_license = NULL, seller_name = NULL, listing_price = NULL, listed_at = NULL,
                seller_certificate_fee = 0
            WHERE id = ? AND owner_identifier = ? AND status = 'owned' AND last_active < ?
        ]], { row.id, row.owner_identifier, cutoff })

        if affected and affected == 1 then
            changed = true
            local refund = math.floor((tonumber(row.price) or 0) * ((tonumber(Config.Inactivity.RefundPercentage) or 0) / 100))
            if refund > 0 then
                creditIdentifierBank(row.owner_identifier, refund, ('Inactive business repossession: %s'):format(row.name), row.id)
            end

            local onlineOwner = getOnlinePlayerByIdentifier(row.owner_identifier)
            if onlineOwner then
                setFallbackJobIfNeeded(onlineOwner, row.job)
                notify(onlineOwner.source, 'warning', ('%s was returned to the Business Centre after %s days without business activity. $%s was deposited to your bank.'):format(row.name, days, refund))
            end

            writeHistory(row.id, 'business_repossessed_inactive', row.owner_identifier, row.owner_name, { refund = refund, inactiveDays = days })
        end
    end

    if changed then broadcastWorldSync() end
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    CreateThread(function()
        Wait(1500)
        processPendingPayouts(xPlayer)
        if xPlayer and xPlayer.job and xPlayer.job.name then
            MySQL.update.await("UPDATE dss_businesses SET last_active = NOW() WHERE status = 'owned' AND job = ?", { xPlayer.job.name })
        end
        sendWorldSync(playerId)
    end)
end)

local function setupDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS dss_businesses (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            name VARCHAR(80) NOT NULL,
            business_type VARCHAR(60) NOT NULL DEFAULT 'Commercial Business',
            description TEXT NULL,
            price INT UNSIGNED NOT NULL,
            job VARCHAR(50) NOT NULL,
            job_grade INT NOT NULL,
            sell_back_percentage DECIMAL(5,2) NOT NULL DEFAULT 50.00,
            image VARCHAR(255) NULL,
            sign_model VARCHAR(80) NOT NULL DEFAULT 'prop_forsale_sign_fs',
            sign_x DECIMAL(10,4) NOT NULL,
            sign_y DECIMAL(10,4) NOT NULL,
            sign_z DECIMAL(10,4) NOT NULL,
            sign_w DECIMAL(10,4) NOT NULL DEFAULT 0.0000,
            enable_blip TINYINT(1) NOT NULL DEFAULT 0,
            blip_x DECIMAL(10,4) NULL,
            blip_y DECIMAL(10,4) NULL,
            blip_z DECIMAL(10,4) NULL,
            blip_sprite INT NOT NULL DEFAULT 475,
            blip_color INT NOT NULL DEFAULT 5,
            blip_scale DECIMAL(4,2) NOT NULL DEFAULT 0.65,
            blip_name VARCHAR(80) NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'for_sale',
            owner_identifier VARCHAR(100) NULL,
            owner_license VARCHAR(100) NULL,
            owner_name VARCHAR(100) NULL,
            owner_char_slot INT NULL,
            ownership_token VARCHAR(128) NULL,
            purchase_price INT UNSIGNED NULL,
            purchased_at DATETIME NULL,
            last_active DATETIME NULL,
            seller_identifier VARCHAR(100) NULL,
            seller_license VARCHAR(100) NULL,
            seller_name VARCHAR(100) NULL,
            listing_price INT UNSIGNED NULL,
            listed_at DATETIME NULL,
            seller_certificate_fee INT UNSIGNED NOT NULL DEFAULT 0,
            created_by VARCHAR(100) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_business_status (status),
            KEY idx_business_owner (owner_identifier),
            KEY idx_business_seller (seller_identifier),
            KEY idx_business_job (job),
            KEY idx_business_activity (last_active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    local ownershipTokenColumn = MySQL.query.await("SHOW COLUMNS FROM dss_businesses LIKE 'ownership_token'") or {}
    if #ownershipTokenColumn == 0 then
        MySQL.query.await("ALTER TABLE dss_businesses ADD COLUMN ownership_token VARCHAR(128) NULL AFTER owner_char_slot")
    end

    local certificateFeeColumn = MySQL.query.await("SHOW COLUMNS FROM dss_businesses LIKE 'seller_certificate_fee'") or {}
    if #certificateFeeColumn == 0 then
        MySQL.query.await("ALTER TABLE dss_businesses ADD COLUMN seller_certificate_fee INT UNSIGNED NOT NULL DEFAULT 0 AFTER listed_at")
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS dss_business_history (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            business_id INT UNSIGNED NULL,
            action VARCHAR(60) NOT NULL,
            actor_identifier VARCHAR(100) NULL,
            actor_name VARCHAR(100) NULL,
            details LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_history_business (business_id),
            KEY idx_history_action (action)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS dss_business_payouts (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            identifier VARCHAR(100) NOT NULL,
            business_id INT UNSIGNED NULL,
            amount INT UNSIGNED NOT NULL,
            reason VARCHAR(255) NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            paid_at DATETIME NULL,
            PRIMARY KEY (id),
            KEY idx_payout_identifier_status (identifier, status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    local accountColumn = MySQL.query.await("SHOW COLUMNS FROM users LIKE 'accounts'") or {}
    if #accountColumn > 0 then
        offlineBankSchema = 'accounts'
    else
        local bankColumn = MySQL.query.await("SHOW COLUMNS FROM users LIKE 'bank'") or {}
        if #bankColumn > 0 then offlineBankSchema = 'bank' end
    end

    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM dss_businesses')) or 0
    if count == 0 and Config.SeedBusinesses and #Config.SeedBusinesses > 0 then
        for _, seed in ipairs(Config.SeedBusinesses) do
            local data, err = validateBusinessPayload(seed)
            if data then
                MySQL.insert.await([[
                    INSERT INTO dss_businesses
                    (name, business_type, description, price, job, job_grade, sell_back_percentage, image,
                     sign_model, sign_x, sign_y, sign_z, sign_w,
                     enable_blip, blip_x, blip_y, blip_z, blip_sprite, blip_color, blip_scale, blip_name,
                     status, created_by)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'for_sale', 'config_seed')
                ]], {
                    data.name, data.business_type, data.description, data.price, data.job, data.job_grade,
                    data.sell_back_percentage, data.image, data.sign_model,
                    data.sign_coords.x, data.sign_coords.y, data.sign_coords.z, data.sign_coords.w,
                    data.enable_blip and 1 or 0,
                    data.blip_coords and data.blip_coords.x or data.sign_coords.x,
                    data.blip_coords and data.blip_coords.y or data.sign_coords.y,
                    data.blip_coords and data.blip_coords.z or data.sign_coords.z,
                    data.blip_sprite, data.blip_color, data.blip_scale, data.blip_name
                })
            else
                print(('^1[%s] Seed business skipped: %s^7'):format(RESOURCE, err or 'invalid data'))
            end
        end
    end

    databaseReady = true
    debugPrint('Database ready. Offline bank mode:', offlineBankSchema or 'pending-payout fallback')
    broadcastWorldSync()
end

MySQL.ready(function()
    math.randomseed(os.time())
    setupDatabase()

    CreateThread(function()
        while true do
            Wait(math.max(1, tonumber(Config.Inactivity.ActivityHeartbeatMinutes) or 10) * 60000)
            updateActivityForOnlineJobs()
        end
    end)

    CreateThread(function()
        Wait(10000)
        -- Resource restarts do not re-fire esx:playerLoaded for players already online,
        -- so refresh active business jobs before the first repossession pass.
        updateActivityForOnlineJobs()
        while true do
            runInactivityCheck()
            Wait(math.max(1, tonumber(Config.Inactivity.CheckIntervalMinutes) or 60) * 60000)
        end
    end)
end)
