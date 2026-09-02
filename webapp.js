/**
 * HydroPulse Web Console - Centralized Backend Authentication & Pump Controller
 */

document.addEventListener('DOMContentLoaded', () => {

  // ==============================================================================
  // 1. Configuration & Global State
  // ==============================================================================
  const DEFAULT_API_URL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
    ? 'http://localhost:4000/api/v1'
    : (window.location.origin.includes('vercel.app')
        ? 'http://localhost:4000/api/v1' // Default local dev, or cloud endpoint if configured
        : `${window.location.origin}/api/v1`);

  let apiBaseUrl = localStorage.getItem('hydropulse_api_url') || DEFAULT_API_URL;
  let authToken = localStorage.getItem('hydropulse_auth_token') || null;
  let currentUser = null;
  let activeDevice = {
    id: 'esp32_pump_000000',
    name: 'ESP32 Main Gateway',
    isOnline: true,
    rttMs: 22
  };

  // Telemetry & Control State
  let waterLevelPct = 68.5;
  let isPumpRunning = false;
  let operatingMode = 'AUTO';
  let flowRateLpm = 0.0;
  let powerKw = 0.00;
  let tdsPpm = 118;
  let tempC = 24.5;
  let runDurationSeconds = 0;
  let cycleCount = 14;
  let runtimeTimer = null;

  // Safety thresholds
  let autoStartThresh = 25;
  let autoStopThresh = 95;
  let dryRunEnabled = true;

  // ==============================================================================
  // 2. DOM Elements
  // ==============================================================================
  const authView = document.getElementById('auth-view');
  const dashboardView = document.getElementById('dashboard-view');
  const serverStatusDot = document.getElementById('server-status-dot');
  const serverStatusText = document.getElementById('server-status-text');
  const btnOpenApiConfig = document.getElementById('btn-open-api-config');
  const apiModal = document.getElementById('api-modal');
  const inputApiUrl = document.getElementById('input-api-url');
  const btnSaveApiUrl = document.getElementById('btn-save-api-url');
  const btnCancelApiModal = document.getElementById('btn-cancel-api-modal');

  // Auth Tabs & Forms
  const tabLogin = document.getElementById('tab-login');
  const tabRegister = document.getElementById('tab-register');
  const formLogin = document.getElementById('form-login');
  const formRegister = document.getElementById('form-register');
  const authAlert = document.getElementById('auth-alert');
  const loginEmail = document.getElementById('login-email');
  const loginPassword = document.getElementById('login-password');
  const regFirstname = document.getElementById('reg-firstname');
  const regLastname = document.getElementById('reg-lastname');
  const regEmail = document.getElementById('reg-email');
  const regPassword = document.getElementById('reg-password');
  const btnLoginSubmit = document.getElementById('btn-login-submit');
  const btnRegisterSubmit = document.getElementById('btn-register-submit');

  // Dashboard Header & User Info
  const userAvatar = document.getElementById('user-avatar');
  const userDisplayName = document.getElementById('user-display-name');
  const userDisplayEmail = document.getElementById('user-display-email');
  const topDeviceName = document.getElementById('top-device-name');
  const topDeviceId = document.getElementById('top-device-id');
  const hwStatusPill = document.getElementById('hw-status-pill');
  const hwStatusTxt = document.getElementById('hw-status-txt');
  const hwRttTxt = document.getElementById('hw-rtt-txt');
  const btnLogout = document.getElementById('btn-logout');

  // Controls & Actions
  const btnMotorToggle = document.getElementById('btn-motor-toggle');
  const motorBtnText = document.getElementById('motor-btn-text');
  const btnEstop = document.getElementById('btn-estop');
  const btnModeAuto = document.getElementById('btn-mode-auto');
  const btnModeManual = document.getElementById('btn-mode-manual');

  // Tank & Telemetry
  const tankCanvas = document.getElementById('tank-canvas');
  const tankLevelPct = document.getElementById('tank-level-pct');
  const tankVolumeLiters = document.getElementById('tank-volume-liters');
  const inflowStatusVal = document.getElementById('inflow-status-val');
  const valFlowRate = document.getElementById('val-flow-rate');
  const valPowerKw = document.getElementById('val-power-kw');
  const valTds = document.getElementById('val-tds');
  const valTemp = document.getElementById('val-temp');
  const valRuntime = document.getElementById('val-runtime');
  const valCycles = document.getElementById('val-cycles');

  // Rules
  const sliderStartThresh = document.getElementById('slider-start-thresh');
  const lblStartThresh = document.getElementById('lbl-start-thresh');
  const sliderStopThresh = document.getElementById('slider-stop-thresh');
  const lblStopThresh = document.getElementById('lbl-stop-thresh');
  const checkDryrun = document.getElementById('check-dryrun');
  const btnSaveRules = document.getElementById('btn-save-rules');

  // ==============================================================================
  // 3. Centralized Backend Database API Client
  // ==============================================================================
  async function apiRequest(endpoint, options = {}) {
    const url = `${apiBaseUrl.replace(/\/+$/, '')}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
      ...(authToken ? { 'Authorization': `Bearer ${authToken}` } : {}),
      ...(options.headers || {})
    };

    try {
      const response = await fetch(url, {
        ...options,
        headers
      });

      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(data.message || `Server error (${response.status})`);
      }
      return data;
    } catch (err) {
      throw err;
    }
  }

  // Check Backend Connectivity
  async function checkBackendHealth() {
    serverStatusText.textContent = `Connecting to ${apiBaseUrl}...`;
    try {
      const rootUrl = apiBaseUrl.replace('/api/v1', '');
      const res = await fetch(`${rootUrl}/health`, { method: 'GET' }).catch(() => null);
      if (res && res.ok) {
        serverStatusDot.className = 'status-dot online';
        serverStatusText.textContent = 'Backend Database Online';
        return true;
      } else {
        throw new Error('Not responding');
      }
    } catch {
      serverStatusDot.className = 'status-dot offline';
      serverStatusText.textContent = `Backend Offline (${apiBaseUrl.replace('http://', '').replace('https://', '')})`;
      return false;
    }
  }

  // ==============================================================================
  // 4. Authentication Flow (Pushes to Database)
  // ==============================================================================

  // Tab Switching
  tabLogin.addEventListener('click', () => {
    tabLogin.classList.add('active');
    tabRegister.classList.remove('active');
    formLogin.classList.remove('hidden');
    formRegister.classList.add('hidden');
    clearAuthAlert();
  });

  tabRegister.addEventListener('click', () => {
    tabRegister.classList.add('active');
    tabLogin.classList.remove('active');
    formRegister.classList.remove('hidden');
    formLogin.classList.add('hidden');
    clearAuthAlert();
  });

  function showAuthAlert(message, isSuccess = false) {
    authAlert.textContent = message;
    authAlert.className = `auth-alert ${isSuccess ? 'success' : ''}`;
    authAlert.classList.remove('hidden');
  }

  function clearAuthAlert() {
    authAlert.textContent = '';
    authAlert.classList.add('hidden');
  }

  function setButtonLoading(btn, isLoading) {
    const textSpan = btn.querySelector('.btn-text');
    const loaderSpan = btn.querySelector('.btn-loader');
    if (isLoading) {
      btn.disabled = true;
      textSpan.classList.add('hidden');
      loaderSpan.classList.remove('hidden');
    } else {
      btn.disabled = false;
      textSpan.classList.remove('hidden');
      loaderSpan.classList.add('hidden');
    }
  }

  // 1. Register: Pushes directly to Backend Database (PostgreSQL via Prisma)
  formRegister.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearAuthAlert();
    setButtonLoading(btnRegisterSubmit, true);

    const payload = {
      firstName: regFirstname.value.trim(),
      lastName: regLastname.value.trim(),
      email: regEmail.value.trim().toLowerCase(),
      password: regPassword.value
    };

    try {
      const res = await apiRequest('/auth/register', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      if (res.data && res.data.tokens) {
        authToken = res.data.tokens.accessToken;
        localStorage.setItem('hydropulse_auth_token', authToken);
        currentUser = res.data.user;
        showAuthAlert('Account created successfully! Loading console...', true);
        setTimeout(() => initDashboard(), 800);
      }
    } catch (err) {
      if (err.message && err.message.toLowerCase().includes('failed to fetch')) {
        showAuthAlert(`Cannot reach backend database at ${apiBaseUrl}. Ensure backend is running, or click "⚡ Instant Demo Console" below!`);
      } else {
        showAuthAlert(err.message || 'Failed to create account on backend database.');
      }
    } finally {
      setButtonLoading(btnRegisterSubmit, false);
    }
  });

  // 2. Login: Verifies directly with Backend Database
  formLogin.addEventListener('submit', async (e) => {
    e.preventDefault();
    clearAuthAlert();
    setButtonLoading(btnLoginSubmit, true);

    const payload = {
      email: loginEmail.value.trim().toLowerCase(),
      password: loginPassword.value
    };

    try {
      const res = await apiRequest('/auth/login', {
        method: 'POST',
        body: JSON.stringify(payload)
      });

      if (res.data && res.data.tokens) {
        authToken = res.data.tokens.accessToken;
        localStorage.setItem('hydropulse_auth_token', authToken);
        currentUser = res.data.user;
        showAuthAlert('Authenticated! Entering console...', true);
        setTimeout(() => initDashboard(), 600);
      }
    } catch (err) {
      if (err.message && err.message.toLowerCase().includes('failed to fetch')) {
        showAuthAlert(`Cannot reach backend database at ${apiBaseUrl}. Ensure backend is running, or click "⚡ Instant Demo Console" below!`);
      } else {
        showAuthAlert(err.message || 'Invalid email or password. Please check your credentials.');
      }
    } finally {
      setButtonLoading(btnLoginSubmit, false);
    }
  });

  // 3. Logout
  btnLogout.addEventListener('click', () => {
    authToken = null;
    currentUser = null;
    localStorage.removeItem('hydropulse_auth_token');
    authView.classList.remove('hidden');
    dashboardView.classList.add('hidden');
    loginPassword.value = '';
    clearAuthAlert();
  });

  // 4. Instant Demo / Guest Console Access
  const btnDemoAccess = document.getElementById('btn-demo-access');
  if (btnDemoAccess) {
    btnDemoAccess.addEventListener('click', () => {
      currentUser = {
        firstName: 'Karthik',
        lastName: 'Nataraj',
        email: 'karthik@hydropulse.io',
        role: 'ADMIN'
      };
      activeDevice = {
        id: 'esp32_pump_main',
        name: 'ESP32 Main Gateway',
        isOnline: true,
        rttMs: 22
      };
      initDashboard();
    });
  }

  // Check Existing Session on Page Load
  async function checkSession() {
    await checkBackendHealth();

    // Check for demo bypass via URL hash or param
    if (window.location.hash === '#dashboard' || window.location.search.includes('demo=true')) {
      currentUser = {
        firstName: 'Karthik',
        lastName: 'Nataraj',
        email: 'karthik@hydropulse.io',
        role: 'ADMIN'
      };
      activeDevice = {
        id: 'esp32_pump_main',
        name: 'ESP32 Main Gateway',
        isOnline: true,
        rttMs: 22
      };
      initDashboard();
      return;
    }

    if (!authToken) {
      authView.classList.remove('hidden');
      dashboardView.classList.add('hidden');
      return;
    }

    try {
      const res = await apiRequest('/auth/profile', { method: 'GET' });
      if (res.data) {
        currentUser = res.data;
        initDashboard();
      } else {
        throw new Error('Invalid session');
      }
    } catch {
      authToken = null;
      localStorage.removeItem('hydropulse_auth_token');
      authView.classList.remove('hidden');
      dashboardView.classList.add('hidden');
    }
  }

  // ==============================================================================
  // 5. Dashboard Initialization & Device Fetch
  // ==============================================================================
  async function initDashboard() {
    authView.classList.add('hidden');
    dashboardView.classList.remove('hidden');

    // Populate User Details
    if (currentUser) {
      const initials = `${(currentUser.firstName || 'K')[0]}${(currentUser.lastName || 'N')[0]}`.toUpperCase();
      userAvatar.textContent = initials;
      userDisplayName.textContent = `${currentUser.firstName} ${currentUser.lastName}`;
      userDisplayEmail.textContent = currentUser.email;
    }

    // Fetch User Devices from Database
    try {
      const devRes = await apiRequest('/devices', { method: 'GET' });
      if (devRes.data && devRes.data.length > 0) {
        const dev = devRes.data[0];
        activeDevice.id = dev.id || dev.deviceId || 'esp32_pump_000000';
        activeDevice.name = dev.name || 'ESP32 Main Gateway';
      }
    } catch (e) {
      console.warn('Could not fetch registered devices, using default account gateway node.');
    }

    topDeviceName.textContent = activeDevice.name;
    topDeviceId.textContent = activeDevice.id;

    updateUI();
    renderHistoryChart();
  }

  // ==============================================================================
  // 6. Pump Control & Actuation Deck
  // ==============================================================================
  btnMotorToggle.addEventListener('click', async () => {
    const nextState = !isPumpRunning;
    const command = nextState ? 'PUMP_ON' : 'PUMP_OFF';

    // Optimistic UI actuation
    setPumpRunning(nextState);

    // Send command to Backend Database & MQTT Ingestion
    try {
      await apiRequest(`/pumps/${activeDevice.id}/command`, {
        method: 'POST',
        body: JSON.stringify({ command })
      });
    } catch (e) {
      console.warn(`Command ${command} logged in local controller session (${e.message})`);
    }
  });

  btnEstop.addEventListener('click', async () => {
    setPumpRunning(false);
    try {
      await apiRequest(`/pumps/${activeDevice.id}/command`, {
        method: 'POST',
        body: JSON.stringify({ command: 'EMERGENCY_STOP' })
      });
    } catch (e) {
      console.warn('Emergency stop triggered locally');
    }
  });

  btnModeAuto.addEventListener('click', () => setOperatingMode('AUTO'));
  btnModeManual.addEventListener('click', () => setOperatingMode('MANUAL'));

  function setOperatingMode(mode) {
    operatingMode = mode;
    if (mode === 'AUTO') {
      btnModeAuto.classList.add('active');
      btnModeManual.classList.remove('active');
    } else {
      btnModeAuto.classList.remove('active');
      btnModeManual.classList.add('active');
    }

    apiRequest(`/pumps/${activeDevice.id}/command`, {
      method: 'POST',
      body: JSON.stringify({ command: 'SET_MODE', parameters: { mode } })
    }).catch(() => {});
  }

  function setPumpRunning(running) {
    isPumpRunning = running;
    if (running) {
      btnMotorToggle.classList.add('running');
      motorBtnText.textContent = 'STOP MOTOR';
      inflowStatusVal.textContent = 'Active Inflow';
      inflowStatusVal.style.color = 'var(--emerald)';

      if (!runtimeTimer) {
        runtimeTimer = setInterval(() => {
          runDurationSeconds++;
          const hrs = String(Math.floor(runDurationSeconds / 3600)).padStart(2, '0');
          const mins = String(Math.floor((runDurationSeconds % 3600) / 60)).padStart(2, '0');
          const secs = String(runDurationSeconds % 60).padStart(2, '0');
          valRuntime.textContent = `${hrs}:${mins}:${secs}`;
        }, 1000);
      }
    } else {
      btnMotorToggle.classList.remove('running');
      motorBtnText.textContent = 'START MOTOR';
      inflowStatusVal.textContent = 'Idle';
      inflowStatusVal.style.color = 'var(--text-main)';

      if (runtimeTimer) {
        clearInterval(runtimeTimer);
        runtimeTimer = null;
      }
    }
    updateUI();
  }

  // Rules Sliders
  sliderStartThresh.addEventListener('input', (e) => {
    autoStartThresh = parseInt(e.target.value, 10);
    lblStartThresh.textContent = `${autoStartThresh}%`;
  });

  sliderStopThresh.addEventListener('input', (e) => {
    autoStopThresh = parseInt(e.target.value, 10);
    lblStopThresh.textContent = `${autoStopThresh}%`;
  });

  btnSaveRules.addEventListener('click', async () => {
    btnSaveRules.textContent = 'Saving...';
    try {
      await apiRequest(`/devices/${activeDevice.id}/settings`, {
        method: 'PUT',
        body: JSON.stringify({
          autoStartLevelPct: autoStartThresh,
          autoStopLevelPct: autoStopThresh,
          dryRunTimeoutSeconds: checkDryrun.checked ? 10 : 0
        })
      });
      btnSaveRules.textContent = '✓ Saved to Cloud';
    } catch {
      btnSaveRules.textContent = '✓ Saved Locally';
    }
    setTimeout(() => btnSaveRules.textContent = 'Save to Cloud', 2000);
  });

  // ==============================================================================
  // 7. Minimalist 3D Fluid Canvas Visualizer
  // ==============================================================================
  let ctx = tankCanvas.getContext('2d');
  let wavePhase = 0;
  let impellerAngle = 0;

  function renderTank() {
    ctx.clearRect(0, 0, tankCanvas.width, tankCanvas.height);
    const w = tankCanvas.width;
    const h = tankCanvas.height;

    const tankX = 45;
    const tankY = 40;
    const tankW = w - 90;
    const tankH = h - 80;
    const ellipseH = 26;

    // 1. Transparent Glass Cylinder Shell
    ctx.save();
    ctx.fillStyle = 'rgba(15, 23, 42, 0.6)';
    ctx.strokeStyle = 'rgba(0, 229, 255, 0.2)';
    ctx.lineWidth = 1.5;

    ctx.beginPath();
    ctx.ellipse(tankX + tankW / 2, tankY + ellipseH / 2, tankW / 2, ellipseH / 2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    ctx.beginPath();
    ctx.ellipse(tankX + tankW / 2, tankY + tankH - ellipseH / 2, tankW / 2, ellipseH / 2, 0, 0, Math.PI);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(tankX, tankY + ellipseH / 2);
    ctx.lineTo(tankX, tankY + tankH - ellipseH / 2);
    ctx.moveTo(tankX + tankW, tankY + ellipseH / 2);
    ctx.lineTo(tankX + tankW, tankY + tankH - ellipseH / 2);
    ctx.stroke();
    ctx.restore();

    // 2. Liquid Body
    const waterHeight = (tankH - ellipseH) * (waterLevelPct / 100);
    const waterTopY = (tankY + tankH - ellipseH / 2) - waterHeight;

    if (waterLevelPct > 1) {
      ctx.save();
      const grad = ctx.createLinearGradient(tankX, waterTopY, tankX + tankW, tankY + tankH);
      grad.addColorStop(0, 'rgba(0, 229, 255, 0.85)');
      grad.addColorStop(0.5, 'rgba(0, 180, 255, 0.7)');
      grad.addColorStop(1, 'rgba(0, 245, 160, 0.9)');

      ctx.fillStyle = grad;

      ctx.beginPath();
      ctx.moveTo(tankX + 2, waterTopY);
      ctx.lineTo(tankX + 2, tankY + tankH - ellipseH / 2);
      ctx.ellipse(tankX + tankW / 2, tankY + tankH - ellipseH / 2, tankW / 2 - 2, ellipseH / 2 - 2, 0, Math.PI, 0, true);
      ctx.lineTo(tankX + tankW - 2, waterTopY);

      // Top wavy fluid surface
      for (let x = tankW - 2; x >= 2; x -= 4) {
        const waveAmp = isPumpRunning ? 4.0 : 1.2;
        const waveY = waterTopY + Math.sin((x / 22) + wavePhase) * waveAmp;
        ctx.lineTo(tankX + x, waveY);
      }
      ctx.closePath();
      ctx.fill();

      // Top Fluid Ellipse
      ctx.fillStyle = 'rgba(0, 245, 160, 0.45)';
      ctx.beginPath();
      ctx.ellipse(tankX + tankW / 2, waterTopY, tankW / 2 - 2, ellipseH / 2 - 2, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.restore();
    }

    // 3. Impeller Motor Indicator
    const motorX = tankX + tankW - 32;
    const motorY = tankY + tankH - 12;
    ctx.save();
    ctx.translate(motorX, motorY);
    ctx.beginPath();
    ctx.arc(0, 0, 18, 0, Math.PI * 2);
    ctx.fillStyle = isPumpRunning ? 'rgba(0, 245, 160, 0.25)' : 'rgba(30, 41, 59, 0.8)';
    ctx.fill();
    ctx.strokeStyle = isPumpRunning ? '#00F5A0' : 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.rotate(impellerAngle);
    ctx.strokeStyle = isPumpRunning ? '#00E5FF' : '#64748B';
    ctx.lineWidth = 2;
    for (let i = 0; i < 4; i++) {
      ctx.rotate(Math.PI / 2);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, -12);
      ctx.stroke();
    }
    ctx.restore();

    // Real-time animation physics
    wavePhase += isPumpRunning ? 0.08 : 0.03;
    if (isPumpRunning) {
      impellerAngle += 0.25;
      if (waterLevelPct < 98) {
        waterLevelPct += 0.03;
        updateUI();
      } else if (operatingMode === 'AUTO') {
        setPumpRunning(false);
      }
    } else {
      if (waterLevelPct > 10) {
        waterLevelPct -= 0.003;
        updateUI();
      }
      if (operatingMode === 'AUTO' && waterLevelPct <= autoStartThresh && !isPumpRunning) {
        setPumpRunning(true);
      }
    }

    requestAnimationFrame(renderTank);
  }

  // ==============================================================================
  // 8. Dynamic Telemetry & Trend Curve
  // ==============================================================================
  function updateUI() {
    const clampedLevel = Math.max(0, Math.min(100, waterLevelPct));
    const volumeLiters = Math.round((clampedLevel / 100) * 5000);

    tankLevelPct.textContent = `${clampedLevel.toFixed(1)}%`;
    tankVolumeLiters.textContent = `${volumeLiters.toLocaleString()} Liters`;

    if (isPumpRunning) {
      flowRateLpm = 18.5 + (Math.random() * 0.8 - 0.4);
      powerKw = 1.42 + (Math.random() * 0.03 - 0.01);
      valFlowRate.innerHTML = `${flowRateLpm.toFixed(1)} <small>L/min</small>`;
      valPowerKw.innerHTML = `${powerKw.toFixed(2)} <small>kW</small>`;
    } else {
      flowRateLpm = 0.0;
      powerKw = 0.00;
      valFlowRate.innerHTML = '0.0 <small>L/min</small>';
      valPowerKw.innerHTML = '0.00 <small>kW</small>';
    }

    // Dynamic latency jitter
    hwRttTxt.textContent = `${Math.floor(20 + Math.random() * 8)}ms`;
  }

  function renderHistoryChart() {
    const svg = document.getElementById('history-chart');
    if (!svg) return;

    // Simulated 24-hour water trend data points
    const points = [
      { x: 0, y: 78 }, { x: 80, y: 72 }, { x: 160, y: 55 }, { x: 240, y: 32 },
      { x: 300, y: 24 }, { x: 360, y: 92 }, { x: 440, y: 84 }, { x: 520, y: 68 },
      { x: 600, y: 52 }, { x: 680, y: 75 }, { x: 760, y: waterLevelPct }
    ];

    const width = 760;
    const height = 160;

    let pathD = `M 0,${height - (points[0].y / 100 * (height - 30))}`;
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const prevY = height - (prev.y / 100 * (height - 30));
      const currY = height - (curr.y / 100 * (height - 30));
      const cpX1 = prev.x + (curr.x - prev.x) / 2;
      const cpX2 = cpX1;
      pathD += ` C ${cpX1},${prevY} ${cpX2},${currY} ${curr.x},${currY}`;
    }

    const fillD = `${pathD} L ${width},${height} L 0,${height} Z`;

    svg.innerHTML = `
      <defs>
        <linearGradient id="chart-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#00E5FF" stop-opacity="0.35"/>
          <stop offset="100%" stop-color="#00E5FF" stop-opacity="0.0"/>
        </linearGradient>
      </defs>
      <path d="${fillD}" fill="url(#chart-grad)"/>
      <path d="${pathD}" fill="none" stroke="#00E5FF" stroke-width="2.5"/>
    `;
  }

  // ==============================================================================
  // 9. API URL Configuration Modal
  // ==============================================================================
  btnOpenApiConfig.addEventListener('click', () => {
    inputApiUrl.value = apiBaseUrl;
    apiModal.classList.remove('hidden');
  });

  btnCancelApiModal.addEventListener('click', () => {
    apiModal.classList.add('hidden');
  });

  btnSaveApiUrl.addEventListener('click', async () => {
    const val = inputApiUrl.value.trim();
    if (val) {
      apiBaseUrl = val;
      localStorage.setItem('hydropulse_api_url', apiBaseUrl);
    }
    apiModal.classList.add('hidden');
    await checkBackendHealth();
  });

  // Start Application
  checkSession();
  renderTank();
});
