Config = {}

-- General
Config.Debug = false
Config.Locale = 'en'
Config.MaxBusinessesPerCharacter = 3
Config.RequireBusinessLicense = false
Config.BusinessLicenseItem = 'business_license'
Config.RequireConfiguredGradeToBeBoss = true -- validates that the selected ESX grade has grade name "boss"

-- Purchases are only accepted while the player is physically at the Business Centre NPC.
-- 'money' / 'cash' uses the ox_inventory cash item below. 'bank' uses the ESX bank account.
Config.CashItem = 'money'
Config.PurchaseAccount = 'money' -- 'bank' or 'money' (ox_inventory cash item)
Config.OwnerSalePayoutAccount = 'bank'
Config.DefaultJobAfterSale = { name = 'unemployed', grade = 0 }

-- Allows owners to switch their active ESX job between businesses from the Business Center UI.
-- Disable this when your server already uses a dedicated multi-job resource. Purchases still assign
-- the configured business job/grade as normal.
Config.MultiJob = {
    Enabled = true
}

-- Player-to-player listing must stay inside this percentage range of the configured/original business price.
Config.PlayerListing = {
    MinPercentage = 50,
    MaxPercentage = 80
}

Config.BusinessCenter = {
    PedModel = 'a_m_m_business_01',
    -- Example location. Change this to your chosen business centre location.
    PedCoords = vector4(-250.8928, -924.3846, 32.3433, 312.7000),
    TargetDistance = 2.5,
    ServerValidationDistance = 6.0,
    Scenario = 'WORLD_HUMAN_CLIPBOARD',

    EnableBlip = true,
    BlipCoords = vector3(-250.8928, -924.3846, 32.3433),
    BlipSprite = 476,
    BlipColor = 0,
    BlipScale = 0.5,
    BlipName = 'Los Santos Business Center'
}

Config.ForSaleSign = {
    DefaultModel = 'prop_forsale_sign_fs',
    Collision = true,
    Alpha = 255,
    PlacementAlpha = 155,
    PlacementMoveStep = 0.035,
    PlacementFastMultiplier = 4.0,
    PlacementRotateStep = 1.0,
    PlacementHeightStep = 0.02,
    TargetDistance = 2.5
}

-- Optional support for ZeroDazed AdvertBillboards. When enabled, these two addon prop names
-- are added to the Sign Prop Model suggestions in the in-game business creator. Custom model
-- names can still be typed manually. The advertbillboards resource itself is not required when false.
Config.ZeroDazedAdvertBillboards = {
    Enabled = true,
    Models = {
        'zero_advertisement_small',
        'zero_advertisement_large'
    }
}

Config.BusinessBlips = {
    ShowOnlyWhenForSale = false,
    DefaultScale = 0.65
}

Config.Certificate = {
    ItemName = 'business_certificate',
    ReplacementFee = 500,
    ReplacementFeeAccount = 'money',
    ShowDistance = 3.0,
    MissingCertificateSaleFeePercentage = 2.5
}

-- A business is considered active when any online player with that business job is seen by the activity heartbeat.
Config.Inactivity = {
    Enabled = true,
    Days = 30,
    RefundPercentage = 50,
    ActivityHeartbeatMinutes = 10,
    CheckIntervalMinutes = 60
}

Config.Admin = {
    Command = 'businessadmin',
    AcePermission = 'business.admin', -- server.cfg example: add_ace group.admin business.admin allow
    -- Optional ESX job/grade access in addition to ACE permission. Grade is the minimum numeric grade required.
    AllowedJobs = {
        -- { job = 'government', grade = 4 },
    },
    -- Used only when an admin explicitly chooses the refund option while removing an owner.
    RemovalRefundPercentage = 50
}

-- Optional one-time seed data. These are inserted only when the business table is completely empty.
-- Most servers can leave this empty and create businesses from the in-game admin UI.
Config.SeedBusinesses = {
    --[[
    {
        BusinessName = 'Los Santos Customs (Burton)',
        BusinessType = 'Mechanic Shop',
        Description = 'A fully operational mechanic business in Burton.',
        BusinessPrice = 1250000,
        BusinessJob = 'mechanic',
        BusinessGrade = 4,
        SellBackPercentage = 60,
        BusinessImage = 'assets/businesses/default-business.svg',
        SignModel = 'prop_forsale_sign_fs',
        SignCoords = vector4(-350.0, -133.0, 39.0, 70.0),
        EnableBlip = true,
        BlipCoords = vector3(-350.0, -133.0, 39.0),
        BlipSprite = 446,
        BlipColor = 5,
        BlipScale = 0.65,
        BlipName = 'Los Santos Customs (Burton)'
    }
    ]]
}
