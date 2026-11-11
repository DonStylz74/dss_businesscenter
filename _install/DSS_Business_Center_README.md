# DSS Business Center

![DSS Business Center](docs/dss_business_center_banner.png)

**A complete player-owned business marketplace and management system for FiveM ESX Legacy servers.**

DSS Business Center allows players to purchase configured businesses from a central Business Center NPC, become the registered owner and ESX boss, manage owned businesses, sell businesses back to the Business Center, or list businesses for sale to other players.

The resource also includes a full in-game business creator/editor, configurable for-sale props and blips, ownership certificates, inactivity protection, player resale listings, server-side ownership validation, and an optional ZeroDazed AdvertBillboards integration.

> Designed for **ESX Legacy + ox_lib + ox_inventory + ox_target + oxmysql**.

---

## Features

- Player-owned businesses with one registered owner per business.
- Configurable maximum number of businesses each character can own.
- Businesses can only be purchased from the configured Business Center NPC.
- Purchasing a business automatically assigns the configured ESX job and grade.
- Business ownership is tracked against the original purchaser's character identifier, not simply the ESX boss grade.
- Promoting another employee to `boss` does not give that employee authority to sell the business.
- Configurable instant sell-back percentage for each business.
- Player-to-player business listings with configurable minimum and maximum listing percentages.
- Seller proceeds can be paid even when the original seller is offline.
- Configurable missing-certificate sale fee.
- Configurable business ownership limit per character.
- Optional multi-job switching for owners with multiple businesses.
- Multi-job switching can be disabled when another multi-job resource is already installed.
- Business ownership certificates using ox_inventory metadata.
- Replacement certificates for current business owners.
- Ownership-cycle validation prevents old/stolen certificates from being reused.
- Expired certificates display an **EXPIRED** stamp and are removed when closed.
- For-sale signs automatically appear when a business is available to purchase.
- For-sale signs are removed automatically once a business is purchased.
- `ox_target` interaction on a for-sale sign displays business information.
- Purchases remain restricted to the Business Center NPC.
- Default GTA for-sale sign support.
- Optional ZeroDazed billboard prop support.
- Custom addon prop support.
- In-world ghost prop placement tool for positioning business signs.
- Manual coordinate entry is also supported.
- Optional configurable business blips with sprite, colour, name and scale.
- Business images shown inside the Business Center UI.
- Black/gold executive Business Center NUI.
- Businesses for Sale, My Businesses and Admin sections.
- Scrollable business lists and business information panels.
- Full in-game admin business creator/editor.
- Create, edit and delete businesses without editing Lua config files.
- Admin ownership removal tools.
- ACE permission and/or ESX job-grade admin access.
- `/businessadmin` command allows authorised staff to create a business while standing at the intended location.
- Configurable inactivity repossession system.
- Inactive businesses can automatically return to the market after the configured number of days.
- Configurable inactivity refund deposited to the registered owner's bank.
- Business purchase, sale, listing and administrative history stored in SQL.
- Server-side validation for ownership, money, business state, permissions, job/grade, ownership limits and Business Center proximity.

---

## Framework / Dependencies

Required resources:

```text
es_extended     - ESX Legacy
ox_lib
ox_inventory
ox_target
oxmysql
```

Recommended start order:

```cfg
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_target
ensure ox_inventory
ensure dss_businesscenter
```

Keep the resource folder named exactly:

```text
dss_businesscenter
```

The business certificate ox_inventory item references the resource export by this name.

---

## Money & Inventory Integration

DSS Business Center uses the following routing:

```text
Cash         -> ox_inventory money item
Bank         -> ESX bank account
Certificates -> ox_inventory
```

Default cash item:

```lua
Config.CashItem = 'money'
```

Business purchases can use the ox_inventory cash item:

```lua
Config.PurchaseAccount = 'money'
```

or ESX bank:

```lua
Config.PurchaseAccount = 'bank'
```

Owner sale payouts are normally sent to bank:

```lua
Config.OwnerSalePayoutAccount = 'bank'
```

Offline seller payments, inactivity refunds and pending payouts use the owner's bank account.

---

# Installation

## 1. Install the resource

Copy:

```text
dss_businesscenter
```

into your FiveM resources folder.

Add to `server.cfg`:

```cfg
ensure dss_businesscenter
```

---

## 2. Install ox_inventory items

Open:

```text
dss_businesscenter/install/ox_items.lua
```

Add the included item definitions to:

```text
ox_inventory/data/items.lua
```

The package contains definitions for:

```text
business_license
business_certificate
```

If your server already has a `business_license` item, keep your existing item and only add the business certificate if required.

Copy the included inventory images from:

```text
dss_businesscenter/install/images/
```

to:

```text
ox_inventory/web/images/
```

---

## 3. Database

The required SQL tables are automatically created when the resource starts.

A manual SQL file is also supplied:

```text
dss_businesscenter/install/dss_businesscenter.sql
```

Use this only if you prefer to create/import the tables manually.

The resource stores:

```text
dss_businesses         - business configuration, ownership and listing state
dss_business_history   - purchase/sale/listing/admin audit history
dss_business_payouts   - fallback pending offline payouts
```

---

## 4. Configure the Business Center NPC

Edit `config.lua`:

```lua
Config.BusinessCenter = {
    PedModel = 'a_m_m_business_01',
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
```

Change the coordinates and blip settings to suit your server.

---

## 5. Admin permissions

The admin creator/editor can be opened with:

```text
/businessadmin
```

Default ACE permission:

```lua
Config.Admin.AcePermission = 'business.admin'
```

Example `server.cfg` permission:

```cfg
add_ace group.admin business.admin allow
```

You can also allow ESX jobs/grades:

```lua
Config.Admin.AllowedJobs = {
    { job = 'government', grade = 4 },
}
```

Both permission methods can be used at the same time.

---

# Business Creator / Editor

The in-game creator allows authorised administrators to create businesses without manually editing Lua files or SQL entries.

Required business information includes:

```text
Business Name
Business Price
ESX Job
ESX Owner Grade
Sell Back Percentage
For-Sale Sign Model
For-Sale Sign Coordinates
```

Optional information includes:

```text
Business Type
Description
Business Image
Business Blip
Blip Coordinates
Blip Sprite
Blip Colour
Blip Size
Blip Name
```

The business job must already exist in ESX.

When this option is enabled:

```lua
Config.RequireConfiguredGradeToBeBoss = true
```

the selected ESX grade must have the grade name:

```text
boss
```

The grade number itself may be different for every job.

---

## Sign Placement Tool

The creator includes a visual prop placement mode.

Press the placement button and a transparent/ghosted copy of the selected sign appears in the world.

Controls:

```text
Arrow Up / Down       Move forward / backward
Arrow Left / Right    Move left / right
Q / E                 Rotate
Page Up / Page Down   Raise / lower
G                     Snap to ground
Shift                 Faster movement / rotation
Enter                 Accept position
Backspace / Escape    Cancel
```

The editor stores sign coordinates as:

```text
x, y, z, heading
```

Pasted `vec4(...)` coordinates are also accepted.

---

# For-Sale Props

The standard GTA V sign model is:

```text
prop_forsale_sign_fs
```

When ZeroDazed AdvertBillboards support is enabled, the creator also offers:

```text
zero_advertisement_small
zero_advertisement_large
```

> **Important:** prop model names must not include `.ydr`.
>
> `zero_advertisement_small.ydr` is the streamed model filename.
>
> The model name entered in the Business Center creator is `zero_advertisement_small`.

Enable the addon options with:

```lua
Config.ZeroDazedAdvertBillboards = {
    Enabled = true,
    Models = {
        'zero_advertisement_small',
        'zero_advertisement_large'
    }
}
```

When disabled, only the normal GTA for-sale sign is offered by default. Custom prop models can still be entered manually.

---

# ZeroDazed AdvertBillboards Installation

DSS Business Center supports the free **ZeroDazed Advert Billboards** prop package.

**ZeroDazed Advert Billboards:**  
https://forum.cfx.re/t/free-prop-billboard-prop-pack

There are **two supported installation methods**.

## Method 1 — Run ZeroDazed AdvertBillboards as a Separate Resource

Use this method if you want to keep the original ZeroDazed AdvertBillboards package running independently from DSS Business Center.

1. Install and ensure the ZeroDazed AdvertBillboards resource normally.
2. Locate:

```text
dss_businesscenter/install/advertbillboards/zero_advertisement_small.ydr
```

3. Copy that file into the ZeroDazed AdvertBillboards resource:

```text
ZeroDazedAdvertBillboards/stream/
```

4. Replace/overwrite the existing:

```text
zero_advertisement_small.ydr
```

5. Keep both resources enabled:

```cfg
ensure ZeroDazedAdvertBillboards
ensure dss_businesscenter
```

This method keeps the billboard props in their own resource while replacing the small billboard texture/model with the DSS Business Center **Business For Sale** version.

---

## Method 2 — Run Everything as a Single DSS Business Center Resource

Use this method if you do not want to run ZeroDazed AdvertBillboards as a separate resource.

1. Download the ZeroDazed AdvertBillboards package from the link above.
2. Copy the entire:

```text
stream
```

folder from the ZeroDazed AdvertBillboards package.
3. Paste that `stream` folder directly into:

```text
dss_businesscenter/
```

4. Open:

```text
dss_businesscenter/install/advertbillboards/
```

5. Copy the supplied:

```text
fxmanifest.lua
```

6. Paste it into the main:

```text
dss_businesscenter/
```

folder and overwrite the existing `fxmanifest.lua`.
7. Ensure only DSS Business Center:

```cfg
ensure dss_businesscenter
```

The billboard models will now stream directly from DSS Business Center and a separate ZeroDazed resource is not required.

### ZeroDazed configuration

After installing the billboard props using either method, enable them in `config.lua`:

```lua
Config.ZeroDazedAdvertBillboards.Enabled = true
```

The business creator will then provide:

```text
prop_forsale_sign_fs
zero_advertisement_small
zero_advertisement_large
```

---

# Business Blips

Each business can optionally have its own map blip.

The creator/editor supports:

```text
Enable / Disable
Coordinates
Sprite
Colour
Name
Size / Scale
```

Default business blip size:

```lua
Config.BusinessBlips.DefaultScale = 0.65
```

You can choose whether business blips are shown only while the business is available for sale:

```lua
Config.BusinessBlips.ShowOnlyWhenForSale = false
```

Set this to `true` if you only want business-sale locations visible while they are on the market.

---

# Business Images

Business images are displayed inside the Business Center UI.

Recommended location:

```text
dss_businesscenter/html/assets/businesses/
```

Example:

```text
dss_businesscenter/html/assets/businesses/carwash.png
```

Enter this into the Business Image field:

```text
assets/businesses/carwash.png
```

Recommended formats:

```text
.png
.jpg / .jpeg
.webp
```

PNG is recommended for GTA-style business artwork.

---

# Purchasing a Business

A business can only be purchased through the Business Center NPC.

When the purchase succeeds:

1. The character becomes the registered business owner.
2. The configured purchase price is removed.
3. The player's ESX job is changed to the configured business job and grade.
4. The for-sale sign is removed.
5. The business is marked as owned in SQL.
6. An ownership-cycle token is created.
7. A Business Ownership Certificate is issued through ox_inventory.
8. The purchase is recorded in business history.

Ownership authority remains tied to the original purchasing character identifier.

---

# Selling a Business

Owners have two sale options.

## Instant Sale to the Business Center

Each business has its own configured sell-back percentage.

Example:

```text
Original price: $1,000,000
Sell-back:      60%
Owner receives: $600,000
```

The payout is sent using the configured owner sale payout account.

## Player Listing

Owners can list a business for another player to purchase.

Allowed listing percentages are configured globally:

```lua
Config.PlayerListing = {
    MinPercentage = 50,
    MaxPercentage = 80
}
```

The business returns to the market, the for-sale sign appears, and another player can purchase it from the Business Center NPC.

When sold, the original seller receives the listing proceeds to their bank account.

---

# Business Certificates

Every successful business purchase issues a unique Business Ownership Certificate.

The certificate contains ownership and business information and is tied to the current ownership cycle.

Using the certificate displays the certificate to the holder and nearby player where applicable.

A current owner can request a replacement certificate from the Business Center.

Default replacement fee:

```lua
Config.Certificate.ReplacementFee = 500
Config.Certificate.ReplacementFeeAccount = 'money'
```

Issuing a replacement certificate invalidates the previous certificate.

If an old/stolen certificate is later used, it displays:

```text
EXPIRED
```

and is removed from the inventory when the expired certificate is closed.

---

## Selling Without a Valid Certificate

The resource can allow the registered owner to continue a sale without their valid certificate by paying a percentage fee.

Default:

```lua
Config.Certificate.MissingCertificateSaleFeePercentage = 2.5
```

Before the sale continues, the UI displays:

```text
Normal sale value
Certificate fee
Final amount owner will receive
```

The owner can cancel, retrieve the correct certificate and restart the sale instead.

---

# Multi-Business / Multi-Job Support

The maximum number of businesses each character can own is configurable:

```lua
Config.MaxBusinessesPerCharacter = 3
```

DSS Business Center can also allow an owner to switch their active ESX job between businesses they personally own:

```lua
Config.MultiJob.Enabled = true
```

If your server already uses another multi-job resource, disable this feature:

```lua
Config.MultiJob.Enabled = false
```

Purchasing a business will still assign the configured business job and owner grade. Only the optional job-switching controls inside the Business Center UI are disabled.

---

# Inactivity Protection / Business Repossession

The resource can automatically return inactive businesses to the market.

Default configuration:

```lua
Config.Inactivity = {
    Enabled = true,
    Days = 30,
    RefundPercentage = 50,
    ActivityHeartbeatMinutes = 10,
    CheckIntervalMinutes = 60
}
```

A business is considered active when an online player is detected actively using that business job.

If the configured inactivity period is reached:

1. Ownership is removed.
2. The business is returned to the market.
3. The for-sale sign becomes available again.
4. The configured percentage of the business purchase price is deposited to the registered owner's bank account.
5. The repossession is recorded in the audit history.

---

# Security / Ownership Validation

DSS Business Center does not use the player's current ESX boss grade as proof of ownership.

The registered purchaser is stored separately against the business ownership record.

This means another employee can safely be promoted to the business `boss` grade without gaining permission to sell or list the business.

Sensitive actions are validated server-side, including:

```text
Business ownership
Business availability
Original owner identifier
Money / bank balance
Ownership limit
Configured ESX job and grade
Admin permissions
Business Center purchase proximity
Certificate ownership cycle
Listing state
```

---

# Important Configuration Examples

## Maximum owned businesses

```lua
Config.MaxBusinessesPerCharacter = 3
```

## Require a business licence

```lua
Config.RequireBusinessLicense = true
Config.BusinessLicenseItem = 'business_license'
```

## Cash item

```lua
Config.CashItem = 'money'
```

## Purchase using cash

```lua
Config.PurchaseAccount = 'money'
```

## Purchase using bank

```lua
Config.PurchaseAccount = 'bank'
```

## Owner sale payout

```lua
Config.OwnerSalePayoutAccount = 'bank'
```

## Disable DSS multi-job switching

```lua
Config.MultiJob.Enabled = false
```

## Enable ZeroDazed props

```lua
Config.ZeroDazedAdvertBillboards.Enabled = true
```

## Default business blip scale

```lua
Config.BusinessBlips.DefaultScale = 0.65
```

---

# Troubleshooting

### Addon billboard says `invalid prop model`

Make sure the streamed model files are installed and that the model name entered in the creator does **not** contain `.ydr`.

Correct:

```text
zero_advertisement_small
```

Incorrect:

```text
zero_advertisement_small.ydr
```

### Business image does not display

Check that the image exists under:

```text
html/assets/businesses/
```

and that the editor path is relative to the `html` folder, for example:

```text
assets/businesses/carwash.png
```

### Purchase says the job/grade is invalid

Confirm the job and grade exist in your ESX `jobs` / `job_grades` tables.

If:

```lua
Config.RequireConfiguredGradeToBeBoss = true
```

is enabled, the selected grade's internal grade name must be `boss`.

### Player cannot switch to another owned business job

Check:

```lua
Config.MultiJob.Enabled
```

If set to `false`, job switching is intentionally disabled so another multi-job resource can handle that function.

### Business blip is not visible

Check the business itself has blips enabled and review:

```lua
Config.BusinessBlips.ShowOnlyWhenForSale
```

If set to `true`, owned businesses will not display their business blip.

---

# Suggested GitHub Banner Setup

For the supplied DSS Business Center promotional image, place the banner at:

```text
docs/dss_business_center_banner.png
```

The image at the top of this README will then display automatically on GitHub.

For Tebex, upload the promotional image through the Tebex product/gallery editor and use the feature overview from this README as the product description.

---

# Credits

**DSS / Don Stylz Skriptz**  
DSS Business Center

Optional billboard prop integration:

**ZeroDazed Advert Billboards**  
https://forum.cfx.re/t/free-prop-billboard-prop-pack

The ZeroDazed billboard pack remains the work of its original creator. DSS Business Center only provides optional integration/support for those prop models.

---

# Support Notes

When requesting support, provide:

```text
DSS Business Center version
ESX Legacy version
ox_inventory version
ox_lib version
ox_target version
oxmysql version
Server/client console error if applicable
Steps required to reproduce the issue
```

Do not post database credentials, server keys or other private server information in public support requests.

---

## Compatibility

Built for:

```text
FiveM
ESX Legacy
ox_lib
ox_inventory
ox_target
oxmysql
```

DSS Business Center is an independent FiveM server resource and is not affiliated with or endorsed by Rockstar Games or Take-Two Interactive.
