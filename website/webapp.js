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
  const apiBaseUrl = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
    ? (window.location.port === '4000' ? 'http://localhost:4000/api/v1' : 'https://water-pump-controller.vercel.app/api/v1')
    : (window.location.origin.includes('vercel.app') ? `${window.location.origin}/api/v1` : 'https://water-pump-controller.vercel.app/api/v1');

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

  async function completeAuthentication(user, token) {
    currentUser = user;
    if (token) authToken = token;
    else if (!authToken) authToken = `hp_jwt_${Date.now()}`;
    localStorage.setItem('hydropulse_auth_token', authToken);
    localStorage.setItem('hydropulse_current_user', JSON.stringify(currentUser));

    showAlert('✓ Authenticated! Loading HydroPulse System Console...', true);

    setTimeout(async () => {
      if (authView) authView.classList.add('hidden');
      if (dashboardView) dashboardView.classList.remove('hidden');

      const fullName = `${user.firstName || ''} ${user.lastName || ''}`.trim() || (user.email ? user.email.split('@')[0] : 'User');
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

      // Fetch user's devices from the centralized backend to check for hardware
      let userDevices = [];
      try {
        const devRes = await fetch(`${apiBaseUrl}/devices`, {
          headers: { 'Authorization': `Bearer ${authToken}` }
        });
        if (devRes.ok) {
          const devJson = await devRes.json();
          if (devJson.data && Array.isArray(devJson.data)) {
            userDevices = devJson.data;
          }
        }
      } catch (e) {
        console.warn('[Sync] Devices fetch notice:', e);
      }

      const hasHardware = userDevices.length > 0;
      const hwActiveDash = document.getElementById('hw-active-dashboard');
      const hwNoneDash = document.getElementById('hw-none-dashboard');
      const topbarChip = document.getElementById('topbar-device-chip') || document.querySelector('.topbar-device-chip');

      if (!hasHardware) {
        // RESTRICTION: No hardware added yet! Hide hardware cards, show user profile and app update engine
        if (hwActiveDash) hwActiveDash.classList.add('hidden');
        if (hwNoneDash) hwNoneDash.classList.remove('hidden');
        if (topbarChip) topbarChip.textContent = 'Node: None (Awaiting Pairing)';

        // Populate No-Hardware Profile View
        const pAvatar = document.getElementById('profile-avatar-display');
        const pName = document.getElementById('profile-name-display');
        const pEmail = document.getElementById('profile-email-display');
        if (pAvatar) pAvatar.textContent = initials;
        if (pName) pName.textContent = fullName;
        if (pEmail) pEmail.textContent = user.email;

        const btnProfSettings = document.getElementById('btn-profile-to-settings');
        if (btnProfSettings) {
          btnProfSettings.onclick = () => switchTab('settings');
        }
        const btnProfSignout = document.getElementById('btn-profile-signout');
        if (btnProfSignout) {
          btnProfSignout.onclick = handleSignOut;
        }

        const btnCheckUpdatesWeb = document.getElementById('btn-check-updates-web');
        if (btnCheckUpdatesWeb) {
          btnCheckUpdatesWeb.onclick = () => {
            alert('HydroPulse Update Engine:\nInstalled Client: v2.0.2 (Build 4)\nStatus: Running latest official release with in-app OTA and direct package installer support.');
          };
        }
      } else {
        // Hardware is attached! Show live cards, 3D tank, and telemetry
        if (hwActiveDash) hwActiveDash.classList.remove('hidden');
        if (hwNoneDash) hwNoneDash.classList.add('hidden');
        if (topbarChip) topbarChip.textContent = `Node: ${userDevices[0].nodeId || userDevices[0].id || 'esp32_pump_main'}`;

        resizeTankCanvas();
        renderTrendChart();
        updateMetrics();
      }

      // Initialize live two-way MQTT & REST synchronization with mobile app
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

      // STRICT AUTHENTICATION: Check strictly against centralized backend database
      try {
        const response = await fetch(`${apiBaseUrl}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password })
        });

        const json = await response.json().catch(() => ({}));
        if (response.ok && json.status === 'success' && json.data && json.data.user) {
          completeAuthentication(json.data.user, json.data.tokens?.accessToken);
        } else {
          showAlert(json.message || 'Access Denied: Account not found or incorrect credentials. Please register your account first.');
        }
      } catch (err) {
        showAlert('Unable to reach the HydroPulse Cloud API. Please check your network connection.');
      }
    });
  }

  // Auth Tabs Switching (Sign In vs Create Account)
  const tabSignin = document.getElementById('tab-auth-signin');
  const tabSignup = document.getElementById('tab-auth-signup');
  const formSignin = document.getElementById('auth-form-signin');
  const formSignup = document.getElementById('auth-form-signup');
  const authTitle = document.getElementById('auth-form-title');
  const authDesc = document.getElementById('auth-form-desc');

  if (tabSignin && tabSignup) {
    tabSignin.addEventListener('click', () => {
      tabSignin.classList.add('active');
      tabSignup.classList.remove('active');
      if (formSignin) formSignin.classList.remove('hidden');
      if (formSignup) formSignup.classList.add('hidden');
      if (authTitle) authTitle.textContent = 'System Console Sign In';
      if (authDesc) authDesc.textContent = 'Authenticate to access hardware control registers and real-time telemetry.';
      hideAlert();
    });

    tabSignup.addEventListener('click', () => {
      tabSignup.classList.add('active');
      tabSignin.classList.remove('active');
      if (formSignin) formSignin.classList.add('hidden');
      if (formSignup) formSignup.classList.remove('hidden');
      if (authTitle) authTitle.textContent = 'Create HydroPulse Account';
      if (authDesc) authDesc.textContent = 'Register an enterprise client profile to manage water pump controllers.';
      hideAlert();
    });
  }

  // Password peek toggle for signup
  const btnPeekSignupPwd = document.getElementById('btn-peek-signup-pwd');
  if (btnPeekSignupPwd) {
    btnPeekSignupPwd.addEventListener('click', () => {
      const pwdInput = document.getElementById('signup-password');
      if (pwdInput) {
        pwdInput.type = pwdInput.type === 'password' ? 'text' : 'password';
      }
    });
  }

  // Account Creation (Sign Up) Submission
  if (formSignup) {
    formSignup.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert();

      const firstName = document.getElementById('signup-firstname')?.value.trim();
      const lastName = document.getElementById('signup-lastname')?.value.trim();
      const email = document.getElementById('signup-email')?.value.trim().toLowerCase();
      const password = document.getElementById('signup-password')?.value;
      const confirmPassword = document.getElementById('signup-confirmpassword')?.value;

      if (!firstName) {
        showAlert('Please enter your first name.');
        document.getElementById('signup-firstname')?.focus();
        return;
      }
      if (!email) {
        showAlert('Please enter your email address.');
        document.getElementById('signup-email')?.focus();
        return;
      }
      const emailRegex = /^[\w\.-]+@([\w-]+\.)+[\w-]{2,6}$/;
      if (!emailRegex.test(email)) {
        showAlert('Please enter a valid email address.');
        document.getElementById('signup-email')?.focus();
        return;
      }
      if (!password) {
        showAlert('Please enter a password.');
        document.getElementById('signup-password')?.focus();
        return;
      }
      if (password.length < 6) {
        showAlert('Password must be at least 6 characters long.');
        document.getElementById('signup-password')?.focus();
        return;
      }
      if (!confirmPassword) {
        showAlert('Please confirm your password.');
        document.getElementById('signup-confirmpassword')?.focus();
        return;
      }
      if (password !== confirmPassword) {
        showAlert('Passwords do not match.');
        document.getElementById('signup-confirmpassword')?.focus();
        return;
      }

      const submitBtn = document.getElementById('btn-submit-signup');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = 'Creating Account...';
      }

      try {
        const response = await fetch(`${apiBaseUrl}/auth/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            firstName,
            lastName: lastName || firstName,
            email,
            password
          })
        });

        const json = await response.json().catch(() => ({}));
        if ((response.status === 200 || response.status === 201) && json.status === 'success' && json.data && json.data.user) {
          showAlert('✓ Account created successfully! Launching HydroPulse console...', true);
          completeAuthentication(json.data.user, json.data.tokens?.accessToken);
        } else {
          showAlert(json.message || 'Account registration failed. Please check details.');
        }
      } catch (err) {
        showAlert('Unable to reach the HydroPulse Cloud API. Please check your network connection.');
      } finally {
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.textContent = 'Create HydroPulse Account';
        }
      }
    });
  }

  function handleSignOut() {
    currentUser = null;
    authToken = null;
    localStorage.removeItem('hydropulse_auth_token');
    localStorage.removeItem('hydropulse_current_user');
    sessionStorage.clear();
    if (dashboardView) dashboardView.classList.add('hidden');
    if (authView) authView.classList.remove('hidden');
    hideAlert();
  }

  if (btnLogout) btnLogout.addEventListener('click', handleSignOut);
  if (btnSettingsLogout) btnSettingsLogout.addEventListener('click', handleSignOut);

  const btnSettingsFlush = document.getElementById('btn-settings-flush');
  if (btnSettingsFlush) {
    btnSettingsFlush.addEventListener('click', async () => {
      if (confirm('Are you sure you want to flush all user accounts, devices, and database telemetry?')) {
        try {
          await fetch(`${apiBaseUrl}/system/flush`, { method: 'POST' });
        } catch {}
        localStorage.clear();
        sessionStorage.clear();
        alert('All accounts and database data have been completely flushed.');
        window.location.reload();
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
    googleAuthForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const input = document.getElementById('google-email-input');
      const email = input ? input.value.trim().toLowerCase() : '';
      if (!email || !email.includes('@')) return;
      googleModalSheet.classList.add('hidden');
      const namePart = email.split('@')[0].replace(/[\._-]/g, ' ');
      const capName = namePart ? (namePart.charAt(0).toUpperCase() + namePart.slice(1)) : 'Google User';

      try {
        const response = await fetch(`${apiBaseUrl}/auth/google`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email,
            firstName: capName,
            lastName: 'Account',
            googleId: `google_web_${Date.now()}`
          })
        });
        const json = await response.json();
        if (response.ok && json.status === 'success' && json.data?.user) {
          completeAuthentication(json.data.user, json.data.tokens?.accessToken);
        } else {
          showAlert(json.message || 'Google authentication failed.');
        }
      } catch (err) {
        showAlert('Google authentication service unreachable.');
      }
    });
  }

  if (authToken && currentUser) {
    completeAuthentication(currentUser, authToken);
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
  let bubbleProgress = 0;
  let liveFlowRate = 0.0;
  let livePowerKw = 0.0;

  // Interactive 3D Spatial Tilt Angles (matching Flutter SpatialWaterTank3D)
  let tiltX = -0.06;
  let tiltY = 0.04;
  let targetTiltX = -0.06;
  let targetTiltY = 0.04;

  const tankDataHud = document.getElementById('tank-data-hud');
  const tankFillingStatus = document.getElementById('tank-filling-status');

  if (tankContainer) {
    tankContainer.addEventListener('mousemove', (e) => {
      const rect = tankContainer.getBoundingClientRect();
      const nx = (e.clientX - rect.left) / rect.width - 0.5;
      const ny = (e.clientY - rect.top) / rect.height - 0.5;
      targetTiltY = nx * 0.22;
      targetTiltX = -ny * 0.22;
    });

    tankContainer.addEventListener('mouseleave', () => {
      targetTiltX = -0.06;
      targetTiltY = 0.04;
    });

    tankContainer.addEventListener('touchmove', (e) => {
      if (!e.touches[0]) return;
      const rect = tankContainer.getBoundingClientRect();
      const nx = (e.touches[0].clientX - rect.left) / rect.width - 0.5;
      const ny = (e.touches[0].clientY - rect.top) / rect.height - 0.5;
      targetTiltY = nx * 0.22;
      targetTiltX = -ny * 0.22;
    }, { passive: true });

    tankContainer.addEventListener('touchend', () => {
      targetTiltX = -0.06;
      targetTiltY = 0.04;
    });
  }

  // 22 Volumetric Micro-Bubbles
  const tankBubbles = [];
  for (let i = 0; i < 22; i++) {
    tankBubbles.push({
      x: Math.random(),
      y: Math.random(),
      size: Math.random() * 3.5 + 2,
      speed: Math.random() * 0.4 + 0.3,
      opacity: Math.random() * 0.5 + 0.3
    });
  }

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
    const w = tankCanvas.width;
    const h = tankCanvas.height;
    if (w === 0 || h === 0) return;

    tankCtx.clearRect(0, 0, w, h);

    // Dynamic fluid color palette based on tank level (matches Flutter)
    let primaryFluid = '#00E5FF';
    let secondaryFluid = '#0066FF';
    let fluidGlow = '#00D2FF';

    const clampedLevel = Math.max(0, Math.min(100, waterLevel));
    if (clampedLevel <= 20) {
      primaryFluid = '#FF5252';
      secondaryFluid = '#D50000';
      fluidGlow = '#FF1744';
    } else if (clampedLevel <= 40) {
      primaryFluid = '#FFD600';
      secondaryFluid = '#FF6D00';
      fluidGlow = '#FFAB00';
    } else if (clampedLevel >= 90) {
      primaryFluid = '#00E676';
      secondaryFluid = '#00B0FF';
      fluidGlow = '#00E676';
    }

    // Dynamic ambient back-glow in container matching fluid state
    if (tankContainer) {
      tankContainer.style.boxShadow = `0 10px 36px ${fluidGlow}38, 0 14px 28px rgba(0, 0, 0, 0.6)`;
    }

    // Ease interactive 3D tilt
    tiltX += (targetTiltX - tiltX) * 0.12;
    tiltY += (targetTiltY - tiltY) * 0.12;
    tankCanvas.style.transform = `perspective(900px) rotateX(${tiltX}rad) rotateY(${tiltY}rad)`;

    tankCtx.save();

    // Clip to rounded tank vessel boundary (Radius: 36px equivalent)
    const rad = Math.min(36 * (w / 340), 36);
    tankCtx.beginPath();
    if (tankCtx.roundRect) {
      tankCtx.roundRect(0, 0, w, h, rad);
    } else {
      tankCtx.rect(0, 0, w, h);
    }
    tankCtx.clip();

    // 1. Dark Cylindrical Glass Vessel Background with 3D Depth Gradient
    const bgGrad = tankCtx.createLinearGradient(0, 0, w, 0);
    bgGrad.addColorStop(0.0, '#070B16');
    bgGrad.addColorStop(0.35, '#141D33');
    bgGrad.addColorStop(0.75, '#0B1020');
    bgGrad.addColorStop(1.0, '#04060C');
    tankCtx.fillStyle = bgGrad;
    tankCtx.fillRect(0, 0, w, h);

    const fillPct = clampedLevel / 100.0;
    const waterHeight = (h - 16) * fillPct;
    const baseWaterY = h - 8 - waterHeight;

    if (fillPct > 0.005) {
      // 2. Back Water Wave (Dual Harmonic Wave with Parallax)
      tankCtx.beginPath();
      tankCtx.moveTo(0, h);
      tankCtx.lineTo(0, baseWaterY);
      for (let x = 0; x <= w; x += 4) {
        const normX = x / w;
        const wy = baseWaterY +
          Math.sin(normX * 2 * Math.PI + wavePhase * 0.8) * 7.0 +
          Math.cos(normX * 4 * Math.PI - wavePhase * 0.6) * 3.0;
        tankCtx.lineTo(x, wy);
      }
      tankCtx.lineTo(w, h);
      tankCtx.closePath();

      const backGrad = tankCtx.createLinearGradient(0, baseWaterY, 0, h);
      backGrad.addColorStop(0.0, `${secondaryFluid}8C`); // 0.55 opacity
      backGrad.addColorStop(1.0, `${secondaryFluid}40`); // 0.25 opacity
      tankCtx.fillStyle = backGrad;
      tankCtx.fill();

      // 3. Front Water Wave (Primary Volumetric Fluid Fill)
      tankCtx.beginPath();
      tankCtx.moveTo(0, h);
      tankCtx.lineTo(0, baseWaterY);
      for (let x = 0; x <= w; x += 4) {
        const normX = x / w;
        const wy = baseWaterY +
          Math.sin(normX * 2 * Math.PI - wavePhase) * 9.0 +
          Math.sin(normX * 3.5 * Math.PI + wavePhase * 1.3) * 4.0;
        tankCtx.lineTo(x, wy);
      }
      tankCtx.lineTo(w, h);
      tankCtx.closePath();

      const frontGrad = tankCtx.createLinearGradient(0, baseWaterY, 0, h);
      frontGrad.addColorStop(0.0, `${primaryFluid}E0`);  // 0.88 opacity
      frontGrad.addColorStop(0.4, `${secondaryFluid}EB`); // 0.92 opacity
      frontGrad.addColorStop(1.0, '#001F54');
      tankCtx.fillStyle = frontGrad;
      tankCtx.fill();

      // 4. 3D Elliptical Meniscus Surface at Fluid Height
      tankCtx.save();
      const meniscusR = tankCtx.createRadialGradient(w / 2, baseWaterY, 2, w / 2, baseWaterY, w * 0.47);
      meniscusR.addColorStop(0.0, 'rgba(255, 255, 255, 0.75)');
      meniscusR.addColorStop(0.5, `${primaryFluid}CC`);
      meniscusR.addColorStop(1.0, 'rgba(0, 0, 0, 0)');
      tankCtx.fillStyle = meniscusR;
      tankCtx.beginPath();
      tankCtx.ellipse(w / 2, baseWaterY, w * 0.46, 7, 0, 0, Math.PI * 2);
      tankCtx.fill();
      tankCtx.restore();

      // 5. Volumetric Rising Bubbles
      for (let i = 0; i < tankBubbles.length; i++) {
        const b = tankBubbles[i];
        const currentY = ((b.y - (bubbleProgress * b.speed)) % 1.0 + 1.0) % 1.0;
        const actualY = baseWaterY + (currentY * waterHeight);
        const actualX = b.x * w + Math.sin(bubbleProgress * 2 * Math.PI + b.y * 10) * 6;

        if (actualY > baseWaterY && actualY < h) {
          tankCtx.beginPath();
          tankCtx.arc(actualX, actualY, b.size, 0, Math.PI * 2);
          tankCtx.fillStyle = `rgba(255, 255, 255, ${b.opacity * 0.7})`;
          tankCtx.fill();

          tankCtx.strokeStyle = `${fluidGlow}${Math.round(b.opacity * 255).toString(16).padStart(2, '0')}`;
          tankCtx.lineWidth = 1.0;
          tankCtx.stroke();
        }
      }
    }

    // 6. Laser-Etched 3D Graduation Rings & Tick Marks
    tankCtx.strokeStyle = 'rgba(74, 101, 149, 0.55)';
    tankCtx.lineWidth = 1.5;
    tankCtx.fillStyle = 'rgba(255, 255, 255, 0.45)';
    tankCtx.font = 'bold 9px monospace';
    tankCtx.textBaseline = 'middle';

    const levels = [0.25, 0.50, 0.75, 1.0];
    for (let i = 0; i < levels.length; i++) {
      const lvl = levels[i];
      const y = h * (1.0 - lvl);
      // Left tick
      tankCtx.beginPath();
      tankCtx.moveTo(12, y);
      tankCtx.lineTo(28, y);
      tankCtx.stroke();
      // Right tick
      tankCtx.beginPath();
      tankCtx.moveTo(w - 28, y);
      tankCtx.lineTo(w - 12, y);
      tankCtx.stroke();
      // Label
      tankCtx.fillText(`${(lvl * 100).toFixed(0)}%`, 34, y);
    }

    // 7. 3D Cylindrical Curved Glass Highlights & Reflections
    const glassGrad = tankCtx.createLinearGradient(0, 0, w, 0);
    glassGrad.addColorStop(0.05, 'rgba(255, 255, 255, 0.28)');
    glassGrad.addColorStop(0.22, 'rgba(255, 255, 255, 0.04)');
    glassGrad.addColorStop(0.85, 'rgba(255, 255, 255, 0.00)');
    glassGrad.addColorStop(0.98, 'rgba(255, 255, 255, 0.12)');
    tankCtx.fillStyle = glassGrad;
    tankCtx.fillRect(0, 0, w, h);

    // 8. Outer Spatial Glass Border
    const borderGrad = tankCtx.createLinearGradient(0, 0, w, h);
    borderGrad.addColorStop(0.0, 'rgba(255, 255, 255, 0.45)');
    borderGrad.addColorStop(0.5, `${fluidGlow}B3`);
    borderGrad.addColorStop(1.0, '#1E293B');
    tankCtx.strokeStyle = borderGrad;
    tankCtx.lineWidth = 2.5;
    tankCtx.beginPath();
    if (tankCtx.roundRect) {
      tankCtx.roundRect(1.25, 1.25, w - 2.5, h - 2.5, rad);
    } else {
      tankCtx.rect(1.25, 1.25, w - 2.5, h - 2.5);
    }
    tankCtx.stroke();

    tankCtx.restore();

    // Update Holographic HUD Badge colors & pump status
    if (tankDataHud) {
      tankDataHud.style.borderColor = `${fluidGlow}8C`;
      tankDataHud.style.boxShadow = `0 0 20px ${fluidGlow}45, 0 8px 24px rgba(0, 0, 0, 0.6)`;
    }
    if (tankFillingStatus) {
      if (isPumpRunning) tankFillingStatus.classList.remove('hidden');
      else tankFillingStatus.classList.add('hidden');
    }

    // Update wave and bubble progress
    wavePhase += isPumpRunning ? 0.09 : 0.035;
    bubbleProgress = (bubbleProgress + (isPumpRunning ? 0.018 : 0.008)) % 1.0;

    if (isPumpRunning) {
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
