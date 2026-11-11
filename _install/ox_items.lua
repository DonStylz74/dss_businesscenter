-- Add the entries inside this returned table to ox_inventory/data/items.lua.
-- Copy the matching PNG files from install/images/ to ox_inventory/web/images/.

return {
    ['business_license'] = {
        label = 'Business License',
        weight = 2,
        stack = false,
        close = false,
        description = 'License to purchase and own a registered business.',
        client = {
            image = 'business_license.png',
        },
    },

    ['business_certificate'] = {
        label = 'Business Ownership Certificate',
        weight = 10,
        stack = false,
        close = true,
        consume = 0,
        description = 'Official purchase certificate issued by the Los Santos Business Center.',
        server = {
            export = 'dss_businesscenter.business_certificate'
        },
        client = {
            image = 'business_certificate.png',
        },
    },
}
