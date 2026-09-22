// 爱快 DHCP 网关切换助手 - 前端逻辑
(() => {
  const $ = (sel) => document.querySelector(sel);

  const listView = $('#list-view');
  const configView = $('#config-view');
  const deviceList = $('#device-list');
  const listEmpty = $('#list-empty');
  const listError = $('#list-error');
  const summary = $('#summary');
  const statusBadge = $('#status-badge');
  const configForm = $('#config-form');
  const formMsg = $('#form-msg');
  const toast = $('#toast');
  const btnRefresh = $('#btn-refresh');
  const btnSettings = $('#btn-settings');
  const btnCancel = $('#btn-cancel');
  const btnToggleHidden = $('#btn-toggle-hidden');

  const toggling = new Set(); // 正在切换的 mac 集合
  const hiding = new Set(); // 正在隐藏/恢复的 mac 集合
  let showHidden = false; // 是否展开显示隐藏的终端

  // ---- 工具 ----

  async function api(path, options = {}) {
    const resp = await fetch(path, {
      headers: { 'Content-Type': 'application/json' },
      ...options,
    });
    let data = null;
    try {
      data = await resp.json();
    } catch (_) {
      /* 非 JSON 响应 */
    }
    if (!resp.ok) {
      const msg = (data && data.detail) || `请求失败（HTTP ${resp.status}）`;
      throw new Error(msg);
    }
    return data;
  }

  function showToast(msg) {
    toast.textContent = msg;
    toast.classList.remove('hidden');
    clearTimeout(showToast._t);
    showToast._t = setTimeout(() => toast.classList.add('hidden'), 2500);
  }

  function setStatus(text, cls) {
    statusBadge.textContent = text;
    statusBadge.className = 'badge ' + cls;
  }

  function showView(view) {
    listView.classList.toggle('hidden', view !== 'list');
    configView.classList.toggle('hidden', view !== 'config');
  }

  function fillForm(cfg) {
    configForm.host.value = cfg.host || '';
    configForm.port.value = cfg.port || 80;
    configForm.use_https.checked = !!cfg.use_https;
    configForm.username.value = cfg.username || '';
    configForm.password.value = cfg.password || '';
    configForm.gateway_a.value = cfg.gateway_a || '';
    configForm.gateway_b.value = cfg.gateway_b || '';
  }

  function readForm() {
    return {
      host: configForm.host.value.trim(),
      port: parseInt(configForm.port.value, 10) || 80,
      use_https: configForm.use_https.checked,
      username: configForm.username.value.trim(),
      password: configForm.password.value,
      gateway_a: configForm.gateway_a.value.trim(),
      gateway_b: configForm.gateway_b.value.trim(),
    };
  }

  // ---- 渲染 ----

  function renderDevices(devices) {
    const hiddenCount = devices.filter((d) => d.hidden).length;
    const visible = devices.filter((d) => !d.hidden || showHidden);

    deviceList.innerHTML = '';
    listEmpty.classList.toggle('hidden', visible.length !== 0);
    summary.textContent = showHidden
      ? `共 ${devices.length} 台终端（含 ${hiddenCount} 台隐藏）`
      : `共 ${devices.length - hiddenCount} 台终端` +
        (hiddenCount ? `（已隐藏 ${hiddenCount} 台）` : '');

    btnToggleHidden.textContent = showHidden
      ? '收起隐藏'
      : `隐藏的终端 (${hiddenCount})`;
    btnToggleHidden.classList.toggle('hidden', hiddenCount === 0);

    for (const d of visible) {
      const li = document.createElement('li');
      li.className = 'device-item' + (d.hidden ? ' is-hidden' : '');

      const info = document.createElement('div');
      info.className = 'device-info';

      const name = document.createElement('div');
      name.className = 'device-name';
      name.textContent = d.name || d.mac;

      const meta = document.createElement('div');
      meta.className = 'device-meta';
      if (d.ip) {
        const ip = document.createElement('span');
        ip.className = 'ip';
        ip.textContent = d.ip;
        meta.appendChild(ip);
      }
      const mac = document.createElement('span');
      mac.className = 'mac';
      mac.textContent = d.mac;
      meta.appendChild(mac);

      const chip = document.createElement('span');
      chip.className = 'gateway-chip' + (d.is_a ? ' a' : d.is_b ? ' b' : '');
      chip.textContent = d.gateway ? `网关 ${d.gateway}` : '网关未设置';
      meta.appendChild(chip);

      info.appendChild(name);
      info.appendChild(meta);

      const toggle = document.createElement('div');
      toggle.className = 'toggle';

      const hideBtn = document.createElement('button');
      hideBtn.className = 'hide-btn' + (d.hidden ? ' restore' : '');
      hideBtn.textContent = d.hidden ? '恢复' : '隐藏';
      hideBtn.setAttribute(
        'aria-label',
        (d.hidden ? '恢复显示 ' : '隐藏 ') + (d.name || d.mac)
      );
      if (hiding.has(d.mac)) hideBtn.disabled = true;
      hideBtn.addEventListener('click', () => onToggleHidden(d));

      const label = document.createElement('span');
      label.className = 'toggle-label ' + (d.is_a ? 'a' : d.is_b ? 'b' : 'none');
      label.textContent = d.is_a ? 'A' : d.is_b ? 'B' : '—';

      const sw = document.createElement('button');
      sw.className = 'switch' + (d.is_b ? ' on' : '');
      sw.setAttribute('aria-label', `切换 ${d.name || d.mac} 的网关`);
      if (toggling.has(d.mac)) {
        sw.classList.add('loading');
        sw.disabled = true;
      }
      sw.addEventListener('click', () => onToggle(d, sw));

      toggle.appendChild(hideBtn);
      toggle.appendChild(label);
      toggle.appendChild(sw);
      li.appendChild(info);
      li.appendChild(toggle);
      deviceList.appendChild(li);
    }
  }

  // ---- 动作 ----

  async function loadDevices() {
    listError.classList.add('hidden');
    btnRefresh.disabled = true;
    try {
      const data = await api('/api/devices');
      setStatus('已连接', 'badge-ok');
      renderDevices(data.devices || []);
    } catch (e) {
      setStatus('错误', 'badge-err');
      listError.textContent = e.message;
      listError.classList.remove('hidden');
      deviceList.innerHTML = '';
      listEmpty.classList.add('hidden');
    } finally {
      btnRefresh.disabled = false;
    }
  }

  async function onToggle(d, sw) {
    toggling.add(d.mac);
    sw.classList.add('loading');
    sw.disabled = true;
    try {
      const r = await api(`/api/devices/${encodeURIComponent(d.mac)}/toggle`, {
        method: 'POST',
      });
      showToast(`已切换：${r.old_gateway || '—'} → ${r.new_gateway}`);
      // 先移出集合再重渲染，避免新按钮被误标为 loading 而永久转圈
      toggling.delete(d.mac);
      await loadDevices();
    } catch (e) {
      toggling.delete(d.mac);
      showToast('切换失败：' + e.message);
      sw.classList.remove('loading');
      sw.disabled = false;
    }
  }

  async function onToggleHidden(d) {
    const action = d.hidden ? 'unhide' : 'hide';
    hiding.add(d.mac);
    try {
      await api(`/api/devices/${encodeURIComponent(d.mac)}/${action}`, {
        method: 'POST',
      });
      showToast(d.hidden ? `已恢复显示 ${d.name || d.mac}` : `已隐藏 ${d.name || d.mac}`);
      hiding.delete(d.mac);
      await loadDevices();
    } catch (e) {
      hiding.delete(d.mac);
      showToast('操作失败：' + e.message);
      await loadDevices();
    }
  }

  // ---- 初始化 ----

  async function init() {
    let cfg = {};
    try {
      cfg = await api('/api/config');
    } catch (_) {
      /* 忽略，视为未配置 */
    }

    btnRefresh.addEventListener('click', loadDevices);

    btnToggleHidden.addEventListener('click', () => {
      showHidden = !showHidden;
      loadDevices();
    });

    btnSettings.addEventListener('click', () => {
      fillForm(cfg);
      formMsg.classList.add('hidden');
      showView('config');
    });

    btnCancel.addEventListener('click', () => {
      if (cfg && cfg.host) showView('list');
    });

    configForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      formMsg.classList.add('hidden');
      const data = readForm();
      if (!data.host) {
        formMsg.textContent = '请填写路由器地址';
        formMsg.classList.remove('hidden');
        return;
      }
      try {
        await api('/api/config', { method: 'POST', body: JSON.stringify(data) });
        cfg = data;
        try {
          await api('/api/login', { method: 'POST' });
        } catch (e) {
          formMsg.textContent = '配置已保存，但连接失败：' + e.message;
          formMsg.classList.remove('hidden');
          return;
        }
        formMsg.classList.add('hidden');
        showView('list');
        await loadDevices();
      } catch (e) {
        formMsg.textContent = '保存失败：' + e.message;
        formMsg.classList.remove('hidden');
      }
    });

    if (cfg && cfg.host) {
      showView('list');
      await loadDevices();
    } else {
      fillForm(cfg);
      showView('config');
    }
  }

  init();
})();
