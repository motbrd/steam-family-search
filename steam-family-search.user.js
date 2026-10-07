// ==UserScript==
// @name         Steam Family Library in Search
// @namespace    local.steam-family-search
// @version      0.1.0
// @description  Marks Steam Store search results you can already play through Steam Family.
// @match        https://store.steampowered.com/search*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';
  if (!location.pathname.startsWith('/search')) return;
  // In the Steam client this runs at document start (before the DOM), so wait for it.
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main, { once: true });
  else main();

  function main() {
    if (window.__sfsLoaded) return; // may be injected more than once
    window.__sfsLoaded = true;

    const CACHE_KEY = 'sfs_family_apps';
    const CACHE_TTL = 12 * 60 * 60 * 1000; // 12h -> at most ~2 API calls per day

    // --- Data: same token/API the store page itself uses for "In Family Library" ---

    function readConfig(attr) {
      const el = document.getElementById('application_config');
      try { return JSON.parse(el.getAttribute(attr)); } catch { return null; }
    }

    async function api(method, params) {
      const url = new URL(`https://api.steampowered.com/IFamilyGroupsService/${method}/v1/`);
      for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
      const r = await fetch(url, { credentials: 'omit' });
      if (!r.ok) throw new Error(`${method}: HTTP ${r.status}`);
      return (await r.json()).response || {};
    }

    async function loadFamilyApps() {
      const userinfo = readConfig('data-userinfo') || {};
      const steamid = userinfo.steamid;
      try {
        const c = JSON.parse(localStorage.getItem(CACHE_KEY));
        if (c && c.steamid === steamid && Date.now() - c.t < CACHE_TTL) return new Set(c.apps);
      } catch { /* no cache */ }

      const token = (readConfig('data-store_user_config') || {}).webapi_token;
      if (!token || !steamid) throw new Error('Not logged in to the store');

      const group = await api('GetFamilyGroupForUser', { access_token: token });
      if (!group.family_groupid) return new Set(); // not in a Steam Family

      const lib = await api('GetSharedLibraryApps', {
        access_token: token,
        family_groupid: group.family_groupid,
        steamid,
        include_own: false,
        include_excluded: false,
        include_free: false,
        include_non_games: false,
      });
      const apps = (lib.apps || [])
        .filter(a => !(a.owner_steamids || []).includes(steamid))
        .map(a => a.appid);
      try { localStorage.setItem(CACHE_KEY, JSON.stringify({ steamid, t: Date.now(), apps })); } catch { }
      return new Set(apps);
    }

    // --- UI ---

    const style = document.createElement('style');
    style.textContent = `
      .sfs-family .search_capsule { position: relative; }
      .sfs-family:not(.ds_owned) .search_capsule::after {
        content: "FAMILY"; position: absolute; left: 0; bottom: 0;
        background: #2a7fb8; color: #fff; font: bold 9px/1 Arial, sans-serif;
        padding: 2px 4px; letter-spacing: .5px;
      }
      .sfs-family:not(.ds_owned) .title::after {
        content: "In Family Library"; margin-left: 8px; padding: 1px 5px;
        background: rgba(42,127,184,.35); color: #b8e0ff; font-size: 11px; border-radius: 2px;
      }
    `;
    document.head.appendChild(style);
    try { localStorage.removeItem('sfs_hide'); } catch { } // leftover from the removed toggle

    function mark(family) {
      for (const row of document.querySelectorAll('a.search_result_row[data-ds-appid]:not([data-sfs])')) {
        row.dataset.sfs = '1';
        if (row.classList.contains('ds_owned')) continue; // personally owned -> leave as is
        const ids = row.dataset.dsAppid.split(',').map(Number);
        if (ids.length === 1 && family.has(ids[0])) row.classList.add('sfs-family');
      }
    }

    loadFamilyApps().then(family => {
      mark(family);
      // Infinite scroll / filter changes append or replace rows.
      const rows = document.getElementById('search_resultsRows') || document.body;
      new MutationObserver(() => mark(family)).observe(rows.parentNode || rows, { childList: true, subtree: true });
    }).catch(e => console.warn('[Steam Family Search]', e));
  }
})();
