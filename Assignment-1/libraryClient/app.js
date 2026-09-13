/* =========================================================================
   Dashboard Logic
   ========================================================================= */

// We use a state object to remember data between fetches.
// When we load assets, institutions, or overdue items, we save them here.
const state = {
    assets: [],
    institutions: [],
    overdue: []
};

/* -----------------------------------------------------------------
   HELPERS
   ----------------------------------------------------------------- */
function baseUrl() {
    return document.getElementById('baseUrl').value.replace(/\/$/, '');
}

function badgeClass(status) {
    return String(status || 'available').toLowerCase();
}

function escapeHtml(text) {
    return String(text ?? '')
        .replace(/&/g, '&amp;').replace(/</g, '&lt;')
        .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

async function request(path, options = {}) {
    // Start with any headers the caller passed in.
    const headers = { ...(options.headers || {}) };

    // Only send Content-Type when there's a body (POST, PUT, PATCH).
    // GET requests have no body, and sending Content-Type anyway
    // makes the browser run a CORS preflight that we don't need.
    if (options.body) {
        headers['Content-Type'] = 'application/json';
    }

    // Always accept JSON back.
    headers['Accept'] = 'application/json';

    const response = await fetch(baseUrl() + path, {
        ...options,
        headers
    });

    const text = await response.text();
    let payload;
    try { payload = text ? JSON.parse(text) : null; } catch { payload = text; }

    if (!response.ok) {
        const msg = typeof payload === 'string'
            ? payload
            : (payload?.message || JSON.stringify(payload));
        throw new Error(msg || `HTTP ${response.status}`);
    }
    return payload;
}

/* -----------------------------------------------------------------
   RENDERING
   ----------------------------------------------------------------- */
function renderAssets(containerId, assets) {
    const container = document.getElementById(containerId);
    if (!assets || assets.length === 0) {
        container.innerHTML = '<p class="empty">No assets found.</p>';
        return;
    }
    const html = assets.map(a => `
        <div class="asset-card">
            <div class="meta">
                <div class="tag">${escapeHtml(a.assetTag)}</div>
                <div class="name">${escapeHtml(a.name)}</div>
                <div class="place">${escapeHtml(a.institutionId)} — ${escapeHtml(a.site)}</div>
            </div>
            <span class="badge ${badgeClass(a.status)}">${escapeHtml(a.status)}</span>
        </div>
    `).join('');
    container.innerHTML = html;
}

// NEW: Calculate and display the stat cards
function renderSummary() {
    const total = state.assets.length;
    const available = state.assets.filter(a => a.status === 'AVAILABLE').length;
    const overdue = state.overdue.length;
    const institutions = state.institutions.length;

    document.getElementById('total-assets').textContent = total;
    document.getElementById('available-assets').textContent = available;
    document.getElementById('overdue-assets').textContent = overdue;
    document.getElementById('institution-count').textContent = institutions;
}

/* -----------------------------------------------------------------
   LOADING DATA
   ----------------------------------------------------------------- */
async function loadInstitutions() {
    try {
        const result = await request('/institutions');
        state.institutions = Array.isArray(result) ? result : [];
    } catch (e) {
        state.institutions = [];
    }
    renderSummary();
}

async function loadGlobal() {
    const container = document.getElementById('global-list');
    container.innerHTML = '<p class="empty">Loading…</p>';
    try {
        const result = await request('/assets');
        state.assets = await request('/assets');
        renderAssets('global-list', state.assets);
        renderSummary(); // Update stats after loading assets
    } catch (e) {
        container.innerHTML = `<p class="empty">Error: ${escapeHtml(e.message)}</p>`;
    }
}

async function loadCampus() {
    const institution = document.getElementById('campus-institution').value.trim();
    const site = document.getElementById('campus-site').value.trim();
    const container = document.getElementById('campus-list');

    if (!institution && !site) {
        container.innerHTML = '<p class="empty">Enter an institution or site to filter.</p>';
        return;
    }
    container.innerHTML = '<p class="empty">Loading…</p>';
    const params = new URLSearchParams();
    if (institution) params.set('institutionId', institution);
    if (site) params.set('site', site);

    try {
        const assets = await request('/assets/filtered?' + params.toString());
        renderAssets('campus-list', assets);
    } catch (e) {
        container.innerHTML = `<p class="empty">Error: ${escapeHtml(e.message)}</p>`;
    }
}

async function loadOverdue() {
    const container = document.getElementById('overdue-list');
    container.innerHTML = '<p class="empty">Loading…</p>';
    try {
        const result = await request('/assets/overdue');
        state.overdue = Array.isArray(result) ? result : [];
        renderAssets('overdue-list', state.overdue);
        renderSummary();
    } catch (e) {
        container.innerHTML = `<p class="empty">Error: ${escapeHtml(e.message)}</p>`;
    }
}

/* -----------------------------------------------------------------
   FORM HANDLERS (same as before)
   ----------------------------------------------------------------- */
async function handleLoan(event) {
    event.preventDefault();
    const tag = document.getElementById('loan-tag').value.trim();
    const due = document.getElementById('loan-due').value;
    const msg = document.getElementById('loan-msg');

    if (!tag || !due) { msg.textContent = 'Tag and due date are required.'; msg.className = 'status-msg err'; return; }
    msg.textContent = 'Submitting…'; msg.className = 'status-msg';

    const payload = {
        scheduleId: `SCH-${tag}-${due}`, scheduleType: 'BOOKING', scheduleStatus: 'PENDING',
        startTime: new Date().toISOString(), dueDate: new Date(due + 'T00:00:00Z').toISOString(),
        description: 'Loaned via web dashboard'
    };

    try {
        await request(`/assets/${encodeURIComponent(tag)}/loan`, { method: 'POST', body: JSON.stringify(payload) });
        msg.textContent = `Asset ${tag} loaned successfully.`; msg.className = 'status-msg ok';
        event.target.reset();
    } catch (e) { msg.textContent = 'Error: ' + e.message; msg.className = 'status-msg err'; }
}

async function handleReturn(event) {
    event.preventDefault();
    const tag = document.getElementById('return-tag').value.trim();
    const schedule = document.getElementById('return-schedule').value.trim();
    const msg = document.getElementById('return-msg');

    if (!tag || !schedule) { msg.textContent = 'Tag and schedule ID are required.'; msg.className = 'status-msg err'; return; }
    msg.textContent = 'Submitting…'; msg.className = 'status-msg';

    const payload = {
        scheduleId: schedule, scheduleType: 'BOOKING', scheduleStatus: 'COMPLETED',
        startTime: new Date().toISOString(), dueDate: new Date().toISOString(),
        description: 'Returned via web dashboard'
    };

    try {
        await request(`/assets/${encodeURIComponent(tag)}/return`, { method: 'POST', body: JSON.stringify(payload) });
        msg.textContent = `Asset ${tag} returned successfully.`; msg.className = 'status-msg ok';
        event.target.reset();
    } catch (e) { msg.textContent = 'Error: ' + e.message; msg.className = 'status-msg err'; }
}

async function handleSchedule(event) {
    event.preventDefault();
    const tag = document.getElementById('sched-tag').value.trim();
    const type = document.getElementById('sched-type').value;
    const start = document.getElementById('sched-start').value;
    const due = document.getElementById('sched-due').value;
    const desc = document.getElementById('sched-desc').value.trim();
    const msg = document.getElementById('sched-msg');

    if (!tag || !start || !due) { msg.textContent = 'Tag, start and due dates are required.'; msg.className = 'status-msg err'; return; }
    msg.textContent = 'Submitting…'; msg.className = 'status-msg';

    const payload = {
        scheduleId: `SCH-${tag}-${Date.now()}`, scheduleType: type, scheduleStatus: 'PENDING',
        startTime: new Date(start + 'Z').toISOString(), dueDate: new Date(due + 'Z').toISOString(),
        description: desc || 'Added via web dashboard'
    };

    try {
        await request(`/assets/${encodeURIComponent(tag)}/schedules`, { method: 'POST', body: JSON.stringify(payload) });
        msg.textContent = `Schedule added to ${tag}.`; msg.className = 'status-msg ok';
        event.target.reset();
    } catch (e) { msg.textContent = 'Error: ' + e.message; msg.className = 'status-msg err'; }
}

/* -----------------------------------------------------------------
   TAB SWITCHING & WIRING
   ----------------------------------------------------------------- */
const tabButtons = document.querySelectorAll('.tab');
const panels = document.querySelectorAll('.panel');

tabButtons.forEach(tab => {
    tab.addEventListener('click', () => {
        tabButtons.forEach(t => t.classList.remove('active'));
        panels.forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById('panel-' + tab.dataset.tab).classList.add('active');
    });
});

document.getElementById('refreshBtn').addEventListener('click', () => {
    const activeTab = document.querySelector('.tab.active').dataset.tab;
    if (activeTab === 'global') loadGlobal();
    if (activeTab === 'campus') loadCampus();
    if (activeTab === 'overdue') loadOverdue();
});

document.getElementById('campus-filter-btn').addEventListener('click', loadCampus);
document.getElementById('loan-form').addEventListener('submit', handleLoan);
document.getElementById('return-form').addEventListener('submit', handleReturn);
document.getElementById('schedule-form').addEventListener('submit', handleSchedule);

/* -----------------------------------------------------------------
   INITIAL LOAD
   When the page opens, load everything to populate the stat cards.
   ----------------------------------------------------------------- */
async function initialize() {
    await loadInstitutions();
    await loadGlobal();
    await loadOverdue();
}

initialize();