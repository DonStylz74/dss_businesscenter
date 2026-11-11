const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'dss_businesscenter';

const app = document.getElementById('app');
const content = document.getElementById('content');
const searchInput = document.getElementById('searchInput');
const modalRoot = document.getElementById('modalRoot');
const toastRoot = document.getElementById('toastRoot');
const certificateOverlay = document.getElementById('certificateOverlay');
const businessDetailsOverlay = document.getElementById('businessDetailsOverlay');
const businessDetailsContent = document.getElementById('businessDetailsContent');

const state = {
    open: false,
    placing: false,
    tab: 'sale',
    data: { businesses: [], canAdmin: false, ownedCount: 0, maxBusinesses: 0 },
    selectedId: null,
    search: '',
    adminEditing: false,
    adminEditId: null
};

let modalHandlers = {};

const esc = (value) => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

const money = (value) => `$${Math.max(0, Number(value) || 0).toLocaleString('en-US')}`;
const adminDateTime = (value) => {
    if (value === null || value === undefined || value === '') return '—';

    let date;
    if (typeof value === 'number' || /^\d+$/.test(String(value).trim())) {
        let timestamp = Number(value);
        if (!Number.isFinite(timestamp)) return String(value);
        if (timestamp < 1000000000000) timestamp *= 1000;
        date = new Date(timestamp);
    } else {
        const raw = String(value).trim();
        date = new Date(raw.includes('T') ? raw : raw.replace(' ', 'T'));
    }

    if (Number.isNaN(date.getTime())) return String(value);

    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
};
const imageFor = (business) => business?.image || 'assets/businesses/default-business.svg';
const salePrice = (business) => business?.status === 'listed' ? business.listingPrice : business?.price;
const statusLabel = (business) => business?.status === 'owned' ? 'Owned' : business?.status === 'listed' ? 'Owner Listed' : 'Business Center Sale';
const statusClass = (business) => business?.status === 'owned' ? 'green' : business?.status === 'listed' ? 'orange' : 'gold';

function nui(name, payload = {}) {
    return fetch(`https://${resourceName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
    }).then(r => r.json()).catch(() => ({ success: false, message: 'NUI request failed.' }));
}

function toast(type, message) {
    if (!message) return;
    const node = document.createElement('div');
    node.className = `toast ${type || 'inform'}`;
    node.innerHTML = `<strong>${type === 'error' ? 'Error' : type === 'success' ? 'Success' : type === 'warning' ? 'Notice' : 'Business Center'}</strong><span>${esc(message)}</span>`;
    toastRoot.appendChild(node);
    setTimeout(() => node.remove(), 4300);
}

function setData(data) {
    if (!data) return;
    state.data = data;
    document.getElementById('ownedCount').textContent = data.ownedCount ?? 0;
    document.getElementById('maxOwned').textContent = data.maxBusinesses ?? 0;
    const pct = Math.min(100, ((Number(data.ownedCount) || 0) / Math.max(1, Number(data.maxBusinesses) || 1)) * 100);
    document.getElementById('ownershipProgress').style.width = `${pct}%`;
    document.querySelector('.admin-nav').classList.toggle('hidden', !data.canAdmin);
    if (!data.canAdmin && state.tab === 'admin') state.tab = 'sale';
}

function filteredBusinesses(list) {
    const q = state.search.trim().toLowerCase();
    if (!q) return list;
    return list.filter(b => [b.name, b.businessType, b.jobLabel, b.job, b.ownerName, b.sellerName]
        .filter(Boolean).some(v => String(v).toLowerCase().includes(q)));
}

function pickSelection(items) {
    if (!items.length) {
        state.selectedId = null;
        return null;
    }
    const current = items.find(b => Number(b.id) === Number(state.selectedId));
    if (current) return current;
    state.selectedId = items[0].id;
    return items[0];
}

function businessRow(business, mode = 'sale') {
    const selected = Number(state.selectedId) === Number(business.id);
    const price = mode === 'sale' ? salePrice(business) : (business.status === 'listed' ? business.listingPrice : business.price);
    return `
        <div class="business-row ${selected ? 'active' : ''}" data-action="select-business" data-id="${Number(business.id)}">
            <img class="business-thumb" src="${esc(imageFor(business))}" onerror="this.onerror=null;this.src='assets/businesses/default-business.svg'" alt="" />
            <div class="row-copy">
                <div class="row-title">${esc(business.name)}</div>
                <div class="row-type">${esc(business.businessType || 'Commercial Business')} · ${esc(business.jobLabel || business.job)}</div>
                <div class="row-price">${money(price)}</div>
            </div>
            <div class="row-meta">
                <span class="pill ${statusClass(business)}">${esc(statusLabel(business))}</span>
                <div class="chevron">›</div>
            </div>
        </div>`;
}

function emptyState(title, text) {
    return `<div class="empty-state"><div><strong>${esc(title)}</strong><span>${esc(text)}</span></div></div>`;
}

function saleDetail(b) {
    if (!b) return emptyState('No businesses found', 'Try a different search or ask an administrator to create a business.');

    const isOwnListing = b.status === 'listed' && b.isSeller;
    const atLimit = Number(state.data.ownedCount) >= Number(state.data.maxBusinesses);
    const away = !state.data.nearBusinessCenter;
    const disablePurchase = isOwnListing || atLimit || away;
    let buttonText = `Buy Business · ${money(salePrice(b))}`;
    if (isOwnListing) buttonText = 'Your Listing — Manage in My Businesses';
    else if (atLimit) buttonText = 'Ownership Limit Reached';
    else if (away) buttonText = 'Purchase at the Business Center NPC';

    return `
        <img class="detail-image" src="${esc(imageFor(b))}" onerror="this.onerror=null;this.src='assets/businesses/default-business.svg'" alt="" />
        <div class="detail-title">${esc(b.name)}</div>
        <div class="detail-description">${esc(b.description || 'Commercial business opportunity registered with the Los Santos Business Center.')}</div>
        <div class="fact-list">
            <div class="fact"><span class="fact-icon">▣</span><span class="fact-label">Business Type</span><span class="fact-value">${esc(b.businessType)}</span></div>
            <div class="fact"><span class="fact-icon">♟</span><span class="fact-label">ESX Job</span><span class="fact-value">${esc(b.jobLabel || b.job)}</span></div>
            <div class="fact"><span class="fact-icon">★</span><span class="fact-label">Owner Grade</span><span class="fact-value">${esc(b.jobGradeLabel || 'Boss')}</span></div>
            <div class="fact"><span class="fact-icon">●</span><span class="fact-label">Sale Price</span><span class="fact-value">${money(salePrice(b))}</span></div>
            ${b.status === 'listed' ? `<div class="fact"><span class="fact-icon">↗</span><span class="fact-label">Original Business Price</span><span class="fact-value">${money(b.price)}</span></div>` : ''}
            <div class="fact"><span class="fact-icon">↶</span><span class="fact-label">Business Center Buyback</span><span class="fact-value">${Number(b.sellBackPercentage)}% · ${money(b.sellBackValue)}</span></div>
        </div>
        <div class="detail-actions">
            <button class="btn gold" data-action="purchase" data-id="${Number(b.id)}" ${disablePurchase ? 'disabled' : ''}>${esc(buttonText)}</button>
        </div>`;
}

function renderSale() {
    const items = filteredBusinesses((state.data.businesses || []).filter(b => b.status === 'for_sale' || b.status === 'listed'));
    const selected = pickSelection(items);
    content.innerHTML = `
        <section class="screen">
            <div class="screen-head">
                <div><div class="screen-title">BUSINESSES FOR SALE (${items.length})</div><div class="screen-subtitle">Purchase registered Los Santos businesses and become the configured ESX boss.</div></div>
                <span class="pill gold">INVEST · OWN · GROW</span>
            </div>
            <div class="gold-line"></div>
            <div class="market-grid">
                <div class="list-panel"><div class="list-scroll">${items.length ? items.map(b => businessRow(b, 'sale')).join('') : emptyState('No businesses currently for sale', 'New listings will appear here automatically.')}</div></div>
                <div class="detail-panel">${saleDetail(selected)}</div>
            </div>
        </section>`;
}

function ownedDetail(b) {
    if (!b) return emptyState('No owned businesses', 'Businesses you purchase or list for resale will appear here.');

    if (b.isSeller && b.status === 'listed') {
        return `
            <img class="detail-image" src="${esc(imageFor(b))}" onerror="this.onerror=null;this.src='assets/businesses/default-business.svg'" alt="" />
            <div class="detail-title">${esc(b.name)}</div>
            <div class="detail-description">This business has been released to the market. You remain the recorded seller and will receive the sale proceeds when another player purchases it.</div>
            <div class="fact-list">
                <div class="fact"><span class="fact-icon">↗</span><span class="fact-label">Listing Status</span><span class="fact-value">Owner Listed</span></div>
                <div class="fact"><span class="fact-icon">●</span><span class="fact-label">Listing Price</span><span class="fact-value">${money(b.listingPrice)}</span></div>
                ${Number(b.sellerCertificateFee) > 0 ? `<div class="fact"><span class="fact-icon">!</span><span class="fact-label">Certificate Fee on Sale</span><span class="fact-value">${money(b.sellerCertificateFee)} · Net ${money(Number(b.listingPrice) - Number(b.sellerCertificateFee))}</span></div>` : ''}
                <div class="fact"><span class="fact-icon">▣</span><span class="fact-label">Original Price</span><span class="fact-value">${money(b.price)}</span></div>
                <div class="fact"><span class="fact-icon">◷</span><span class="fact-label">Listed</span><span class="fact-value">${esc(b.listedAt || '—')}</span></div>
            </div>
            <div class="detail-actions"><button class="btn gold" data-action="cancel-listing" data-id="${Number(b.id)}">Cancel Listing & Restore Ownership</button></div>`;
    }

    const min = Math.floor(Number(b.price) * (Number(state.data.listingMinPercentage) / 100));
    const max = Math.floor(Number(b.price) * (Number(state.data.listingMaxPercentage) / 100));
    return `
        <img class="detail-image" src="${esc(imageFor(b))}" onerror="this.onerror=null;this.src='assets/businesses/default-business.svg'" alt="" />
        <div class="detail-title">${esc(b.name)}</div>
        <div class="detail-description">Owned by you. Only your recorded purchaser identifier can sell or list this business, even if another employee is promoted to boss.</div>
        <div class="fact-list">
            <div class="fact"><span class="fact-icon">♟</span><span class="fact-label">ESX Job</span><span class="fact-value">${esc(b.jobLabel || b.job)}</span></div>
            <div class="fact"><span class="fact-icon">★</span><span class="fact-label">Owner Grade</span><span class="fact-value">${esc(b.jobGradeLabel || 'Boss')}</span></div>
            <div class="fact"><span class="fact-icon">●</span><span class="fact-label">Your Purchase Price</span><span class="fact-value">${money(b.purchasePrice || b.price)}</span></div>
            <div class="fact"><span class="fact-icon">↶</span><span class="fact-label">Instant Buyback</span><span class="fact-value">${money(b.sellBackValue)} (${Number(b.sellBackPercentage)}%)</span></div>
            <div class="fact"><span class="fact-icon">↗</span><span class="fact-label">Private Listing Range</span><span class="fact-value">${money(min)} – ${money(max)}</span></div>
            <div class="fact"><span class="fact-icon">◷</span><span class="fact-label">Last Business Activity</span><span class="fact-value">${esc(b.lastActive || '—')}</span></div>
        </div>
        <div class="detail-actions">
            <div class="action-row">
                ${state.data.multiJobEnabled ? `<button class="btn ghost" data-action="set-job" data-id="${Number(b.id)}">Set Active Job</button>` : ''}
                <button class="btn ghost" data-action="replace-certificate" data-id="${Number(b.id)}">Replacement Certificate · ${money(state.data.replacementFee)}</button>
            </div>
            <div class="action-row">
                <button class="btn" data-action="list-business" data-id="${Number(b.id)}">List for Player Sale</button>
                <button class="btn danger" data-action="sell-instant" data-id="${Number(b.id)}">Sell to Business Center · ${money(b.sellBackValue)}</button>
            </div>
        </div>`;
}

function renderOwned() {
    const items = filteredBusinesses((state.data.businesses || []).filter(b => b.isOwner || b.isSeller));
    const selected = pickSelection(items);
    content.innerHTML = `
        <section class="screen">
            <div class="screen-head">
                <div><div class="screen-title">MY BUSINESSES (${items.length})</div><div class="screen-subtitle">Manage owned businesses, certificates, resale and private listings${state.data.multiJobEnabled ? ', including active-job switching' : ''}.</div></div>
                <span class="pill ${Number(state.data.ownedCount) >= Number(state.data.maxBusinesses) ? 'orange' : 'green'}">${Number(state.data.ownedCount)} / ${Number(state.data.maxBusinesses)} OWNED</span>
            </div>
            <div class="gold-line"></div>
            <div class="market-grid">
                <div class="list-panel"><div class="list-scroll">${items.length ? items.map(b => businessRow(b, 'owned')).join('') : emptyState('You do not own a business', 'Purchase one from the Businesses for Sale tab.')}</div></div>
                <div class="detail-panel">${ownedDetail(selected)}</div>
            </div>
        </section>`;
}

function adminRow(b) {
    return `
        <div class="admin-row ${Number(state.selectedId) === Number(b.id) ? 'active' : ''}" data-action="admin-select" data-id="${Number(b.id)}">
            <div class="admin-row-top"><div class="admin-row-name">${esc(b.name)}</div><span class="pill ${statusClass(b)}">${esc(statusLabel(b))}</span></div>
            <div class="admin-row-sub"><span>${esc(b.job)} · grade ${Number(b.jobGrade)}</span><span>${money(salePrice(b) || b.price)}</span></div>
        </div>`;
}

function vec4Text(coords) {
    if (!coords) return '';
    const n = v => Number(v || 0).toFixed(4);
    return `vec4(${n(coords.x)}, ${n(coords.y)}, ${n(coords.z)}, ${n(coords.w)})`;
}

function plainVec4Text(coords) {
    if (!coords) return '';
    const n = v => Number(v || 0).toFixed(4);
    return `${n(coords.x)}, ${n(coords.y)}, ${n(coords.z)}, ${n(coords.w)}`;
}

function plainVec3Text(coords) {
    if (!coords || coords.x == null || coords.y == null || coords.z == null) return '';
    const n = v => Number(v || 0).toFixed(4);
    return `${n(coords.x)}, ${n(coords.y)}, ${n(coords.z)}`;
}

function cleanPropModelName(model) {
    let value = String(model || '').trim();
    while (/\.ydr$/i.test(value)) value = value.replace(/\.ydr$/i, '').trim();
    return value.replace(/\.+$/, '');
}

function emptyAdminBusiness() {
    return {
        name: '', businessType: '', description: '', price: 0, job: '', jobGrade: 0,
        sellBackPercentage: 60, image: 'assets/businesses/default-business.svg',
        signModel: 'prop_forsale_sign_fs', signCoords: null, enableBlip: false,
        blipCoords: null, blipSprite: 475, blipColor: 5,
        blipScale: Number(state.data.defaultBlipScale) || 0.65, blipName: ''
    };
}

function adminForm(b) {
    const configuredSignModels = (state.data.signModels || ['prop_forsale_sign_fs'])
        .map(cleanPropModelName)
        .filter(Boolean);
    const currentSignModel = cleanPropModelName(b.signModel || 'prop_forsale_sign_fs');
    const currentIsConfigured = configuredSignModels.includes(currentSignModel);
    const signModelOptions = configuredSignModels
        .map(model => `<option value="${esc(model)}" ${currentSignModel === model ? 'selected' : ''}>${esc(model)}</option>`)
        .join('');
    const blipScale = Number.isFinite(Number(b.blipScale)) ? Number(b.blipScale) : (Number(state.data.defaultBlipScale) || 0.65);
    return `
        <div class="admin-summary">
            <div><h2>${state.adminEditId ? `Edit ${esc(b.name)}` : 'Create New Business'}</h2><p>Configure the business registration, ESX boss assignment, sale sign and optional map blip.</p></div>
            <span class="pill gold">${state.adminEditId ? `ID ${Number(state.adminEditId)}` : 'NEW'}</span>
        </div>

        <div class="form-section">
            <div class="form-section-title">Business Registration <span>Required</span></div>
            <div class="form-grid">
                <div class="field"><label>Business Name</label><input id="adminName" maxlength="80" value="${esc(b.name)}" placeholder="Los Santos Customs (Burton)" /></div>
                <div class="field"><label>Business Type</label><input id="adminType" maxlength="60" value="${esc(b.businessType)}" placeholder="Mechanic Shop" /></div>
                <div class="field full"><label>Description</label><textarea id="adminDescription" maxlength="600" placeholder="Short description shown in the Business Center.">${esc(b.description)}</textarea></div>
                <div class="field"><label>Original Business Price</label><input id="adminPrice" type="number" min="1" step="1" value="${Number(b.price) || 0}" /></div>
                <div class="field"><label>Sell Back Percentage</label><input id="adminSellBack" type="number" min="0" max="100" step="1" value="${Number(b.sellBackPercentage) || 0}" /></div>
                <div class="field"><label>ESX Job</label><input id="adminJob" maxlength="50" value="${esc(b.job)}" placeholder="mechanic" /></div>
                <div class="field"><label>ESX Boss Grade Number</label><input id="adminGrade" type="number" min="0" step="1" value="${Number(b.jobGrade) || 0}" /><span class="field-hint">The server validates that this grade exists and is named <b>boss</b> when boss validation is enabled.</span></div>
                <div class="field full"><label>Business Image</label><input id="adminImage" maxlength="255" value="${esc(b.image)}" placeholder="assets/businesses/my-business.png" /><span class="field-hint">Place local images in html/assets/businesses/ or use an allowed image URL.</span></div>
            </div>
        </div>

        <div class="form-section">
            <div class="form-section-title">For Sale Sign <span>Required</span></div>
            <div class="form-grid">
                <div class="field"><label>Sign Prop Model</label>
                    <select id="adminSignModelSelect">
                        ${signModelOptions}
                        <option value="__custom__" ${currentIsConfigured ? '' : 'selected'}>Custom prop model...</option>
                    </select>
                    <input id="adminSignModelCustom" class="${currentIsConfigured ? 'hidden' : ''}" maxlength="80" value="${currentIsConfigured ? '' : esc(currentSignModel)}" placeholder="custom_prop_model" />
                    <span class="field-hint">Select a configured sign prop. Choose Custom prop model to enter any other model name.</span>
                </div>
                <div class="field"><label>Manual Sign Coordinates (x, y, z, h)</label>
                    <div class="inline-field"><input id="adminSignCoords" value="${esc(plainVec4Text(b.signCoords))}" placeholder="0.0000, 0.0000, 0.0000, 0.0000" /><button class="btn gold" data-action="start-placement">Placement Tool</button></div>
                    <span class="field-hint">Use x, y, z, heading. Pasted vec4(...) data is also accepted. The placement tool writes the save-ready numeric format.</span>
                </div>
            </div>
        </div>

        <div class="form-section">
            <div class="form-section-title">Map Blip <label class="toggle"><input id="adminEnableBlip" type="checkbox" ${b.enableBlip ? 'checked' : ''}><span></span></label></div>
            <div class="form-grid">
                <div class="field full"><label>Blip Coordinates (x, y, z)</label><input id="adminBlipCoords" value="${esc(plainVec3Text(b.blipCoords))}" placeholder="0.0, 0.0, 0.0 — blank uses sign coordinates" /><span class="field-hint">Enter coordinates as x, y, z. Pasted vec3(...) values are also accepted.</span></div>
                <div class="field"><label>Blip Sprite</label><input id="adminBlipSprite" type="number" value="${Number(b.blipSprite) || 475}" /></div>
                <div class="field"><label>Blip Color</label><input id="adminBlipColor" type="number" value="${Number(b.blipColor) || 5}" /></div>
                <div class="field"><label>Blip Size</label><input id="adminBlipScale" type="number" min="0.10" max="5.00" step="0.05" value="${blipScale}" /><span class="field-hint">Default size is ${Number(state.data.defaultBlipScale) || 0.65}.</span></div>
                <div class="field"><label>Blip Name</label><input id="adminBlipName" maxlength="80" value="${esc(b.blipName || b.name)}" placeholder="Defaults to business name" /></div>
            </div>
        </div>

        <div class="form-footer">
            <button class="btn ghost" data-action="admin-cancel-edit">Cancel</button>
            <button class="btn gold" data-action="admin-save">Save Business</button>
        </div>`;
}

function adminSummary(b) {
    if (!b) return emptyState('No businesses configured', 'Select Create Business to register the first business.');
    const ownerSection = b.status === 'owned' ? `
        <div class="admin-owner">
            <span class="pill green">CURRENT OWNER</span>
            <div class="admin-owner-grid">
                <div><span>Name</span>${esc(b.ownerName || 'Unknown')}</div>
                <div><span>Character Identifier</span>${esc(b.ownerIdentifier || 'Unavailable')}</div>
                <div><span>Character Slot</span>${esc(b.ownerCharacterSlot ?? '—')}</div>
                <div><span>Last Active</span>${esc(adminDateTime(b.lastActive))}</div>
            </div>
        </div>` : b.status === 'listed' ? `
        <div class="admin-owner">
            <span class="pill orange">PLAYER LISTING</span>
            <div class="admin-owner-grid">
                <div><span>Seller</span>${esc(b.sellerName || 'Unknown')}</div>
                <div><span>Seller Identifier</span>${esc(b.sellerIdentifier || 'Unavailable')}</div>
                <div><span>Listing Price</span>${money(b.listingPrice)}</div>
                <div><span>Listed At</span>${esc(b.listedAt || '—')}</div>
            </div>
        </div>` : '';

    return `
        <div class="admin-summary">
            <div><h2>${esc(b.name)}</h2><p>${esc(b.description || 'No description set.')}</p></div>
            <span class="pill ${statusClass(b)}">${esc(statusLabel(b))}</span>
        </div>
        ${ownerSection}
        <div class="fact-list" style="margin-top:14px">
            <div class="fact"><span class="fact-icon">▣</span><span class="fact-label">Business Type</span><span class="fact-value">${esc(b.businessType)}</span></div>
            <div class="fact"><span class="fact-icon">●</span><span class="fact-label">Original Price</span><span class="fact-value">${money(b.price)}</span></div>
            <div class="fact"><span class="fact-icon">♟</span><span class="fact-label">Job / Boss Grade</span><span class="fact-value">${esc(b.jobLabel || b.job)} · ${esc(b.jobGradeLabel || b.jobGrade)}</span></div>
            <div class="fact"><span class="fact-icon">↶</span><span class="fact-label">Sell Back</span><span class="fact-value">${Number(b.sellBackPercentage)}% · ${money(b.sellBackValue)}</span></div>
            <div class="fact"><span class="fact-icon">⌖</span><span class="fact-label">Sign Prop</span><span class="fact-value">${esc(b.signModel)}</span></div>
            <div class="fact"><span class="fact-icon">⌖</span><span class="fact-label">Sign Coordinates</span><span class="fact-value">${esc(vec4Text(b.signCoords))}</span></div>
        </div>
        <div class="admin-action-strip">
            <button class="btn gold" data-action="admin-edit" data-id="${Number(b.id)}">Edit Business</button>
            ${b.status === 'owned' ? `<button class="btn danger" data-action="admin-remove-owner" data-id="${Number(b.id)}">Remove Owner</button>` : ''}
            ${b.status === 'listed' ? `<button class="btn danger" data-action="admin-clear-listing" data-id="${Number(b.id)}">Clear Player Listing</button>` : ''}
            <button class="btn danger" data-action="admin-delete" data-id="${Number(b.id)}">Delete Business</button>
        </div>`;
}

function renderAdmin() {
    if (!state.data.canAdmin) {
        state.tab = 'sale';
        render();
        return;
    }

    const items = filteredBusinesses(state.data.businesses || []);
    const selected = state.adminEditing ? null : pickSelection(items);
    let formBusiness = emptyAdminBusiness();
    if (state.adminEditing && state.adminEditId) {
        formBusiness = (state.data.businesses || []).find(b => Number(b.id) === Number(state.adminEditId)) || formBusiness;
    }

    content.innerHTML = `
        <section class="screen">
            <div class="screen-head">
                <div><div class="screen-title">BUSINESS ADMINISTRATION</div><div class="screen-subtitle">Create, edit and retire business registrations. Owner authority remains identifier-based.</div></div>
                <span class="pill gold">ADMIN ACCESS</span>
            </div>
            <div class="gold-line"></div>
            <div class="admin-layout">
                <div class="admin-list">
                    <div class="admin-list-toolbar"><button class="btn gold" data-action="admin-create">+ Create Business</button></div>
                    <div class="admin-business-list">${items.length ? items.map(adminRow).join('') : emptyState('No businesses', 'Create a business to begin.')}</div>
                </div>
                <div class="admin-main">${state.adminEditing ? adminForm(formBusiness) : adminSummary(selected)}</div>
            </div>
        </section>`;
}

function render() {
    document.querySelectorAll('[data-tab]').forEach(btn => btn.classList.toggle('active', btn.dataset.tab === state.tab));
    if (state.tab === 'owned') renderOwned();
    else if (state.tab === 'admin') renderAdmin();
    else renderSale();
}

function parseVector(text, count) {
    const matches = String(text || '').match(/-?\d+(?:\.\d+)?/g);
    if (!matches || matches.length < count) return null;
    const nums = matches.slice(0, count).map(Number);
    if (nums.some(v => Number.isNaN(v))) return null;
    return count === 4 ? { x: nums[0], y: nums[1], z: nums[2], w: nums[3] } : { x: nums[0], y: nums[1], z: nums[2], w: 0 };
}

function getAdminSignModel() {
    const select = document.getElementById('adminSignModelSelect');
    if (!select) return 'prop_forsale_sign_fs';
    if (select.value === '__custom__') {
        return cleanPropModelName(document.getElementById('adminSignModelCustom')?.value || '');
    }
    return cleanPropModelName(select.value);
}

function collectAdminForm() {
    const signCoords = parseVector(document.getElementById('adminSignCoords')?.value, 4);
    if (!signCoords) return { error: 'Valid sign coordinates are required (x, y, z, heading).' };
    const blipText = document.getElementById('adminBlipCoords')?.value?.trim();
    const blipCoords = blipText ? parseVector(blipText, 3) : null;
    if (blipText && !blipCoords) return { error: 'Blip coordinates must be valid x, y, z coordinates.' };

    return {
        payload: {
            name: document.getElementById('adminName')?.value,
            business_type: document.getElementById('adminType')?.value,
            description: document.getElementById('adminDescription')?.value,
            price: Number(document.getElementById('adminPrice')?.value),
            job: document.getElementById('adminJob')?.value,
            job_grade: Number(document.getElementById('adminGrade')?.value),
            sell_back_percentage: Number(document.getElementById('adminSellBack')?.value),
            image: document.getElementById('adminImage')?.value,
            sign_model: getAdminSignModel(),
            sign_coords: signCoords,
            enable_blip: document.getElementById('adminEnableBlip')?.checked === true,
            blip_coords: blipCoords,
            blip_sprite: Number(document.getElementById('adminBlipSprite')?.value),
            blip_color: Number(document.getElementById('adminBlipColor')?.value),
            blip_scale: Number(document.getElementById('adminBlipScale')?.value),
            blip_name: document.getElementById('adminBlipName')?.value
        }
    };
}

async function runAction(name, payload, successTab = null) {
    const result = await nui(name, payload);
    toast(result.success ? 'success' : 'error', result.message || (result.success ? 'Completed.' : 'Action failed.'));
    if (result.success && result.data) {
        setData(result.data);
        if (result.selectedId) state.selectedId = result.selectedId;
        if (successTab) state.tab = successTab;
        render();
    }
    return result;
}

function showModal(title, body, buttons) {
    modalHandlers = {};
    const buttonHtml = buttons.map((button, index) => {
        const key = `m${index}`;
        modalHandlers[key] = button.onClick;
        return `<button class="btn ${button.className || ''}" data-modal-action="${key}">${esc(button.label)}</button>`;
    }).join('');

    modalRoot.innerHTML = `
        <div class="modal-backdrop">
            <div class="modal">
                <div class="modal-head">${esc(title)}</div>
                <div class="modal-body">${body}</div>
                <div class="modal-actions"><button class="btn ghost" data-modal-action="cancel">Cancel</button>${buttonHtml}</div>
            </div>
        </div>`;
}

function closeModal() {
    modalRoot.innerHTML = '';
    modalHandlers = {};
}

function confirmPurchase(b) {
    showModal('Purchase Business', `Purchase <b>${esc(b.name)}</b> for <b>${money(salePrice(b))}</b>?<br><br>You will become the configured ESX boss and receive a business ownership certificate.`, [
        { label: `Purchase · ${money(salePrice(b))}`, className: 'gold', onClick: async () => { closeModal(); await runAction('purchase', { id: b.id }); } }
    ]);
}


async function showInstantSaleModal(b) {
    const preflight = await nui('salePreflight', { id: b.id, mode: 'instant' });
    if (!preflight.success) return toast('error', preflight.message || 'Unable to validate the sale.');

    if (preflight.hasValidCertificate) {
        showModal('Sell Business to Business Center', `A valid ownership certificate was found.<br><br>Sell <b>${esc(b.name)}</b> immediately for <b>${money(preflight.net)}</b>?<br><br>The certificate will be removed when the sale completes. This cannot be undone.`, [
            { label: `Sell · ${money(preflight.net)}`, className: 'danger', onClick: async () => { closeModal(); await runAction('sellInstant', { id: b.id, acceptMissingCertificateFee: false }); } }
        ]);
        return;
    }

    showModal('Business Certificate Not Found', `No valid ownership certificate for <b>${esc(b.name)}</b> was found in your inventory.<br><br>
        You can cancel, place the valid certificate into your inventory, and restart the sale; or continue now with a <b>${Number(preflight.feePercentage)}%</b> missing-certificate fee.<br><br>
        <div class="list-price-box">
            <div style="display:flex;justify-content:space-between"><span>Normal sale total</span><b>${money(preflight.gross)}</b></div>
            <div style="display:flex;justify-content:space-between;margin-top:8px"><span>Certificate fee</span><b>− ${money(preflight.fee)}</b></div>
            <div style="display:flex;justify-content:space-between;margin-top:10px;color:#f0bf4f"><span>New sale total</span><b>${money(preflight.net)}</b></div>
        </div>`, [
        { label: `Continue Sale · ${money(preflight.net)}`, className: 'danger', onClick: async () => { closeModal(); await runAction('sellInstant', { id: b.id, acceptMissingCertificateFee: true }); } }
    ]);
}

function showListingModal(b) {
    const min = Math.floor(Number(b.price) * (Number(state.data.listingMinPercentage) / 100));
    const max = Math.floor(Number(b.price) * (Number(state.data.listingMaxPercentage) / 100));
    const initial = Math.floor((min + max) / 2);
    const body = `
        Release <b>${esc(b.name)}</b> back to the public market and set a private sale price.<br>
        Your ownership and active business job end when the listing is created. You will be paid when another player buys it.
        <div class="list-price-box">
            <div style="display:flex;justify-content:space-between"><span>${money(min)}</span><b id="listingDisplay">${money(initial)}</b><span>${money(max)}</span></div>
            <input id="listingRange" type="range" min="${min}" max="${max}" value="${initial}" step="1" />
            <div class="list-price-number"><span>$</span><input id="listingNumber" type="number" min="${min}" max="${max}" value="${initial}" /></div>
        </div>`;

    showModal('List Business for Player Sale', body, [
        { label: 'Create Listing', className: 'gold', onClick: async () => {
            const price = Number(document.getElementById('listingNumber')?.value);
            const preflight = await nui('salePreflight', { id: b.id, mode: 'listing', price });
            if (!preflight.success) return toast('error', preflight.message || 'Unable to validate the listing.');

            if (preflight.hasValidCertificate) {
                closeModal();
                await runAction('listForSale', { id: b.id, price, acceptMissingCertificateFee: false });
                return;
            }

            closeModal();
            showModal('Business Certificate Not Found', `No valid ownership certificate for <b>${esc(b.name)}</b> was found in your inventory.<br><br>
                Cancel to place the valid certificate into your inventory and restart the listing, or continue with the <b>${Number(preflight.feePercentage)}%</b> fee deducted when the business sells.<br><br>
                <div class="list-price-box">
                    <div style="display:flex;justify-content:space-between"><span>Listing price</span><b>${money(preflight.gross)}</b></div>
                    <div style="display:flex;justify-content:space-between;margin-top:8px"><span>Certificate fee</span><b>− ${money(preflight.fee)}</b></div>
                    <div style="display:flex;justify-content:space-between;margin-top:10px;color:#f0bf4f"><span>Expected proceeds</span><b>${money(preflight.net)}</b></div>
                </div>`, [
                { label: `Continue Listing · ${money(preflight.net)} net`, className: 'gold', onClick: async () => {
                    closeModal();
                    await runAction('listForSale', { id: b.id, price, acceptMissingCertificateFee: true });
                } }
            ]);
        } }
    ]);
}

function showRemoveOwnerModal(b) {
    showModal('Remove Business Owner', `Remove <b>${esc(b.ownerName || 'the current owner')}</b> from <b>${esc(b.name)}</b>?<br><br>The business will immediately return to public sale and its for-sale sign will respawn.`, [
        { label: 'Remove — No Refund', className: 'danger', onClick: async () => { closeModal(); await runAction('adminRemoveOwner', { id: b.id, refund: false }); } },
        { label: `Remove + ${Number(state.data.adminRemovalRefundPercentage || 0)}% Refund`, className: 'gold', onClick: async () => { closeModal(); await runAction('adminRemoveOwner', { id: b.id, refund: true }); } }
    ]);
}

function businessById(id) {
    return (state.data.businesses || []).find(b => Number(b.id) === Number(id));
}

searchInput.addEventListener('input', () => {
    state.search = searchInput.value;
    state.selectedId = null;
    render();
});

document.addEventListener('change', event => {
    if (event.target.id === 'adminSignModelSelect') {
        const customInput = document.getElementById('adminSignModelCustom');
        if (customInput) {
            customInput.classList.toggle('hidden', event.target.value !== '__custom__');
            if (event.target.value === '__custom__') customInput.focus();
        }
    }
});

document.addEventListener('input', event => {
    if (event.target.id === 'listingRange') {
        const number = document.getElementById('listingNumber');
        const display = document.getElementById('listingDisplay');
        if (number) number.value = event.target.value;
        if (display) display.textContent = money(event.target.value);
    } else if (event.target.id === 'listingNumber') {
        const range = document.getElementById('listingRange');
        const display = document.getElementById('listingDisplay');
        if (range) range.value = event.target.value;
        if (display) display.textContent = money(event.target.value);
    }
});

document.addEventListener('click', async event => {
    const target = event.target.closest('[data-action], [data-tab], [data-modal-action]');
    if (!target) return;

    if (target.dataset.modalAction) {
        if (target.dataset.modalAction === 'cancel') return closeModal();
        const handler = modalHandlers[target.dataset.modalAction];
        if (handler) await handler();
        return;
    }

    if (target.dataset.tab) {
        state.tab = target.dataset.tab;
        state.selectedId = null;
        state.adminEditing = false;
        state.adminEditId = null;
        render();
        return;
    }

    const action = target.dataset.action;
    const id = Number(target.dataset.id);
    const business = businessById(id);

    if (action === 'close') {
        await nui('close');
        return;
    }
    if (action === 'close-certificate') {
        await nui('closeCertificate');
        return;
    }
    if (action === 'close-business-details') {
        await nui('closeBusinessDetails');
        return;
    }
    if (action === 'select-business') {
        state.selectedId = id;
        render();
        return;
    }
    if (action === 'purchase' && business) return confirmPurchase(business);
    if (action === 'sell-instant' && business) return showInstantSaleModal(business);
    if (action === 'list-business' && business) return showListingModal(business);
    if (action === 'cancel-listing' && business) {
        return showModal('Cancel Private Listing', `Cancel the listing for <b>${esc(business.name)}</b> and restore your ownership?`, [
            { label: 'Restore Ownership', className: 'gold', onClick: async () => { closeModal(); await runAction('cancelListing', { id }); } }
        ]);
    }
    if (action === 'set-job' && business) return runAction('setActiveJob', { id });
    if (action === 'replace-certificate' && business) {
        return showModal('Replacement Certificate', `Issue a replacement ownership certificate for <b>${esc(business.name)}</b> for <b>${money(state.data.replacementFee)}</b>?`, [
            { label: `Issue · ${money(state.data.replacementFee)}`, className: 'gold', onClick: async () => { closeModal(); await runAction('replacementCertificate', { id }); } }
        ]);
    }

    if (action === 'admin-select') {
        state.selectedId = id;
        state.adminEditing = false;
        state.adminEditId = null;
        render();
        return;
    }
    if (action === 'admin-create') {
        state.adminEditing = true;
        state.adminEditId = null;
        render();
        return;
    }
    if (action === 'admin-edit' && business) {
        state.adminEditing = true;
        state.adminEditId = id;
        render();
        return;
    }
    if (action === 'admin-cancel-edit') {
        state.adminEditing = false;
        state.adminEditId = null;
        render();
        return;
    }
    if (action === 'start-placement') {
        const signModel = getAdminSignModel() || 'prop_forsale_sign_fs';
        const signCoords = parseVector(document.getElementById('adminSignCoords')?.value, 4);
        const result = await nui('startSignPlacement', { model: signModel, coords: signCoords });
        if (!result.success) toast('error', result.message || 'Unable to start placement tool.');
        return;
    }
    if (action === 'admin-save') {
        const form = collectAdminForm();
        if (form.error) return toast('error', form.error);
        const result = await nui('adminSave', { id: state.adminEditId, payload: form.payload });
        toast(result.success ? 'success' : 'error', result.message || 'Save failed.');
        if (result.success && result.data) {
            setData(result.data);
            state.adminEditing = false;
            state.adminEditId = null;
            state.selectedId = result.selectedId || state.selectedId;
            render();
        }
        return;
    }
    if (action === 'admin-remove-owner' && business) return showRemoveOwnerModal(business);
    if (action === 'admin-clear-listing' && business) {
        return showModal('Clear Player Listing', `Clear the player listing for <b>${esc(business.name)}</b>?<br><br>This removes the seller claim without paying sale proceeds and converts it to a normal Business Center sale.`, [
            { label: 'Clear Listing', className: 'danger', onClick: async () => { closeModal(); await runAction('adminClearListing', { id }); } }
        ]);
    }
    if (action === 'admin-delete' && business) {
        return showModal('Delete Business', `Permanently delete <b>${esc(business.name)}</b>?<br><br>Owned businesses must have their owner removed first, and player listings must be cleared first.`, [
            { label: 'Delete Permanently', className: 'danger', onClick: async () => { closeModal(); await runAction('adminDelete', { id }); } }
        ]);
    }
});

document.addEventListener('keydown', async event => {
    if (event.key !== 'Escape') return;
    if (!certificateOverlay.classList.contains('hidden')) {
        await nui('closeCertificate');
        return;
    }
    if (!businessDetailsOverlay.classList.contains('hidden')) {
        await nui('closeBusinessDetails');
        return;
    }
    if (modalRoot.innerHTML) {
        closeModal();
        return;
    }
    if (state.open && !state.placing) await nui('close');
});

window.addEventListener('message', event => {
    const message = event.data || {};

    if (message.action === 'open') {
        state.open = true;
        state.placing = false;
        state.tab = message.initialTab || 'sale';
        state.selectedId = null;
        state.search = '';
        state.adminEditing = false;
        state.adminEditId = null;
        searchInput.value = '';
        setData(message.data || {});
        app.classList.remove('hidden');
        render();
    } else if (message.action === 'close') {
        state.open = false;
        state.placing = false;
        closeModal();
        app.classList.add('hidden');
    } else if (message.action === 'setData') {
        setData(message.data || {});
        if (message.selectedId) state.selectedId = message.selectedId;
        if (state.open && !state.placing) render();
    } else if (message.action === 'placementMode') {
        state.placing = true;
        app.classList.add('hidden');
    } else if (message.action === 'placementResult') {
        state.placing = false;
        app.classList.remove('hidden');
        const input = document.getElementById('adminSignCoords');
        if (input && message.coords) input.value = plainVec4Text(message.coords);
        toast('success', 'Sign position captured. Save the business to apply it.');
    } else if (message.action === 'placementCancelled') {
        state.placing = false;
        app.classList.remove('hidden');
        toast('warning', 'Sign placement cancelled.');
    } else if (message.action === 'showBusinessDetails') {
        const b = message.business || {};
        const price = b.status === 'listed' ? b.listingPrice : b.price;
        businessDetailsContent.innerHTML = `
            <img class="sign-details-image" src="${esc(imageFor(b))}" onerror="this.onerror=null;this.src='assets/businesses/default-business.svg'" alt="" />
            <div class="sign-details-title">${esc(b.name || 'Business for Sale')}</div>
            <div class="sign-details-description">${esc(b.description || 'Commercial business opportunity registered with the Los Santos Business Center.')}</div>
            <div class="fact-list">
                <div class="fact"><span class="fact-icon">▣</span><span class="fact-label">Business Type</span><span class="fact-value">${esc(b.businessType || 'Commercial Business')}</span></div>
                <div class="fact"><span class="fact-icon">♟</span><span class="fact-label">ESX Job</span><span class="fact-value">${esc(b.jobLabel || b.job || '—')}</span></div>
                <div class="fact"><span class="fact-icon">★</span><span class="fact-label">Owner Grade</span><span class="fact-value">${esc(b.jobGradeLabel || 'Boss')}</span></div>
                <div class="fact"><span class="fact-icon">●</span><span class="fact-label">Sale Price</span><span class="fact-value">${money(price)}</span></div>
                ${b.status === 'listed' ? `<div class="fact"><span class="fact-icon">↗</span><span class="fact-label">Original Price</span><span class="fact-value">${money(b.price)}</span></div>` : ''}
                <div class="fact"><span class="fact-icon">↶</span><span class="fact-label">Business Center Buyback</span><span class="fact-value">${Number(b.sellBackPercentage || 0)}% · ${money(b.sellBackValue)}</span></div>
            </div>
            <div class="sign-details-note">This sign is informational only. Businesses can only be purchased from the Business Center NPC.</div>`;
        businessDetailsOverlay.classList.remove('hidden');
    } else if (message.action === 'hideBusinessDetails') {
        businessDetailsOverlay.classList.add('hidden');
    } else if (message.action === 'showCertificate') {
        const c = message.certificate || {};
        document.getElementById('certificateBusiness').textContent = c.businessName || 'Unknown Business';
        document.getElementById('certificateOwner').textContent = c.ownerName || 'Unknown';
        document.getElementById('certificateType').textContent = c.businessType || 'Commercial Business';
        document.getElementById('certificatePrice').textContent = money(c.purchasePrice);
        document.getElementById('certificateDate').textContent = c.purchaseDate || 'Unknown';
        document.getElementById('certificateNumber').textContent = c.certificateNumber || 'Unknown';
        const expired = c.expired === true;
        document.getElementById('certificateExpiredStamp').classList.toggle('hidden', !expired);
        document.getElementById('certificateNote').textContent = expired
            ? 'EXPIRED: this certificate no longer matches the current Business Center ownership register. It will be removed from the holder inventory when closed.'
            : 'Purchase receipts verify the recorded transaction only. Current sale authority is determined by the Business Center ownership register.';
        certificateOverlay.querySelector('.certificate-card')?.classList.toggle('expired', expired);
        certificateOverlay.classList.remove('hidden');
    } else if (message.action === 'hideCertificate') {
        certificateOverlay.classList.add('hidden');
    }
});
