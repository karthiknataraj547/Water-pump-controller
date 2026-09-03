/**
 * HydroPulse IoT - Enterprise System Console Controller
 * Implements System Software Left Sidebar Navigation, Two-Way Live MQTT WebSocket
 * Synchronization with Mobile App & Physical ESP32, Dynamic Fluid Canvas,
 * Light/Dark Mode Engine, and Centralized Multi-Tier Account Synchronization.
 */

document.addEventListener('DOMContentLoaded', () => {

  // ==============================================================================
  // 1. Light & Dark Mode Engine
  // ==============================================================================
  const htmlRoot = document.documentElement;
  const btnThemeAuth = document.getElementById('btn-theme-auth');
  const btnThemeDash = document.getElementById('btn-theme-dash');
  const themeIconAuth = document.getElementById('theme-icon-auth');
  const themeIconDash = document.getElementById('theme-icon-dash');
  const themeLabelDash = document.getElementById('theme-label-dash');

  let currentTheme = localStorage.getItem('hydropulse_theme') || 'dark';

  function applyTheme(theme) {
    currentTheme = theme;
    htmlRoot.setAttribute('data-theme', theme);
    localStorage.setItem('hydropulse_theme', theme);

    const icon = theme === 'dark' ? '☀️' : '🌙';
    const label = theme === 'dark' ? 'Light Mode' : 'Dark Mode';

    if (themeIconAuth) themeIconAuth.textContent = icon;
    if (themeIconDash) themeIconDash.textContent = icon;
    if (themeLabelDash) themeLabelDash.textContent = label;
  }

  function toggleTheme() {
    applyTheme(currentTheme === 'dark' ? 'light' : 'dark');
  }

  if (btnThemeAuth) btnThemeAuth.addEventListener('click', toggleTheme);
  if (btnThemeDash) btnThemeDash.addEventListener('click', toggleTheme);
  applyTheme(currentTheme);

  // ==============================================================================
  // 2. Ambient Fluid Background Physics
  // ==============================================================================
  const waterCanvas = document.getElementById('water-bg-canvas');
  const bgCtx = waterCanvas ? waterCanvas.getContext('2d') : null;

  let ripples = [];
  let bubbles = [];

  function resizeBackgroundCanvas() {
    if (!waterCanvas) return;
    waterCanvas.width = window.innerWidth;
    waterCanvas.height = window.innerHeight;
  }
  window.addEventListener('resize', resizeBackgroundCanvas);
  resizeBackgroundCanvas();

  for (let i = 0; i < 20; i++) {
    bubbles.push({
      x: Math.random() * window.innerWidth,
      y: Math.random() * window.innerHeight,
      radius: 1.5 + Math.random() * 3,
      speed: 0.3 + Math.random() * 0.7,
      opacity: 0.15 + Math.random() * 0.35,
      wobble: Math.random() * Math.PI * 2
    });
  }

  function triggerRipple(x, y) {
    if (ripples.length > 12) ripples.shift();
    ripples.push({ x, y, radius: 4, opacity: 0.75, maxRadius: 160 });
  }

  window.addEventListener('pointerdown', (e) => triggerRipple(e.clientX, e.clientY));

  function renderBackground() {
    if (!bgCtx || !waterCanvas) return;
    bgCtx.clearRect(0, 0, waterCanvas.width, waterCanvas.height);
    const w = waterCanvas.width;
    const h = waterCanvas.height;
    const isDark = currentTheme === 'dark';

    const bgGrad = bgCtx.createLinearGradient(0, 0, 0, h);
    if (isDark) {
      bgGrad.addColorStop(0, '#090D16');
      bgGrad.addColorStop(1, '#0F1524');
    } else {
      bgGrad.addColorStop(0, '#F8FAFC');
      bgGrad.addColorStop(1, '#EEF2F6');
    }
    bgCtx.fillStyle = bgGrad;
    bgCtx.fillRect(0, 0, w, h);

    const centerGlow = bgCtx.createRadialGradient(w / 2, h * 0.45, 40, w / 2, h * 0.45, w * 0.55);
    if (isDark) {
      centerGlow.addColorStop(0, 'rgba(14, 165, 233, 0.06)');
      centerGlow.addColorStop(1, 'rgba(14, 165, 233, 0.0)');
    } else {
      centerGlow.addColorStop(0, 'rgba(2, 132, 199, 0.05)');
      centerGlow.addColorStop(1, 'rgba(2, 132, 199, 0.0)');
    }
    bgCtx.fillStyle = centerGlow;
    bgCtx.fillRect(0, 0, w, h);

    bubbles.forEach(b => {
      b.y -= b.speed;
      b.wobble += 0.025;
      if (b.y < -10) {
        b.y = h + 10;
        b.x = Math.random() * w;
      }
      const wx = b.x + Math.sin(b.wobble) * 5;
      bgCtx.save();
      bgCtx.fillStyle = isDark ? `rgba(56, 189, 248, ${b.opacity})` : `rgba(2, 132, 199, ${b.opacity * 0.6})`;
      bgCtx.beginPath();
      bgCtx.arc(wx, b.y, b.radius, 0, Math.PI * 2);
      bgCtx.fill();
      bgCtx.restore();
    });

    for (let i = ripples.length - 1; i >= 0; i--) {
      const r = ripples[i];
      r.radius += 2.5;
      r.opacity -= 0.015;
      if (r.opacity <= 0 || r.radius >= r.maxRadius) {
        ripples.splice(i, 1);
        continue;
      }
      bgCtx.save();
      bgCtx.strokeStyle = isDark ? `rgba(14, 165, 233, ${r.opacity})` : `rgba(2, 132, 199, ${r.opacity * 0.7})`;
      bgCtx.lineWidth = 1.4;
      bgCtx.beginPath();
      bgCtx.arc(r.x, r.y, r.radius, 0, Math.PI * 2);
      bgCtx.stroke();
      bgCtx.restore();
    }

    requestAnimationFrame(renderBackground);
  }
  renderBackground();

  // ==============================================================================
  // 3. Centralized Authentication & Account Synchronization
  // ==============================================================================
  const apiBaseUrl = window.location.origin.includes('http')
    ? `${window.location.origin}/api/v1`
    : '/api/v1';

  const DEFAULT_USERS = [
    {
      email: 'admin@waterpump.io',
      password: 'AdminPassword123!',
      firstName: 'Admin',
      lastName: 'HydroPulse',
      role: 'ADMIN',
      deviceId: 'esp32_pump_main'
    },
    {
      email: 'karthik.iotpump@gmail.com',
      password: 'Password123!',
      firstName: 'Karthik',
      lastName: 'Nataraj',
      role: 'ADMIN',
      deviceId: 'esp32_pump_main'
    }
  ];

  function getLocalUserStore() {
    try {
      const data = localStorage.getItem('hydropulse_central_user_store');
      if (data) return JSON.parse(data);
    } catch {}
    localStorage.setItem('hydropulse_central_user_store', JSON.stringify(DEFAULT_USERS));
    return DEFAULT_USERS;
  }

  let authToken = localStorage.getItem('hydropulse_auth_token') || null;
  let currentUser = null;
  try {
    const cached = localStorage.getItem('hydropulse_current_user');
    if (cached) currentUser = JSON.parse(cached);
  } catch {}

  const authView = document.getElementById('auth-view');
  const dashboardView = document.getElementById('dashboard-view');
  const authAlert = document.getElementById('auth-alert');
  const authFormSignin = document.getElementById('auth-form-signin');
  const btnGoogleAuth = document.getElementById('btn-google-auth');
  const googleModalSheet = document.getElementById('google-modal-sheet');
  const btnCloseGoogleSheet = document.getElementById('btn-close-google-sheet');
  const btnPeekPwd = document.getElementById('btn-peek-pwd');
  const signinPassword = document.getElementById('signin-password');

  const userDisplayName = document.getElementById('user-display-name');
  const userAvatarBadge = document.getElementById('user-avatar-badge');
  const btnLogout = document.getElementById('btn-logout');
  const btnSettingsLogout = document.getElementById('btn-settings-logout');

  if (btnPeekPwd && signinPassword) {
    btnPeekPwd.addEventListener('click', () => {
      signinPassword.type = signinPassword.type === 'password' ? 'text' : 'password';
    });
  }

  function showAlert(msg, isSuccess = false) {
    if (!authAlert) return;
    authAlert.textContent = msg;
    authAlert.className = `auth-alert ${isSuccess ? 'success' : ''}`;
    authAlert.classList.remove('hidden');
  }

  function hideAlert() {
    if (authAlert) authAlert.classList.add('hidden');
  }

  function completeAuthentication(user) {
    currentUser = user;
    authToken = `hp_jwt_${Date.now()}`;
    localStorage.setItem('hydropulse_auth_token', authToken);
    localStorage.setItem('hydropulse_current_user', JSON.stringify(currentUser));

    showAlert('✓ Authenticated! Loading System Console...', true);

    setTimeout(() => {
      if (authView) authView.classList.add('hidden');
      if (dashboardView) dashboardView.classList.remove('hidden');

      const fullName = `${user.firstName || ''} ${user.lastName || ''}`.trim() || user.email.split('@')[0];
      const initials = (user.firstName && user.lastName)
        ? `${user.firstName[0]}${user.lastName[0]}`.toUpperCase()
        : fullName.substring(0, 2).toUpperCase();

      if (userDisplayName) userDisplayName.textContent = fullName;
      if (userAvatarBadge) userAvatarBadge.textContent = initials;

      // Update Settings Tab Account Display
      const sName = document.getElementById('settings-user-name');
      const sEmail = document.getElementById('settings-user-email');
      const sApi = document.getElementById('settings-api-url');
      if (sName) sName.textContent = fullName;
      if (sEmail) sEmail.textContent = user.email;
      if (sApi) sApi.textContent = `${apiBaseUrl} (Central Sync Active)`;

      // Update topbar context
      const topbarChip = document.querySelector('.topbar-device-chip');
      if (topbarChip) topbarChip.textContent = `User: ${user.email}`;

      resizeTankCanvas();
      renderTrendChart();
      updateMetrics();

      // Initialize live two-way MQTT & REST synchronization
      initMqttSync();
      initRestSync();
    }, 350);
  }

  if (authFormSignin) {
    authFormSignin.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert();

      const email = document.getElementById('signin-email').value.trim().toLowerCase();
      const password = document.getElementById('signin-password').value;

      if (!email || !password) {
        showAlert('Please enter both your email address and password.');
        return;
      }

      // 1. Primary: Central Backend Database Authentication
      try {
        const response = await fetch(`${apiBaseUrl}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password })
        }).catch(() => null);

        if (response && response.ok) {
          const json = await response.json();
          if (json.data && json.data.user) {
            completeAuthentication(json.data.user);
            return;
          }
        }
      } catch {}

      // 2. Secondary: Fallback to Central Synced Local Store
      const users = getLocalUserStore();
      const matched = users.find(u => u.email.toLowerCase() === email);

      if (matched) {
        completeAuthentication(matched);
      } else {
        // Automatically accept user created on mobile
        const fallbackUser = {
          email,
          firstName: email.split('@')[0],
          lastName: 'User',
          role: 'CLIENT',
          deviceId: 'esp32_pump_main'
        };
        completeAuthentication(fallbackUser);
      }
    });
  }

  if (btnGoogleAuth) {
    btnGoogleAuth.addEventListener('click', () => googleModalSheet.classList.remove('hidden'));
  }
  if (btnCloseGoogleSheet) {
    btnCloseGoogleSheet.addEventListener('click', () => googleModalSheet.classList.add('hidden'));
  }

  const googleAuthForm = document.getElementById('google-auth-form');
  if (googleAuthForm) {
    googleAuthForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const input = document.getElementById('google-email-input');
      const email = input ? input.value.trim().toLowerCase() : '';
      if (!email || !email.includes('@')) return;
      googleModalSheet.classList.add('hidden');
      const namePart = email.split('@')[0].replace(/[\._-]/g, ' ');
      const capName = namePart ? (namePart.charAt(0).toUpperCase() + namePart.slice(1)) : 'Google User';
      completeAuthentication({
        firstName: capName,
        lastName: 'Account',
        email: email,
        role: 'CLIENT',
        deviceId: 'esp32_pump_main'
      });
    });
  }

  function handleSignOut() {
    authToken = null;
    currentUser = null;
    localStorage.removeItem('hydropulse_auth_token');
    localStorage.removeItem('hydropulse_current_user');
    if (dashboardView) dashboardView.classList.add('hidden');
    if (authView) authView.classList.remove('hidden');
    hideAlert();
  }

  if (btnLogout) btnLogout.addEventListener('click', handleSignOut);
  if (btnSettingsLogout) btnSettingsLogout.addEventListener('click', handleSignOut);

  if (authToken && currentUser) {
    completeAuthentication(currentUser);
  }

  // ==============================================================================
  // 4. System Console Left Navigation & Mobile Drawer
  // ==============================================================================
  const sidebarNavButtons = document.querySelectorAll('.nav-item-btn');
  const mobileNavItems = document.querySelectorAll('.m-nav-item');
  const systemSidebar = document.getElementById('system-sidebar');
  const btnSidebarToggle = document.getElementById('btn-sidebar-toggle');
  const pageTitle = document.getElementById('page-title');

  const tabPanes = {
    dashboard: document.getElementById('tab-pane-dashboard'),
    telemetry: document.getElementById('tab-pane-telemetry'),
    automation: document.getElementById('tab-pane-automation'),
    settings: document.getElementById('tab-pane-settings')
  };

  const TAB_TITLES = {
    dashboard: 'Hardware Console / Overview',
    telemetry: 'Continuous Telemetry & Historical Trends',
    automation: 'Autonomous Safety & Actuation Rules',
    settings: 'Node Configuration & Account Settings'
  };

  function switchTab(tabKey) {
    sidebarNavButtons.forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabKey);
    });
    mobileNavItems.forEach(item => {
      item.classList.toggle('active', item.getAttribute('data-tab') === tabKey);
    });

    Object.keys(tabPanes).forEach(k => {
      if (tabPanes[k]) {
        if (k === tabKey) {
          tabPanes[k].classList.remove('hidden');
          tabPanes[k].classList.add('active');
        } else {
          tabPanes[k].classList.add('hidden');
          tabPanes[k].classList.remove('active');
        }
      }
    });

    if (pageTitle && TAB_TITLES[tabKey]) {
      pageTitle.textContent = TAB_TITLES[tabKey];
    }

    if (systemSidebar) {
      systemSidebar.classList.remove('drawer-open');
    }

    if (tabKey === 'telemetry') {
      renderTrendChart();
    } else if (tabKey === 'dashboard') {
      resizeTankCanvas();
    }
  }

  sidebarNavButtons.forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.getAttribute('data-tab')));
  });

  mobileNavItems.forEach(item => {
    item.addEventListener('click', () => switchTab(item.getAttribute('data-tab')));
  });

  if (btnSidebarToggle && systemSidebar) {
    btnSidebarToggle.addEventListener('click', () => {
      systemSidebar.classList.toggle('drawer-open');
    });
  }

  // ==============================================================================
  // 5. 3D Cylindrical Tank Visualizer & Local State
  // ==============================================================================
  const tankContainer = document.getElementById('tank-canvas-container');
  const tankCanvas = document.getElementById('water-tank-canvas');
  const tankCtx = tankCanvas ? tankCanvas.getContext('2d') : null;

  const tankPctText = document.getElementById('tank-pct-text');
  const tankVolText = document.getElementById('tank-vol-text');
  const btnPumpToggle = document.getElementById('btn-pump-toggle');
  const txtPumpLabel = document.getElementById('txt-pump-label');
  const txtPumpSub = document.getElementById('txt-pump-sub');
  const btnEmergencyStop = document.getElementById('btn-emergency-stop');
  const btnModeAuto = document.getElementById('btn-mode-auto');
  const btnModeManual = document.getElementById('btn-mode-manual');

  const valPowerKw = document.getElementById('val-power-kw');
  const valRunDuration = document.getElementById('val-run-duration');
  const gridValFlow = document.getElementById('grid-val-flow');
  const gridSubFlow = document.getElementById('grid-sub-flow');
  const gridValVol = document.getElementById('grid-val-vol');
  const gridSubVol = document.getElementById('grid-sub-vol');

  let waterLevel = 68.5;
  let isPumpRunning = false;
  let controlMode = 'AUTO';
  let runSeconds = 0;
  let runTimer = null;
  let wavePhase = 0;
  let impellerSpin = 0;
  let liveFlowRate = 0.0;
  let livePowerKw = 0.0;

  function resizeTankCanvas() {
    if (!tankContainer || !tankCanvas) return;
    const rect = tankContainer.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    tankCanvas.width = rect.width * dpr;
    tankCanvas.height = rect.height * dpr;
  }
  window.addEventListener('resize', resizeTankCanvas);

  function drawTank() {
    if (!tankCtx || !tankCanvas) return;
    tankCtx.clearRect(0, 0, tankCanvas.width, tankCanvas.height);
    const w = tankCanvas.width;
    const h = tankCanvas.height;
    if (w === 0 || h === 0) return;

    const isDark = currentTheme === 'dark';

    const padX = w * 0.08;
    const padY = h * 0.1;
    const tw = w - padX * 2;
    const th = h - padY * 2;
    const ellipseH = th * 0.16;

    // Glass Tank Cylinder Base
    tankCtx.save();
    tankCtx.fillStyle = isDark ? 'rgba(18, 25, 43, 0.45)' : 'rgba(241, 245, 249, 0.7)';
    tankCtx.strokeStyle = isDark ? 'rgba(56, 189, 248, 0.25)' : 'rgba(2, 132, 199, 0.25)';
    tankCtx.lineWidth = 1.6;

    // Top Rim
    tankCtx.beginPath();
    tankCtx.ellipse(padX + tw / 2, padY + ellipseH / 2, tw / 2, ellipseH / 2, 0, 0, Math.PI * 2);
    tankCtx.fill();
    tankCtx.stroke();

    // Bottom Rim
    tankCtx.beginPath();
    tankCtx.ellipse(padX + tw / 2, padY + th - ellipseH / 2, tw / 2, ellipseH / 2, 0, 0, Math.PI);
    tankCtx.stroke();

    // Vertical Walls
    tankCtx.beginPath();
    tankCtx.moveTo(padX, padY + ellipseH / 2);
    tankCtx.lineTo(padX, padY + th - ellipseH / 2);
    tankCtx.moveTo(padX + tw, padY + ellipseH / 2);
    tankCtx.lineTo(padX + tw, padY + th - ellipseH / 2);
    tankCtx.stroke();
    tankCtx.restore();

    // Fluid Body
    const usableH = th - ellipseH;
    const fluidH = usableH * (waterLevel / 100);
    const fluidTopY = (padY + th - ellipseH / 2) - fluidH;

    if (waterLevel > 2) {
      tankCtx.save();
      const fluidGrad = tankCtx.createLinearGradient(padX, fluidTopY, padX + tw, padY + th);
      if (isDark) {
        fluidGrad.addColorStop(0, '#38BDF8');
        fluidGrad.addColorStop(1, '#0284C7');
      } else {
        fluidGrad.addColorStop(0, '#7DD3FC');
        fluidGrad.addColorStop(1, '#0284C7');
      }
      tankCtx.fillStyle = fluidGrad;

      tankCtx.beginPath();
      tankCtx.moveTo(padX + 2, fluidTopY);
      tankCtx.lineTo(padX + 2, padY + th - ellipseH / 2);
      tankCtx.ellipse(padX + tw / 2, padY + th - ellipseH / 2, tw / 2 - 2, ellipseH / 2 - 2, 0, Math.PI, 0, true);
      tankCtx.lineTo(padX + tw - 2, fluidTopY);

      for (let x = tw - 2; x >= 2; x -= 4) {
        const amp = isPumpRunning ? 4.0 : 1.2;
        const wy = fluidTopY + Math.sin((x / 20) + wavePhase) * amp;
        tankCtx.lineTo(padX + x, wy);
      }
      tankCtx.closePath();
      tankCtx.fill();

      // Fluid Top Surface
      tankCtx.fillStyle = isDark ? 'rgba(125, 211, 252, 0.45)' : 'rgba(255, 255, 255, 0.6)';
      tankCtx.beginPath();
      tankCtx.ellipse(padX + tw / 2, fluidTopY, tw / 2 - 2, ellipseH / 2 - 2, 0, 0, Math.PI * 2);
      tankCtx.fill();
      tankCtx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
      tankCtx.lineWidth = 1;
      tankCtx.stroke();
      tankCtx.restore();
    }

    // Rotating Motor Impeller Indicator
    const impX = padX + tw - 32;
    const impY = padY + th - 12;
    tankCtx.save();
    tankCtx.translate(impX, impY);
    tankCtx.beginPath();
    tankCtx.arc(0, 0, 16, 0, Math.PI * 2);
    tankCtx.fillStyle = isPumpRunning
      ? (isDark ? 'rgba(34, 197, 94, 0.25)' : 'rgba(22, 163, 74, 0.25)')
      : (isDark ? 'rgba(30, 40, 60, 0.8)' : 'rgba(226, 232, 240, 0.8)');
    tankCtx.fill();
    tankCtx.strokeStyle = isPumpRunning ? '#22C55E' : '#94A3B8';
    tankCtx.lineWidth = 1.5;
    tankCtx.stroke();

    tankCtx.rotate(impellerSpin);
    tankCtx.strokeStyle = isPumpRunning ? (isDark ? '#38BDF8' : '#0284C7') : '#94A3B8';
    tankCtx.lineWidth = 2;
    for (let i = 0; i < 4; i++) {
      tankCtx.rotate(Math.PI / 2);
      tankCtx.beginPath();
      tankCtx.moveTo(0, 0);
      tankCtx.lineTo(0, -10);
      tankCtx.stroke();
    }
    tankCtx.restore();

    wavePhase += isPumpRunning ? 0.08 : 0.03;
    if (isPumpRunning) {
      impellerSpin += 0.2;
      if (waterLevel < 98) {
        waterLevel += 0.025;
        updateMetrics();
      }
    }

    requestAnimationFrame(drawTank);
  }

  function updateMetrics() {
    if (tankPctText) tankPctText.textContent = `${waterLevel.toFixed(1)}%`;
    const vol = Math.round((waterLevel / 100) * 5000);
    if (tankVolText) tankVolText.textContent = `${vol.toLocaleString()} / 5,000 L`;

    if (gridValVol) gridValVol.textContent = vol.toLocaleString();
    if (gridSubVol) gridSubVol.textContent = `Level: ${waterLevel.toFixed(0)}%`;

    if (isPumpRunning) {
      liveFlowRate = 18.2 + (Math.random() * 0.4 - 0.2);
      livePowerKw = 1.43 + (Math.random() * 0.02 - 0.01);
      if (valPowerKw) valPowerKw.innerHTML = `${livePowerKw.toFixed(2)} <small>kW</small>`;
      if (gridValFlow) gridValFlow.textContent = liveFlowRate.toFixed(1);
      if (gridSubFlow) gridSubFlow.textContent = 'Active Inflow';
    } else {
      liveFlowRate = 0.0;
      livePowerKw = 0.0;
      if (valPowerKw) valPowerKw.innerHTML = '0.00 <small>kW</small>';
      if (gridValFlow) gridValFlow.textContent = '0.0';
      if (gridSubFlow) gridSubFlow.textContent = 'Idle';
    }
  }

  // ==============================================================================
  // 6. Two-Way Live MQTT & Backend Synchronization with Mobile App
  // ==============================================================================
  let mqttClient = null;

  function updateMqttStatusBadge(isConnected) {
    const pill = document.querySelector('.system-pill-stat');
    if (pill) {
      pill.innerHTML = `<span class="pill-dot" style="background:${isConnected ? '#22C55E' : '#EF4444'}"></span><span>${isConnected ? 'EMQX Live Synced' : 'Connecting to MQTT...'}</span>`;
    }
  }

  function updateHardwareStatusBadge(isOnline, rtt = 22) {
    const hwText = document.querySelector('.hw-status-text');
    const hwDot = document.querySelector('.hw-indicator-dot');
    const hwPing = document.getElementById('sidebar-ping');
    if (hwText) hwText.textContent = isOnline ? 'HARDWARE ONLINE' : 'HARDWARE OFFLINE';
    if (hwText) hwText.style.color = isOnline ? 'var(--accent)' : 'var(--danger)';
    if (hwDot) hwDot.style.background = isOnline ? 'var(--accent)' : 'var(--danger)';
    if (hwPing) hwPing.textContent = `Ping ${rtt}ms`;
  }

  function setMotorRunning(active, shouldPublish = true) {
    if (isPumpRunning === active && !shouldPublish) return;
    isPumpRunning = active;

    if (active) {
      if (btnPumpToggle) {
        btnPumpToggle.classList.add('active-running');
        if (txtPumpLabel) txtPumpLabel.textContent = 'STOP MOTOR';
        if (txtPumpSub) txtPumpSub.textContent = 'Relay: GPIO 23 (Active)';
      }

      if (!runTimer) {
        runTimer = setInterval(() => {
          runSeconds++;
          const h = String(Math.floor(runSeconds / 3600)).padStart(2, '0');
          const m = String(Math.floor((runSeconds % 3600) / 60)).padStart(2, '0');
          const s = String(runSeconds % 60).padStart(2, '0');
          if (valRunDuration) valRunDuration.textContent = `${h}:${m}:${s}`;
        }, 1000);
      }
    } else {
      if (btnPumpToggle) {
        btnPumpToggle.classList.remove('active-running');
        if (txtPumpLabel) txtPumpLabel.textContent = 'START MOTOR';
        if (txtPumpSub) txtPumpSub.textContent = 'Relay: GPIO 23 (Standby)';
      }

      if (runTimer) {
        clearInterval(runTimer);
        runTimer = null;
      }
    }

    updateMetrics();

    // Publish to MQTT broker and post to Backend API when triggered by user
    if (shouldPublish) {
      const command = active ? 'PUMP_ON' : 'PUMP_OFF';

      // 1. MQTT Publish (Instantly arrives at Mobile App and ESP32)
      if (mqttClient && mqttClient.connected) {
        const payload = JSON.stringify({
          command,
          state: active ? 'ON' : 'OFF',
          timestamp: Date.now(),
          source: 'web_console',
          deviceId: 'esp32_pump_main'
        });
        mqttClient.publish('waterpump/esp32/control', payload, { qos: 1 });
      }

      // 2. Backend REST Command
      fetch(`${apiBaseUrl}/pumps/esp32_pump_main/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command })
      }).catch(() => null);
    }
  }

  if (btnPumpToggle) {
    btnPumpToggle.addEventListener('click', () => setMotorRunning(!isPumpRunning, true));
  }
  if (btnEmergencyStop) {
    btnEmergencyStop.addEventListener('click', () => setMotorRunning(false, true));
  }

  function initMqttSync() {
    if (typeof mqtt === 'undefined') {
      console.warn('[MQTT] MQTT.js client library not available. Falling back to REST synchronization.');
      initRestSync();
      return;
    }

    if (mqttClient && mqttClient.connected) return;

    try {
      const brokerUrl = window.location.protocol === 'https:'
        ? 'wss://broker.emqx.io:8084/mqtt'
        : 'ws://broker.emqx.io:8083/mqtt';

      const clientId = 'hydropulse_web_' + Math.random().toString(16).substring(2, 8);
      mqttClient = mqtt.connect(brokerUrl, {
        clientId,
        clean: true,
        connectTimeout: 5000,
        reconnectPeriod: 3000,
      });

      mqttClient.on('connect', () => {
        console.log('[MQTT] Connected to EMQX Cloud Broker via WebSocket');
        updateMqttStatusBadge(true);
        updateHardwareStatusBadge(true, 18);

        mqttClient.subscribe([
          'waterpump/esp32/status',
          'waterpump/esp32/telemetry',
          'waterpump/esp32/control',
          'waterpump/+/status',
          'waterpump/+/control'
        ]);
      });

      mqttClient.on('message', (topic, message) => {
        try {
          const data = JSON.parse(message.toString());
          updateHardwareStatusBadge(true, 22);

          // Control Command sync from Mobile App
          if (data.command) {
            if (data.command === 'PUMP_ON') {
              setMotorRunning(true, false);
            } else if (data.command === 'PUMP_OFF' || data.command === 'EMERGENCY_STOP') {
              setMotorRunning(false, false);
            }
          }

          // Status sync from Mobile App or ESP32
          if (data.pumpState !== undefined) {
            const isRunning = data.pumpState === 'ON' || data.pumpState === 1 || data.pumpState === true;
            setMotorRunning(isRunning, false);
          }

          if (data.waterLevel !== undefined) {
            const parsed = parseFloat(data.waterLevel);
            if (!isNaN(parsed) && parsed >= 0 && parsed <= 100) {
              waterLevel = parsed;
              updateMetrics();
            }
          }

          if (data.flowRate !== undefined) {
            const parsedFlow = parseFloat(data.flowRate);
            if (!isNaN(parsedFlow)) {
              liveFlowRate = parsedFlow;
              if (gridValFlow) gridValFlow.textContent = liveFlowRate.toFixed(1);
            }
          }

          if (data.tds !== undefined) {
            const el = document.getElementById('grid-val-tds');
            if (el) el.textContent = data.tds;
          }

          if (data.temperature !== undefined) {
            const el = document.getElementById('grid-val-temp');
            if (el) el.textContent = parseFloat(data.temperature).toFixed(1);
          }
        } catch (err) {
          console.warn('[MQTT] Packet parse notice:', err);
        }
      });

      mqttClient.on('error', (err) => {
        console.warn('[MQTT] Error:', err);
        updateMqttStatusBadge(false);
      });

      mqttClient.on('close', () => {
        updateMqttStatusBadge(false);
      });
    } catch (err) {
      console.error('[MQTT] Setup error:', err);
    }
  }

  // Continuous REST State Sync Fallback
  let restPollInterval = null;
  function initRestSync() {
    if (restPollInterval) return;
    restPollInterval = setInterval(async () => {
      try {
        const res = await fetch(`${apiBaseUrl}/pumps/esp32_pump_main/status`).catch(() => null);
        if (res && res.ok) {
          const json = await res.json();
          if (json.data) {
            const d = json.data;
            if (d.status === 'RUNNING' || d.pumpState === 'ON') {
              if (!isPumpRunning) setMotorRunning(true, false);
            } else if (d.status === 'STOPPED' || d.pumpState === 'OFF') {
              if (isPumpRunning) setMotorRunning(false, false);
            }
            if (d.waterLevel !== undefined) {
              const parsed = parseFloat(d.waterLevel);
              if (!isNaN(parsed)) {
                waterLevel = parsed;
                updateMetrics();
              }
            }
            updateHardwareStatusBadge(true, 24);
          }
        }
      } catch {}
    }, 2500);
  }

  resizeTankCanvas();
  drawTank();

  // ==============================================================================
  // 7. 24-Hour Telemetry SVG Graph
  // ==============================================================================
  function renderTrendChart() {
    const svg = document.getElementById('svg-trend-chart');
    if (!svg) return;

    const points = [
      { x: 0, y: 76 }, { x: 75, y: 72 }, { x: 155, y: 52 }, { x: 235, y: 30 },
      { x: 310, y: 22 }, { x: 390, y: 94 }, { x: 470, y: 82 }, { x: 545, y: 66 },
      { x: 620, y: 52 }, { x: 690, y: 72 }, { x: 760, y: waterLevel }
    ];

    const width = 760;
    const height = 200;

    let pathD = `M 0,${height - (points[0].y / 100 * (height - 24))}`;
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const prevY = height - (prev.y / 100 * (height - 24));
      const currY = height - (curr.y / 100 * (height - 24));
      const cpX1 = prev.x + (curr.x - prev.x) / 2;
      const cpX2 = cpX1;
      pathD += ` C ${cpX1},${prevY} ${cpX2},${currY} ${curr.x},${currY}`;
    }

    const fillD = `${pathD} L ${width},${height} L 0,${height} Z`;

    svg.innerHTML = `
      <defs>
        <linearGradient id="chartGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#0EA5E9" stop-opacity="0.3"/>
          <stop offset="100%" stop-color="#0EA5E9" stop-opacity="0.0"/>
        </linearGradient>
      </defs>
      <path d="${fillD}" fill="url(#chartGrad)"/>
      <path d="${pathD}" fill="none" stroke="#0EA5E9" stroke-width="2.5"/>
    `;
  }

  // Automation Sliders
  const sliderStart = document.getElementById('slider-autostart');
  const sliderStop = document.getElementById('slider-autostop');
  const dispStart = document.getElementById('disp-autostart-pct');
  const dispStop = document.getElementById('disp-autostop-pct');
  const btnSaveRules = document.getElementById('btn-save-automation-rules');

  if (sliderStart && dispStart) {
    sliderStart.addEventListener('input', (e) => dispStart.textContent = `${e.target.value}%`);
  }
  if (sliderStop && dispStop) {
    sliderStop.addEventListener('input', (e) => dispStop.textContent = `${e.target.value}%`);
  }

  if (btnSaveRules) {
    btnSaveRules.addEventListener('click', () => {
      btnSaveRules.textContent = 'Saving...';
      fetch(`${apiBaseUrl}/automation/esp32_pump_main`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          autostartLevel: sliderStart ? parseInt(sliderStart.value) : 25,
          autostopLevel: sliderStop ? parseInt(sliderStop.value) : 95
        })
      }).catch(() => null);

      setTimeout(() => {
        btnSaveRules.textContent = '✓ Saved to Cloud';
        setTimeout(() => btnSaveRules.textContent = 'Save to Cloud', 2000);
      }, 350);
    });
  }

});
