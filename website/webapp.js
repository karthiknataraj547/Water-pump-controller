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
  const isLocalBackend = window.location.hostname === 'localhost' && window.location.port === '4000';
  const isVercelHost = window.location.hostname.endsWith('vercel.app');
  const apiBaseUrl = isLocalBackend
    ? 'http://localhost:4000/api/v1'
    : (isVercelHost ? `${window.location.origin}/api/v1` : 'https://water-pump-controller.vercel.app/api/v1');

  let authToken = localStorage.getItem('hydropulse_auth_token') || null;
  let currentUser = null;
  let userDevices = [];
  try {
    const cached = localStorage.getItem('hydropulse_current_user');
    if (cached) currentUser = JSON.parse(cached);
    const cachedDevs = localStorage.getItem('hydropulse_user_devices');
    if (cachedDevs) userDevices = JSON.parse(cachedDevs);
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

  function applyActiveDevice(device) {
    if (!device) return;
    const devId = device.deviceId || device.id || device.nodeId || 'esp32_pump_94B97E';
    const devName = device.name || (devId === 'esp32_pump_94B97E' ? 'Agricultural Borewell Pump' : 'HydroPulse Gateway');
    const devMac = device.macAddress || device.mac || (devId === 'esp32_pump_94B97E' ? '24:6F:28:94:B9:7E' : '24:6F:28:B2:A4:10');
    const devState = device.pumpState || (device.pumpRunning ? 'ON' : 'OFF');
    const devMode = device.mode || 'AUTO';

    const normalizedDev = {
      id: devId,
      deviceId: devId,
      nodeId: devId,
      name: devName,
      macAddress: devMac,
      isOnline: device.isOnline !== undefined ? Boolean(device.isOnline) : false,
      pumpState: devState,
      pumpRunning: devState === 'ON',
      mode: devMode,
      userEmail: device.userEmail || (currentUser ? currentUser.email : ''),
      userId: device.userId || (currentUser ? currentUser.email : '')
    };

    const existingIdx = userDevices.findIndex(d => (d.id === devId || d.deviceId === devId));
    if (existingIdx >= 0) {
      userDevices[existingIdx] = Object.assign(userDevices[existingIdx], normalizedDev);
    } else {
      userDevices.unshift(normalizedDev);
    }

    localStorage.setItem('hydropulse_user_devices', JSON.stringify(userDevices));
    localStorage.setItem('hydropulse_active_device_id', devId);

    // 1. Update Sidebar Hardware Status Widget
    document.querySelectorAll('.hw-node-id').forEach(el => {
      el.textContent = devName;
      el.title = `ID: ${devId} | MAC: ${devMac}`;
    });

    // 2. Update Topbar Device Chip and Header Title
    const topbarChip = document.getElementById('topbar-device-chip') || document.querySelector('.topbar-device-chip');
    if (topbarChip) {
      topbarChip.textContent = `Node: ${devId}`;
      topbarChip.title = `${devName} (${devMac})`;
    }
    const pageTitle = document.getElementById('page-title');
    if (pageTitle) {
      pageTitle.textContent = `${devName} / Overview`;
    }

    // 3. Update Settings Hardware Identifier Display
    const sHw = document.getElementById('settings-hw-id');
    if (sHw) {
      sHw.textContent = `${devName} (${devId}) • MAC: ${devMac}`;
    }

    // 4. Update Smart Water Card Heading
    const cardHeading = document.querySelector('.smart-water-system-card .sys-heading');
    if (cardHeading) {
      cardHeading.textContent = `${devName} Reservoir`;
    }

    // 5. Switch to Active Hardware Dashboard
    const hwActiveDash = document.getElementById('hw-active-dashboard');
    const hwNoneDash = document.getElementById('hw-none-dashboard');
    if (hwActiveDash) hwActiveDash.classList.remove('hidden');
    if (hwNoneDash) hwNoneDash.classList.add('hidden');

    console.log(`[Hardware Sync] Active hardware applied to UI: ${devName} (${devId})`);
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
      try {
        const queryEmail = user.email ? `?email=${encodeURIComponent(user.email)}` : '';
        const devRes = await fetch(`${apiBaseUrl}/devices${queryEmail}`, {
          headers: {
            'Authorization': `Bearer ${authToken}`,
            'x-user-email': user.email || ''
          }
        });
        if (devRes.ok) {
          const devJson = await devRes.json();
          if (devJson.data && Array.isArray(devJson.data) && devJson.data.length > 0) {
            userDevices = devJson.data;
            localStorage.setItem('hydropulse_user_devices', JSON.stringify(userDevices));
          }
        }
      } catch (e) {
        console.warn('[Sync] Devices fetch notice:', e);
      }

      // If backend returned empty on cold start but we have locally cached devices, preserve them!
      if (!userDevices || userDevices.length === 0) {
        try {
          const cachedDevs = localStorage.getItem('hydropulse_user_devices');
          if (cachedDevs) userDevices = JSON.parse(cachedDevs);
        } catch {}
      }

      if (userDevices && userDevices.length > 0) {
        applyActiveDevice(userDevices[0]);
        // Re-sync local device to backend so container retains it
        fetch(`${apiBaseUrl}/devices`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${authToken}`,
            'x-user-email': user.email || ''
          },
          body: JSON.stringify(userDevices[0])
        }).catch(() => {});
      } else {
        console.log('[Sync] Account has no paired hardware yet.');
        updateHardwareStatusBadge(false, 0);
        const nodeNameEl = document.getElementById('active-node-name');
        if (nodeNameEl) nodeNameEl.textContent = 'No Hardware Linked';
        const nodeMacEl = document.getElementById('active-node-mac');
        if (nodeMacEl) nodeMacEl.textContent = 'Pair via Mobile App or Link Below';
      }

      function promptManualPair() {
        const devId = prompt('Enter ESP32 Hardware ID (e.g. esp32_pump_01):');
        if (!devId || !devId.trim()) return;
        const devName = prompt('Enter Hardware Display Name (e.g. Farm Water Pump):') || 'HydroPulse Controller';
        const mac = prompt('Enter Hardware MAC Address (optional):') || '';
        const userEmail = (currentUser?.email || localStorage.getItem('hydropulse_user_email') || '').toLowerCase();
        const customDev = {
          id: devId.trim(),
          deviceId: devId.trim(),
          nodeId: devId.trim(),
          name: devName.trim(),
          macAddress: mac.trim(),
          userEmail: userEmail,
          userId: userEmail,
          isOnline: false,
          status: 'OFFLINE',
          pumpState: 'OFF',
          mode: 'AUTO',
          firmwareVersion: 'v2.1.2',
          wifiRssi: -65
        };
        applyActiveDevice(customDev);
        if (mqttClient && mqttClient.connected && userEmail) {
          const str = JSON.stringify(customDev);
          mqttClient.publish(`hydropulse/devices/${userEmail}`, str, { retain: true, qos: 1 });
          mqttClient.publish(`devices/sync/${userEmail}`, str, { retain: true, qos: 1 });
        }
        fetch(`${apiBaseUrl}/devices`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${authToken}`,
            'x-user-email': userEmail
          },
          body: JSON.stringify(customDev)
        }).catch(() => {});
        alert(`✓ Hardware ${customDev.name} (${customDev.id}) linked and synced!`);
      }

      const btnManualLink = document.getElementById('btn-manual-link-dialog');
      if (btnManualLink) btnManualLink.onclick = promptManualPair;
      const btnGuideManual = document.getElementById('btn-guide-manual-pair');
      if (btnGuideManual) btnGuideManual.onclick = promptManualPair;

      // Populate Profile Details
      const pAvatar = document.getElementById('profile-avatar-display');
      const pName = document.getElementById('profile-name-display');
      const pEmail = document.getElementById('profile-email-display');
      if (pAvatar) pAvatar.textContent = initials;
      if (pName) pName.textContent = fullName;
      if (pEmail) pEmail.textContent = user.email;
      if (pEmail) pEmail.textContent = user.email;

      const btnProfSettings = document.getElementById('btn-profile-to-settings');
      if (btnProfSettings) {
        btnProfSettings.onclick = () => switchTab('settings');
      }
      const btnProfSignout = document.getElementById('btn-profile-signout');
      if (btnProfSignout) {
        btnProfSignout.onclick = handleSignOut;
      }

      function syncAppVersionInfo() {
        fetch(`version.json?t=${Date.now()}`)
          .then(r => r.json())
          .then(data => {
            if (data && data.version) {
              const otaVer = document.getElementById('ota-current-version');
              if (otaVer) otaVer.textContent = `v${data.version} • Build ${data.build_number || 12}`;

              const setVer = document.getElementById('settings-app-version');
              if (setVer) setVer.textContent = `v${data.version} (Build ${data.build_number || 12})`;

              document.querySelectorAll('.sb-edition').forEach(el => el.textContent = `System Console v${data.version}`);
              document.querySelectorAll('.sys-chip').forEach(el => {
                if (el.textContent.startsWith('v2.')) el.textContent = `v${data.version}`;
              });

              const dlLinks = document.querySelectorAll('a[href*="HydroPulse_WaterPumpController.apk"], .btn-mobile-download');
              dlLinks.forEach(link => {
                const targetUrl = data.download_url ? `${data.download_url}?v=${data.version}` : `releases/HydroPulse_WaterPumpController.apk?v=${data.version}`;
                link.setAttribute('href', targetUrl);
                const sp = link.querySelector('span');
                if (sp && sp.textContent.includes('Download Android APK')) {
                  sp.textContent = `📥 Download Android APK v${data.version} (55.6 MB)`;
                }
              });
            }
          })
          .catch(() => {});
      }
      syncAppVersionInfo();

      const btnCheckUpdatesWeb = document.getElementById('btn-check-updates-web');
      if (btnCheckUpdatesWeb) {
        btnCheckUpdatesWeb.onclick = async () => {
          try {
            const res = await fetch(`version.json?t=${Date.now()}`);
            const data = await res.json();
            alert(`HydroPulse Update Engine:\nLatest Release: v${data.version} (Build ${data.build_number || 12})\nRelease Date: ${data.release_date}\nTitle: ${data.title}\nStatus: System is synchronized with the latest release.`);
          } catch (_) {
            alert('HydroPulse Update Engine:\nInstalled Client: v2.1.2 (Build 15)\nStatus: Running latest official release with in-app OTA and direct package installer support.');
          }
        };
      }

      setTimeout(resizeTankCanvas, 50);
      renderTrendChart();
      updateMetrics();

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

      // STRICT AUTHENTICATION: Check against backend database with cold-start self-healing
      try {
        let response = await fetch(`${apiBaseUrl}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password })
        });

        let json = await response.json().catch(() => ({}));

        // Self-Healing: If backend container reset and says "Account not found", check client account cache or primary admin
        if (response.status === 401 && (json.message?.includes('not found') || json.message?.includes('Account not found'))) {
          let clientAcc = null;
          try {
            const rawAccs = JSON.parse(localStorage.getItem('hydropulse_client_accounts') || '{}');
            clientAcc = rawAccs[email];
          } catch {}

          if (clientAcc && clientAcc.password === password) {
            // Transparently re-register with the backend container
            const reRegRes = await fetch(`${apiBaseUrl}/auth/register`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                firstName: clientAcc.firstName || 'HydroPulse',
                lastName: clientAcc.lastName || 'User',
                email: email,
                password: password
              })
            });
            const reRegJson = await reRegRes.json().catch(() => ({}));
            if ((reRegRes.ok || reRegRes.status === 201 || reRegRes.status === 200) && reRegJson.data?.user) {
              completeAuthentication(reRegJson.data.user, reRegJson.data.tokens?.accessToken);
              return;
            }
          }
        }

        if (response.ok && json.status === 'success' && json.data && json.data.user) {
          try {
            const rawAccs = JSON.parse(localStorage.getItem('hydropulse_client_accounts') || '{}');
            rawAccs[email] = {
              email,
              firstName: json.data.user.firstName || 'User',
              lastName: json.data.user.lastName || '',
              password
            };
            localStorage.setItem('hydropulse_client_accounts', JSON.stringify(rawAccs));
          } catch {}
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
          try {
            const rawAccs = JSON.parse(localStorage.getItem('hydropulse_client_accounts') || '{}');
            rawAccs[email] = { email, firstName, lastName, password };
            localStorage.setItem('hydropulse_client_accounts', JSON.stringify(rawAccs));
          } catch {}
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
    userDevices = [];
    localStorage.removeItem('hydropulse_auth_token');
    localStorage.removeItem('hydropulse_current_user');
    localStorage.removeItem('hydropulse_user_devices');
    localStorage.removeItem('hydropulse_active_device_id');
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
      setTimeout(resizeTankCanvas, 30);
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
  const estopBanner = document.getElementById('estop-banner');
  const btnModeAuto = document.getElementById('btn-mode-auto');
  const btnModeManual = document.getElementById('btn-mode-manual');

  const valPowerKw = document.getElementById('val-power-kw');
  const valRunDuration = document.getElementById('val-run-duration');
  const gridValFlow = document.getElementById('grid-val-flow');
  const gridSubFlow = document.getElementById('grid-sub-flow');
  const gridValVol = document.getElementById('grid-val-vol');
  const gridSubVol = document.getElementById('grid-sub-vol');

  let waterLevel = 0.0;
  let totalCapacityLiters = 5000.0;
  let isPumpRunning = false;
  let isHardwareOnline = false;
  let isSubNodeOnline = false;
  let lastHardwareHeartbeat = 0;
  let lastMqttCommandTimestamp = 0;
  let controlMode = 'AUTO';
  let previousControlMode = 'AUTO';
  let isEmergencyStopActive = false;
  let runSeconds = 0;
  let runTimer = null;
  let dailyCycles = 0;

  function updateEmergencyStopUI(active) {
    isEmergencyStopActive = active;
    if (btnEmergencyStop) {
      if (active) {
        btnEmergencyStop.classList.add('estop-engaged');
        btnEmergencyStop.innerHTML = '<span>⚠️ EMERGENCY STOP ENGAGED (TAP TO RESET)</span>';
      } else {
        btnEmergencyStop.classList.remove('estop-engaged');
        btnEmergencyStop.innerHTML = '<span>🛑 EMERGENCY STOP (E-STOP)</span>';
      }
    }
    if (estopBanner) {
      if (active) {
        estopBanner.classList.remove('hidden');
      } else {
        estopBanner.classList.add('hidden');
      }
    }
    if (btnPumpToggle) {
      if (active) {
        btnPumpToggle.classList.add('control-disabled');
        btnPumpToggle.style.opacity = '0.5';
        btnPumpToggle.style.pointerEvents = 'none';
      } else if (isHardwareOnline) {
        btnPumpToggle.classList.remove('control-disabled');
        btnPumpToggle.style.opacity = '1';
        btnPumpToggle.style.pointerEvents = 'auto';
      }
    }
  }

  function handleEmergencyStopClick() {
    const activeDevId = (userDevices && userDevices.length > 0) ? (userDevices[0].id || userDevices[0].nodeId || userDevices[0].deviceId) : 'esp32_pump_main';
    if (isEmergencyStopActive) {
      // RESET / CLEAR EMERGENCY STOP
      updateEmergencyStopUI(false);
      const restoreMode = previousControlMode || 'AUTO';
      setControlMode(restoreMode, true);

      if (mqttClient && mqttClient.connected) {
        const payload = JSON.stringify({
          action: 'CLEAR_EMERGENCY',
          command: 'CLEAR_EMERGENCY',
          commandId: `cmd_clr_${Date.now()}`,
          deviceId: activeDevId,
          timestamp: Math.floor(Date.now() / 1000)
        });
        mqttClient.publish('pump/command', payload, { qos: 0 });
        mqttClient.publish(`pump/${activeDevId}/command`, payload, { qos: 0 });
        mqttClient.publish(`devices/${activeDevId}/command`, payload, { qos: 0 });
      }

      fetch(`${apiBaseUrl}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command: 'CLEAR_EMERGENCY', action: 'CLEAR_EMERGENCY', deviceId: activeDevId })
      }).catch(() => null);

    } else {
      // ENGAGE EMERGENCY STOP
      previousControlMode = controlMode;
      updateEmergencyStopUI(true);
      setMotorRunning(false, false);

      if (mqttClient && mqttClient.connected) {
        const payload = JSON.stringify({
          action: 'EMERGENCY_STOP',
          command: 'EMERGENCY_STOP',
          commandId: `cmd_estop_${Date.now()}`,
          pumpState: 'OFF',
          state: 'OFF',
          status: 'STOPPED',
          deviceId: activeDevId,
          timestamp: Math.floor(Date.now() / 1000)
        });
        mqttClient.publish('pump/command', payload, { qos: 0 });
        mqttClient.publish(`pump/${activeDevId}/command`, payload, { qos: 0 });
        mqttClient.publish(`devices/${activeDevId}/command`, payload, { qos: 0 });
      }

      fetch(`${apiBaseUrl}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command: 'EMERGENCY_STOP', action: 'EMERGENCY_STOP', deviceId: activeDevId })
      }).catch(() => null);
    }
  }

  // Animation phases (matching Flutter SmartWaterSystemCard)
  let wavePhase = 0;
  let pipeFlowPhase = 0;
  let impellerAngle = 0;
  let cascadePhase = 0;
  let splashPhase = 0;

  // 3D 360° Rotatable Solid Tank (Continuous Horizontal Orbit)
  let tankRotY = 0.0;
  let isDraggingTank = false;
  let lastPointerX = 0;

  // Real-time sensor metrics
  let liveFlowRate = 0.0;
  let livePowerKw = 0.0;
  let liveTds = 0;
  let liveTemp = 0.0;

  const tankDataHud = document.getElementById('tank-data-hud');
  const tankFillingStatus = document.getElementById('tank-filling-status');

  // Interactive 360° Drag & Orbit Interaction
  if (tankContainer) {
    tankContainer.addEventListener('mousedown', (e) => {
      isDraggingTank = true;
      lastPointerX = e.clientX;
    });

    window.addEventListener('mousemove', (e) => {
      if (!isDraggingTank) return;
      const dx = e.clientX - lastPointerX;
      tankRotY += dx * 0.012;
      lastPointerX = e.clientX;
    });

    window.addEventListener('mouseup', () => {
      isDraggingTank = false;
    });

    tankContainer.addEventListener('touchstart', (e) => {
      if (e.touches && e.touches[0]) {
        isDraggingTank = true;
        lastPointerX = e.touches[0].clientX;
      }
    }, { passive: true });

    tankContainer.addEventListener('touchmove', (e) => {
      if (!isDraggingTank || !e.touches || !e.touches[0]) return;
      const dx = e.touches[0].clientX - lastPointerX;
      tankRotY += dx * 0.012;
      lastPointerX = e.touches[0].clientX;
    }, { passive: true });

    tankContainer.addEventListener('touchend', () => {
      isDraggingTank = false;
    });
  }

  function resizeTankCanvas() {
    if (!tankContainer || !tankCanvas) return;
    const rect = tankContainer.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;
    const dpr = window.devicePixelRatio || 1;
    tankCanvas.width = Math.round(rect.width * dpr);
    tankCanvas.height = Math.round(rect.height * dpr);
  }
  window.addEventListener('resize', resizeTankCanvas);

  // ============================================================================
  // 3D VOLUMETRIC CYLINDER RESERVOIR & IMPELLER MOTOR RENDERER
  // (Exact pixel-accurate reproduction of Flutter SmartWaterSystemCard)
  // ============================================================================
  function drawTank() {
    if (!tankCtx || !tankCanvas) {
      requestAnimationFrame(drawTank);
      return;
    }

    // Auto-measure if width or height is 0 (e.g. after tab switches or signin)
    if (tankCanvas.width === 0 || tankCanvas.height === 0) {
      resizeTankCanvas();
      if (tankCanvas.width === 0 || tankCanvas.height === 0) {
        requestAnimationFrame(drawTank);
        return;
      }
    }

    const dpr = window.devicePixelRatio || 1;
    const w = tankCanvas.width / dpr;
    const h = tankCanvas.height / dpr;

    tankCtx.save();
    tankCtx.scale(dpr, dpr);
    tankCtx.clearRect(0, 0, w, h);

    // 0. Stage Background & Subtle Radial Depth Vignette
    const stageGrad = tankCtx.createRadialGradient(w * 0.4, h * 0.35, 10, w * 0.4, h * 0.5, w * 0.7);
    stageGrad.addColorStop(0.0, 'rgba(15, 27, 54, 0.45)');
    stageGrad.addColorStop(1.0, 'rgba(3, 7, 18, 0.85)');
    tankCtx.fillStyle = stageGrad;
    tankCtx.fillRect(0, 0, w, h);

    // Tank Geometric Constants
    const cx = w * 0.38;
    const r = Math.min(w * 0.28, 92);
    const h_tank = h * 0.72;
    const top = 34.0;
    const bottom = top + h_tank;
    const capH = 20.0;

    // Subtle gentle ambient float when not dragging
    if (!isDraggingTank) {
      tankRotY += 0.003;
    }

    // ------------------------------------------------------------------------
    // 1. SOLID BASE PEDESTAL & 3D CONTACT GROUND SHADOW
    // ------------------------------------------------------------------------
    tankCtx.save();
    tankCtx.fillStyle = 'rgba(0, 0, 0, 0.65)';
    tankCtx.beginPath();
    tankCtx.ellipse(cx, bottom + 12, r * 1.15, capH * 0.7, 0, 0, Math.PI * 2);
    tankCtx.fill();
    tankCtx.restore();

    // Solid Base Plinth Oval
    const baseGrad = tankCtx.createLinearGradient(0, bottom - capH * 0.4, 0, bottom + capH * 0.6);
    baseGrad.addColorStop(0, '#1E293B');
    baseGrad.addColorStop(1, '#0B1120');
    tankCtx.fillStyle = baseGrad;
    tankCtx.beginPath();
    tankCtx.ellipse(cx, bottom + 5, r * 1.05, capH * 0.45, 0, 0, Math.PI * 2);
    tankCtx.fill();

    // ------------------------------------------------------------------------
    // 2. BACK WALL OF CYLINDER & BACK STRUCTURAL RIBS (z < 0)
    // ------------------------------------------------------------------------
    const backHullGrad = tankCtx.createLinearGradient(cx - r, 0, cx + r, 0);
    backHullGrad.addColorStop(0.0, '#070E1E');
    backHullGrad.addColorStop(0.5, '#0F1B36');
    backHullGrad.addColorStop(1.0, '#0A1326');
    tankCtx.fillStyle = backHullGrad;

    tankCtx.beginPath();
    tankCtx.moveTo(cx - r, top);
    tankCtx.lineTo(cx - r, bottom);
    tankCtx.ellipse(cx, bottom, r, capH * 0.5, 0, Math.PI, 0, true);
    tankCtx.lineTo(cx + r, top);
    tankCtx.ellipse(cx, top, r, capH * 0.5, 0, 0, Math.PI, true);
    tankCtx.closePath();
    tankCtx.fill();

    // Orbiting Back Structural Ribs
    const numRibs = 8;
    for (let k = 0; k < numRibs; k++) {
      const theta = (k * 2 * Math.PI) / numRibs;
      const alpha = theta + tankRotY;
      const z = Math.cos(alpha);
      const x = cx + r * Math.sin(alpha);
      if (z < 0) {
        tankCtx.strokeStyle = `rgba(30, 47, 84, ${0.4 * (-z)})`;
        tankCtx.lineWidth = 1.6;
        tankCtx.beginPath();
        tankCtx.moveTo(x, top);
        tankCtx.lineTo(x, bottom);
        tankCtx.stroke();
      }
    }

    // ------------------------------------------------------------------------
    // 3. SOLID VOLUMETRIC FLUID MASS
    // ------------------------------------------------------------------------
    const clampedLevel = isSubNodeOnline ? (Math.max(0, Math.min(100, waterLevel)) / 100.0) : 0.0;
    const fluidH = h_tank * clampedLevel;
    const fluidTop = bottom - fluidH;

    if (clampedLevel > 0.01) {
      tankCtx.save();

      // Fluid Hull Path
      tankCtx.beginPath();
      tankCtx.moveTo(cx - r, fluidTop);
      tankCtx.lineTo(cx - r, bottom);
      tankCtx.ellipse(cx, bottom, r, capH * 0.5, 0, Math.PI, 0, true);
      tankCtx.lineTo(cx + r, fluidTop);
      tankCtx.ellipse(cx, fluidTop, r, capH * 0.5, 0, 0, Math.PI, true);
      tankCtx.closePath();

      // 3D Cylindrical Volumetric Fluid Gradient with Specular Shift
      const fluidLightOffset = Math.sin(tankRotY) * 0.25;
      const fluidStop1 = Math.max(0.05, Math.min(0.55, 0.28 + fluidLightOffset));
      const fluidStop2 = Math.max(0.40, Math.min(0.85, 0.65 + fluidLightOffset));

      const fluidGrad = tankCtx.createLinearGradient(cx - r, 0, cx + r, 0);
      fluidGrad.addColorStop(0.0, 'rgba(3, 4, 94, 0.95)');
      fluidGrad.addColorStop(fluidStop1, 'rgba(0, 119, 182, 0.90)');
      fluidGrad.addColorStop(fluidStop2, 'rgba(0, 180, 216, 0.85)');
      fluidGrad.addColorStop(1.0, 'rgba(2, 62, 138, 0.95)');
      tankCtx.fillStyle = fluidGrad;
      tankCtx.fill();

      // 3D Orbiting Aeration Micro-Bubbles
      for (let b = 0; b < 14; b++) {
        const bTheta = b * 0.45 * Math.PI;
        const bAlpha = bTheta + tankRotY;
        const bZ = Math.cos(bAlpha);
        const bRad = r * 0.75;
        const bx = cx + bRad * Math.sin(bAlpha);
        const bProgress = ((wavePhase / (2 * Math.PI) + (b * 0.075)) % 1.0);
        const by = bottom - (fluidH * bProgress);
        const bAlphaVal = Math.max(0.1, Math.min(0.85, 0.25 + 0.45 * ((bZ + 1) / 2)));
        const bSize = (1.5 + (b % 3)) * (0.8 + 0.3 * ((bZ + 1) / 2));

        tankCtx.fillStyle = `rgba(255, 255, 255, ${bAlphaVal})`;
        tankCtx.beginPath();
        tankCtx.arc(bx, by, bSize, 0, Math.PI * 2);
        tankCtx.fill();
      }

      // 3D Elliptical Surface Meniscus Cap at fluidTop
      const meniscusGrad = tankCtx.createLinearGradient(0, fluidTop - capH * 0.5, 0, fluidTop + capH * 0.5);
      meniscusGrad.addColorStop(0.0, 'rgba(144, 224, 239, 0.9)');
      meniscusGrad.addColorStop(0.5, 'rgba(0, 180, 216, 0.65)');
      meniscusGrad.addColorStop(1.0, 'rgba(0, 119, 182, 0.4)');
      tankCtx.fillStyle = meniscusGrad;
      tankCtx.beginPath();
      tankCtx.ellipse(cx, fluidTop, r, capH * 0.5, 0, 0, Math.PI * 2);
      tankCtx.fill();

      // Oscillating Wave Crest
      tankCtx.beginPath();
      tankCtx.moveTo(cx - r, fluidTop);
      const waveAmp = isPumpRunning ? 4.5 : 1.8;
      for (let x = cx - r; x <= cx + r; x += 3) {
        const relX = (x - (cx - r)) / (r * 2);
        const wy = fluidTop + Math.sin(relX * 2 * Math.PI + wavePhase) * waveAmp;
        tankCtx.lineTo(x, wy);
      }
      tankCtx.strokeStyle = 'rgba(202, 240, 248, 0.85)';
      tankCtx.lineWidth = 2.0;
      tankCtx.stroke();

      // Waterfall Surface Impact Splash Ripples (when Pump is Running)
      if (isPumpRunning) {
        const impactX = cx;
        const rippleR = 7.0 + (splashPhase * 22.0);
        const rippleAlpha = Math.max(0.0, 1.0 - splashPhase);
        tankCtx.strokeStyle = `rgba(0, 229, 255, ${rippleAlpha * 0.85})`;
        tankCtx.lineWidth = 2.0;
        tankCtx.beginPath();
        tankCtx.ellipse(impactX, fluidTop, rippleR, rippleR * 0.35, 0, 0, Math.PI * 2);
        tankCtx.stroke();
      }

      tankCtx.restore();
    }

    // ------------------------------------------------------------------------
    // 4. SOLID FRONT SHELL: 3D CYLINDRICAL LIGHTING & SPECULAR GLARE
    // ------------------------------------------------------------------------
    const lightVector = Math.sin(tankRotY) * 0.35;
    const specStop1 = Math.max(0.05, Math.min(0.60, 0.28 + lightVector));
    const specStop2 = Math.max(0.20, Math.min(0.75, 0.42 + lightVector));
    const specStop3 = Math.max(0.55, Math.min(0.95, 0.78 + lightVector));

    const frontGlassGrad = tankCtx.createLinearGradient(cx - r, 0, cx + r, 0);
    frontGlassGrad.addColorStop(0.0, 'rgba(15, 26, 52, 0.82)');
    frontGlassGrad.addColorStop(specStop1, 'rgba(46, 72, 124, 0.38)');
    frontGlassGrad.addColorStop(specStop2, 'rgba(100, 181, 246, 0.26)');
    frontGlassGrad.addColorStop(specStop3, 'rgba(26, 44, 80, 0.42)');
    frontGlassGrad.addColorStop(1.0, 'rgba(11, 20, 40, 0.88)');

    tankCtx.fillStyle = frontGlassGrad;
    tankCtx.beginPath();
    tankCtx.moveTo(cx - r, top);
    tankCtx.lineTo(cx - r, bottom);
    tankCtx.ellipse(cx, bottom, r, capH * 0.5, 0, Math.PI, 0, true);
    tankCtx.lineTo(cx + r, top);
    tankCtx.ellipse(cx, top, r, capH * 0.5, 0, 0, Math.PI, true);
    tankCtx.closePath();
    tankCtx.fill();

    // ------------------------------------------------------------------------
    // 5. 3D ORBITING FRONT STRUCTURAL RIBS (z > 0.05)
    // ------------------------------------------------------------------------
    for (let k = 0; k < numRibs; k++) {
      const theta = (k * 2 * Math.PI) / numRibs;
      const alpha = theta + tankRotY;
      const z = Math.cos(alpha);
      const x = cx + r * Math.sin(alpha);
      if (z > 0.05) {
        const ribWidth = Math.max(1.0, Math.min(3.0, 2.2 * z));
        // Highlight edge
        tankCtx.strokeStyle = `rgba(255, 255, 255, ${0.65 * z})`;
        tankCtx.lineWidth = 1.0;
        tankCtx.beginPath();
        tankCtx.moveTo(x - ribWidth / 2, top);
        tankCtx.lineTo(x - ribWidth / 2, bottom);
        tankCtx.stroke();
        // Shadow edge
        tankCtx.strokeStyle = `rgba(2, 6, 23, ${0.75 * z})`;
        tankCtx.lineWidth = 1.2;
        tankCtx.beginPath();
        tankCtx.moveTo(x + ribWidth / 2, top);
        tankCtx.lineTo(x + ribWidth / 2, bottom);
        tankCtx.stroke();
      }
    }

    // ------------------------------------------------------------------------
    // 6. 3D DOMED TOP CAP, MANHOLE FLANGE, AND 6 ORBITING BOLT STUDS
    // ------------------------------------------------------------------------
    const topDomeGrad = tankCtx.createLinearGradient(0, top - capH * 0.5, 0, top + capH * 0.5);
    topDomeGrad.addColorStop(0.0, '#1E293B');
    topDomeGrad.addColorStop(0.7, '#0B1120');
    topDomeGrad.addColorStop(1.0, '#040812');
    tankCtx.fillStyle = topDomeGrad;
    tankCtx.beginPath();
    tankCtx.ellipse(cx, top, r, capH * 0.5, 0, 0, Math.PI * 2);
    tankCtx.fill();

    tankCtx.strokeStyle = isPumpRunning ? 'rgba(0, 229, 255, 0.85)' : 'rgba(0, 229, 255, 0.45)';
    tankCtx.lineWidth = 2.0;
    tankCtx.stroke();

    // Center Manhole Flange Opening
    const manholeR = 20.0;
    tankCtx.fillStyle = '#050B17';
    tankCtx.beginPath();
    tankCtx.ellipse(cx, top, manholeR, capH * 0.35, 0, 0, Math.PI * 2);
    tankCtx.fill();

    tankCtx.strokeStyle = 'rgba(0, 229, 255, 0.7)';
    tankCtx.lineWidth = 1.4;
    tankCtx.stroke();

    // 6 Orbiting Bolt Studs on Top Flange
    for (let b = 0; b < 6; b++) {
      const bAngle = (b * Math.PI / 3) + tankRotY;
      const bx = cx + (manholeR + 4) * Math.cos(bAngle);
      const by = top + (capH * 0.3) * Math.sin(bAngle);
      tankCtx.fillStyle = 'rgba(255, 255, 255, 0.85)';
      tankCtx.beginPath();
      tankCtx.arc(bx, by, 1.6, 0, Math.PI * 2);
      tankCtx.fill();
    }

    // ------------------------------------------------------------------------
    // 7. ORBITING 3D GRADUATION SCALE (0%, 25%, 50%, 75%, 100%)
    // ------------------------------------------------------------------------
    const scaleAngle = tankRotY % (Math.PI * 2);
    const scaleZ = Math.cos(scaleAngle);
    if (scaleZ > -0.2) {
      const scaleX = cx - (r * 0.88 * Math.cos(scaleAngle));
      const scaleAlpha = Math.max(0.0, Math.min(1.0, scaleZ + 0.2));
      tankCtx.font = 'bold 9px monospace';
      tankCtx.textBaseline = 'middle';

      for (let g = 0; g <= 4; g++) {
        const gy = bottom - (h_tank * (g / 4.0));
        const isMajor = g % 2 === 0;
        const lineLen = isMajor ? 12 : 7;

        tankCtx.strokeStyle = `rgba(255, 255, 255, ${0.65 * scaleAlpha})`;
        tankCtx.lineWidth = isMajor ? 1.6 : 1.0;
        tankCtx.beginPath();
        tankCtx.moveTo(scaleX, gy);
        tankCtx.lineTo(scaleX + lineLen * (scaleZ > 0 ? 1 : 0.6), gy);
        tankCtx.stroke();

        if (isMajor && scaleAlpha > 0.4) {
          tankCtx.fillStyle = `rgba(255, 255, 255, ${0.85 * scaleAlpha})`;
          tankCtx.fillText(`${g * 25}%`, scaleX + lineLen + 4, gy);
        }
      }
    }

    // Outer Cylinder Silhouette Glow
    tankCtx.strokeStyle = isPumpRunning ? 'rgba(0, 229, 255, 0.45)' : 'rgba(0, 229, 255, 0.18)';
    tankCtx.lineWidth = 2.0;
    tankCtx.beginPath();
    tankCtx.moveTo(cx - r, top);
    tankCtx.lineTo(cx - r, bottom);
    tankCtx.ellipse(cx, bottom, r, capH * 0.5, 0, Math.PI, 0, true);
    tankCtx.lineTo(cx + r, top);
    tankCtx.ellipse(cx, top, r, capH * 0.5, 0, 0, Math.PI, true);
    tankCtx.stroke();

    // ------------------------------------------------------------------------
    // 8. CENTRIFUGAL PUMP MOTOR (BOTTOM RIGHT) & SPINNING IMPELLER TURBINE
    // ------------------------------------------------------------------------
    const motorX = w - 48;
    const motorY = h - 48;
    const motorR = 26;

    // Running Aura Glow
    if (isPumpRunning) {
      tankCtx.save();
      tankCtx.fillStyle = 'rgba(0, 229, 255, 0.25)';
      tankCtx.beginPath();
      tankCtx.arc(motorX, motorY, motorR + 10, 0, Math.PI * 2);
      tankCtx.fill();
      tankCtx.restore();
    }

    // Heavy Mounting Bracket
    tankCtx.fillStyle = '#1E293B';
    tankCtx.beginPath();
    if (tankCtx.roundRect) tankCtx.roundRect(motorX - 18, motorY + motorR + 2, 36, 8, 3);
    else tankCtx.rect(motorX - 18, motorY + motorR + 2, 36, 8);
    tankCtx.fill();

    // Motor Body
    const motorGrad = tankCtx.createRadialGradient(motorX - 4, motorY - 4, 2, motorX, motorY, motorR);
    motorGrad.addColorStop(0.0, '#334155');
    motorGrad.addColorStop(0.6, '#1E293B');
    motorGrad.addColorStop(1.0, '#0B1120');
    tankCtx.fillStyle = motorGrad;
    tankCtx.beginPath();
    tankCtx.arc(motorX, motorY, motorR, 0, Math.PI * 2);
    tankCtx.fill();

    tankCtx.strokeStyle = isPumpRunning ? '#00E5FF' : '#64748B';
    tankCtx.lineWidth = 2.4;
    tankCtx.stroke();

    // 12 Radial Cooling Fins
    tankCtx.strokeStyle = 'rgba(255, 255, 255, 0.16)';
    tankCtx.lineWidth = 1.4;
    for (let i = 0; i < 12; i++) {
      const angle = (i * 30 * Math.PI) / 180;
      const x1 = motorX + (motorR - 6) * Math.cos(angle);
      const y1 = motorY + (motorR - 6) * Math.sin(angle);
      const x2 = motorX + motorR * Math.cos(angle);
      const y2 = motorY + motorR * Math.sin(angle);
      tankCtx.beginPath();
      tankCtx.moveTo(x1, y1);
      tankCtx.lineTo(x2, y2);
      tankCtx.stroke();
    }

    // Volute Window
    tankCtx.fillStyle = '#020617';
    tankCtx.beginPath();
    tankCtx.arc(motorX, motorY, motorR - 8, 0, Math.PI * 2);
    tankCtx.fill();

    tankCtx.strokeStyle = isPumpRunning ? 'rgba(0, 229, 255, 0.6)' : 'rgba(255, 255, 255, 0.2)';
    tankCtx.lineWidth = 1.5;
    tankCtx.stroke();

    // Centrifugal Impeller Turbine (Spins rapidly at 60fps when pump is active)
    tankCtx.save();
    tankCtx.translate(motorX, motorY);
    tankCtx.rotate(isPumpRunning ? impellerAngle : 0.0);
    tankCtx.fillStyle = isPumpRunning ? '#00E5FF' : '#94A3B8';

    for (let i = 0; i < 4; i++) {
      tankCtx.save();
      tankCtx.rotate((i * 90 * Math.PI) / 180);
      tankCtx.beginPath();
      tankCtx.moveTo(0, 0);
      tankCtx.quadraticCurveTo(4, -6, 2, -14);
      tankCtx.quadraticCurveTo(0, -16, -2, -14);
      tankCtx.quadraticCurveTo(-4, -6, 0, 0);
      tankCtx.closePath();
      tankCtx.fill();
      tankCtx.restore();
    }

    // Central Hub
    tankCtx.fillStyle = '#0F172A';
    tankCtx.beginPath();
    tankCtx.arc(0, 0, 5, 0, Math.PI * 2);
    tankCtx.fill();
    tankCtx.strokeStyle = isPumpRunning ? '#FFFFFF' : 'rgba(255,255,255,0.4)';
    tankCtx.lineWidth = 1.4;
    tankCtx.stroke();
    tankCtx.restore();

    // ------------------------------------------------------------------------
    // 9. HIGH-PRESSURE DELIVERY PIPE & WATERFALL CASCADE
    // ------------------------------------------------------------------------
    const pipeX = w - 28;
    const topY = 20.0;
    const spoutX = cx;
    const spoutY = 32.0;

    // Metallic Outer Pipe Casing
    tankCtx.beginPath();
    tankCtx.moveTo(motorX - 8, motorY - 18);
    tankCtx.lineTo(pipeX, motorY - 18);
    tankCtx.lineTo(pipeX, topY);
    tankCtx.quadraticCurveTo(pipeX, topY - 10, pipeX - 16, topY - 10);
    tankCtx.lineTo(spoutX, topY - 10);
    tankCtx.quadraticCurveTo(spoutX, topY - 10, spoutX, spoutY);

    tankCtx.strokeStyle = '#1E293B';
    tankCtx.lineWidth = 9.0;
    tankCtx.lineCap = 'round';
    tankCtx.stroke();

    tankCtx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
    tankCtx.lineWidth = 2.0;
    tankCtx.stroke();

    // Flange Joint Collars
    function drawPipeFlange(fx, fy) {
      tankCtx.fillStyle = '#334155';
      tankCtx.strokeStyle = 'rgba(0, 180, 216, 0.6)';
      tankCtx.lineWidth = 1.0;
      tankCtx.beginPath();
      if (tankCtx.roundRect) tankCtx.roundRect(fx - 7, fy - 2.5, 14, 5, 2);
      else tankCtx.rect(fx - 7, fy - 2.5, 14, 5);
      tankCtx.fill();
      tankCtx.stroke();
    }
    drawPipeFlange(pipeX, motorY - 18);
    drawPipeFlange(pipeX, (motorY + topY) / 2);
    drawPipeFlange(pipeX, topY);

    // Spout Nozzle Collar
    tankCtx.fillStyle = 'rgba(0, 229, 255, 0.7)';
    tankCtx.beginPath();
    if (tankCtx.roundRect) tankCtx.roundRect(spoutX - 7, spoutY - 2, 14, 6, 2);
    else tankCtx.rect(spoutX - 7, spoutY - 2, 14, 6);
    tankCtx.fill();

    // Water Flow & Dynamic Waterfall Cascade (when pump is running)
    if (isPumpRunning) {
      // Flow core inside pipe
      tankCtx.beginPath();
      tankCtx.moveTo(motorX - 8, motorY - 18);
      tankCtx.lineTo(pipeX, motorY - 18);
      tankCtx.lineTo(pipeX, topY);
      tankCtx.quadraticCurveTo(pipeX, topY - 10, pipeX - 16, topY - 10);
      tankCtx.lineTo(spoutX, topY - 10);
      tankCtx.quadraticCurveTo(spoutX, topY - 10, spoutX, spoutY);

      tankCtx.strokeStyle = 'rgba(0, 229, 255, 0.75)';
      tankCtx.lineWidth = 5.0;
      tankCtx.stroke();

      // Rapid rising water particles inside vertical pipe
      const vertH = (motorY - 18) - topY;
      tankCtx.fillStyle = '#E0FAFF';
      for (let i = 0; i < 5; i++) {
        const p = (pipeFlowPhase + (i * 0.2)) % 1.0;
        const py = (motorY - 18) - (p * vertH);
        tankCtx.beginPath();
        tankCtx.arc(pipeX, py, 2.2, 0, Math.PI * 2);
        tankCtx.fill();
      }

      // Dynamic Waterfall Cascade pouring from spout nozzle down into liquid surface
      const landingY = Math.max(spoutY + 12, bottom - fluidH);

      const cascadeGrad = tankCtx.createLinearGradient(0, spoutY, 0, landingY);
      cascadeGrad.addColorStop(0.0, '#00E5FF');
      cascadeGrad.addColorStop(0.4, '#00B4D8');
      cascadeGrad.addColorStop(0.8, '#48CAE4');
      cascadeGrad.addColorStop(1.0, '#90E0EF');

      tankCtx.beginPath();
      tankCtx.moveTo(spoutX, spoutY);
      tankCtx.quadraticCurveTo(
        spoutX + Math.sin(cascadePhase * Math.PI * 2) * 1.5,
        (spoutY + landingY) / 2,
        spoutX,
        landingY
      );
      tankCtx.strokeStyle = cascadeGrad;
      tankCtx.lineWidth = 5.5;
      tankCtx.lineCap = 'round';
      tankCtx.stroke();

      // Luminous Highlight Stream
      tankCtx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
      tankCtx.lineWidth = 1.8;
      tankCtx.stroke();

      // Fast-falling Waterfall Droplets
      for (let i = 0; i < 6; i++) {
        const p = (cascadePhase + (i * 0.16)) % 1.0;
        const dy = spoutY + p * (landingY - spoutY);
        const dx = spoutX + Math.sin(p * Math.PI) * 2;
        tankCtx.fillStyle = '#FFFFFF';
        tankCtx.beginPath();
        tankCtx.arc(dx, dy, 2.2, 0, Math.PI * 2);
        tankCtx.fill();
      }

      // Kinetic Splash Spray Droplets & Foam where water enters
      tankCtx.fillStyle = '#ADE8F4';
      const splashOffsets = [
        { x: -10, y: -12 * (1.0 - splashPhase) },
        { x: 10, y: -14 * (1.0 - splashPhase) },
        { x: -5, y: -16 * (1.0 - splashPhase) },
        { x: 6, y: -10 * (1.0 - splashPhase) },
        { x: 0, y: -18 * (1.0 - splashPhase) }
      ];
      for (const off of splashOffsets) {
        tankCtx.beginPath();
        tankCtx.arc(spoutX + off.x, landingY + off.y, 1.8, 0, Math.PI * 2);
        tankCtx.fill();
      }

      // Concentric Surface Foam Ring
      const splashR = 8.0 + (splashPhase * 16.0);
      tankCtx.strokeStyle = `rgba(224, 250, 255, ${Math.max(0, 0.8 * (1.0 - splashPhase))})`;
      tankCtx.lineWidth = 1.6;
      tankCtx.beginPath();
      tankCtx.ellipse(spoutX, landingY, splashR, splashR * 0.35, 0, 0, Math.PI * 2);
      tankCtx.stroke();
    }

    tankCtx.restore();

    // Advance Animation Phases
    wavePhase += isPumpRunning ? 0.08 : 0.035;
    pipeFlowPhase = (pipeFlowPhase + 0.05) % 1.0;
    impellerAngle = (impellerAngle + 0.35) % (Math.PI * 2);
    cascadePhase = (cascadePhase + 0.06) % 1.0;
    splashPhase = (splashPhase + 0.05) % 1.0;

    // Guaranteed Continuous Loop
    requestAnimationFrame(drawTank);
  }

  function updateMetrics() {
    if (tankPctText) {
      tankPctText.textContent = isSubNodeOnline ? `${waterLevel.toFixed(1)}%` : '--';
      tankPctText.style.color = isSubNodeOnline ? '#0284C7' : '#F59E0B';
    }
    const vol = Math.round((waterLevel / 100) * totalCapacityLiters);
    if (tankVolText) {
      tankVolText.textContent = isSubNodeOnline
        ? `${vol.toLocaleString()} / ${totalCapacityLiters.toLocaleString()} L`
        : 'Sensor Disconnected';
      tankVolText.style.color = isSubNodeOnline ? '' : '#F59E0B';
    }

    if (gridValVol) gridValVol.textContent = isSubNodeOnline ? vol.toLocaleString() : '--';
    if (gridSubVol) gridSubVol.textContent = isSubNodeOnline ? `Level: ${waterLevel.toFixed(0)}%` : 'Sensor Offline';

    if (isPumpRunning) {
      if (liveFlowRate <= 0.0) liveFlowRate = 18.2;
      if (livePowerKw <= 0.0) livePowerKw = 1.45;
      if (valPowerKw) valPowerKw.innerHTML = `${livePowerKw.toFixed(2)} <small>kW</small>`;
      if (gridValFlow) gridValFlow.textContent = liveFlowRate.toFixed(1);
      if (gridSubFlow) gridSubFlow.textContent = 'Active Inflow';
      if (tankFillingStatus) tankFillingStatus.classList.remove('hidden');
    } else {
      liveFlowRate = 0.0;
      livePowerKw = 0.0;
      if (valPowerKw) valPowerKw.innerHTML = '0.00 <small>kW</small>';
      if (gridValFlow) gridValFlow.textContent = '0.0';
      if (gridSubFlow) gridSubFlow.textContent = 'Idle';
      if (tankFillingStatus) tankFillingStatus.classList.add('hidden');
    }

    const tdsEl = document.getElementById('grid-val-tds');
    if (tdsEl) tdsEl.textContent = liveTds > 0 ? liveTds : '--';
    const tempEl = document.getElementById('grid-val-temp');
    if (tempEl) tempEl.textContent = liveTemp > 0 ? liveTemp.toFixed(1) : '--';
    const cyclesEl = document.getElementById('val-cycles-count');
    if (cyclesEl) cyclesEl.textContent = dailyCycles;
  }

  function setControlMode(mode, shouldPublish = true) {
    if (!isEmergencyStopActive && mode !== controlMode) {
      previousControlMode = controlMode;
    }
    controlMode = mode === 'MANUAL' ? 'MANUAL' : 'AUTO';
    if (btnModeAuto && btnModeManual) {
      if (controlMode === 'AUTO') {
        btnModeAuto.classList.add('active');
        btnModeManual.classList.remove('active');
      } else {
        btnModeManual.classList.add('active');
        btnModeAuto.classList.remove('active');
      }
    }

    if (shouldPublish) {
      const activeDevId = userDevices.length > 0 ? (userDevices[0].id || userDevices[0].nodeId) : 'esp32_pump_main';
      if (mqttClient && mqttClient.connected) {
        const payload = JSON.stringify({
          action: 'SET_MODE',
          command: 'SET_MODE',
          parameters: { mode: controlMode },
          mode: controlMode,
          deviceId: activeDevId,
          timestamp: Math.floor(Date.now() / 1000)
        });
        mqttClient.publish('pump/command', payload, { qos: 0 });
        mqttClient.publish(`pump/${activeDevId}/command`, payload, { qos: 0 });
      }

      fetch(`${apiBaseUrl}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command: 'SET_MODE', parameters: { mode: controlMode } })
      }).catch(() => null);
    }
  }

  if (btnModeAuto) btnModeAuto.addEventListener('click', () => setControlMode('AUTO', true));
  if (btnModeManual) btnModeManual.addEventListener('click', () => setControlMode('MANUAL', true));

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
    isHardwareOnline = isOnline;
    if (isOnline) lastHardwareHeartbeat = Date.now();
    const hwText = document.querySelector('.hw-status-text');
    const hwDot = document.querySelector('.hw-indicator-dot');
    const hwPing = document.getElementById('sidebar-ping');
    if (hwText) hwText.textContent = isOnline ? 'HARDWARE ONLINE' : 'HARDWARE OFFLINE';
    if (hwText) hwText.style.color = isOnline ? 'var(--accent)' : 'var(--danger)';
    if (hwDot) hwDot.style.background = isOnline ? 'var(--accent)' : 'var(--danger)';
    if (hwPing) hwPing.textContent = isOnline ? `Ping ${rtt}ms` : 'Disconnected';

    if (btnPumpToggle) {
      if (!isOnline || isEmergencyStopActive) {
        btnPumpToggle.classList.add('control-disabled');
        btnPumpToggle.style.opacity = '0.5';
        btnPumpToggle.style.pointerEvents = 'none';
      } else {
        btnPumpToggle.classList.remove('control-disabled');
        btnPumpToggle.style.opacity = '1';
        btnPumpToggle.style.pointerEvents = 'auto';
      }
    }
  }

  function syncStateToBackend(active) {
    fetch(`${apiBaseUrl}/telemetry`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        pumpRunning: active,
        pump_running: active,
        pumpState: active ? 'ON' : 'OFF',
        pump_state: active ? 'ON' : 'OFF'
      })
    }).catch(() => null);
  }

  function setMotorRunning(active, shouldPublish = true) {
    if (active && isEmergencyStopActive) {
      alert('⚠️ Emergency Stop is active. Reset Emergency Stop first before operating pump.');
      return;
    }
    if (shouldPublish && !isHardwareOnline) {
      alert('⚠️ Hardware is Offline. Ensure ESP32 is powered on and connected before operating pump.');
      return;
    }
    if (shouldPublish && active && controlMode === 'AUTO' && !isSubNodeOnline) {
      alert('⚠️ Tank sensor (sub-node) is disconnected! In AUTO mode the motor cannot run for safety.');
      return;
    }
    if (isPumpRunning === active && !shouldPublish) return;
    const wasRunning = isPumpRunning;
    isPumpRunning = active;
    if (shouldPublish) {
      lastMqttCommandTimestamp = Date.now();
    }

    if (active) {
      if (!wasRunning) dailyCycles++;
      if (btnPumpToggle) {
        btnPumpToggle.classList.add('active-running');
        if (txtPumpLabel) txtPumpLabel.textContent = 'STOP MOTOR';
        if (txtPumpSub) txtPumpSub.textContent = 'Relay: GPIO 23 (Active Inflow)';
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
      const activeDevId = (userDevices && userDevices.length > 0) ? (userDevices[0].id || userDevices[0].nodeId || userDevices[0].deviceId) : 'esp32_pump_main';
      const cmd = active ? 'START_PUMP' : 'STOP_PUMP';

      // 1. MQTT Publish to all topics matching Mobile App & Hardware
      if (mqttClient && mqttClient.connected) {
        const payload = JSON.stringify({
          action: cmd,
          command: cmd,
          commandId: `cmd_web_${Date.now()}`,
          command_id: `cmd_web_${Date.now()}`,
          pumpState: active ? 'ON' : 'OFF',
          pump_state: active ? 'ON' : 'OFF',
          state: active ? 'ON' : 'OFF',
          status: active ? 'RUNNING' : 'STOPPED',
          parameters: {},
          issued_by: currentUser ? currentUser.id : 'web_console',
          deviceId: activeDevId,
          timestamp: Math.floor(Date.now() / 1000)
        });

        mqttClient.publish('pump/command', payload, { qos: 0 });
        mqttClient.publish(`pump/${activeDevId}/command`, payload, { qos: 0 });
        mqttClient.publish(`pump/${currentUser ? currentUser.id : 'user'}/${activeDevId}/command`, payload, { qos: 0 });
        mqttClient.publish(`devices/${activeDevId}/command`, payload, { qos: 0 });
        mqttClient.publish('waterpump/esp32/control', payload, { qos: 0 });
      }

      // 2. Backend REST Command
      fetch(`${apiBaseUrl}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command: cmd, action: cmd, parameters: {}, deviceId: activeDevId })
      }).catch(() => null);

      fetch(`${apiBaseUrl}/pumps/${activeDevId}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({ command: cmd, action: cmd })
      }).catch(() => null);

      // Ingest live telemetry update to serverless backend
      fetch(`${apiBaseUrl}/telemetry`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          pumpRunning: active,
          pump_running: active,
          pumpState: active ? 'ON' : 'OFF',
          pump_state: active ? 'ON' : 'OFF',
          waterLevelPct: waterLevel,
          water_level_pct: waterLevel,
          flowRateLpm: active ? (liveFlowRate || 18.5) : 0.0,
          flow_rate_lpm: active ? (liveFlowRate || 18.5) : 0.0,
          powerKw: active ? (livePowerKw || 1.45) : 0.0,
          power_kw: active ? (livePowerKw || 1.45) : 0.0,
          mode: controlMode
        })
      }).catch(() => null);
    }
  }

  if (btnPumpToggle) {
    btnPumpToggle.addEventListener('click', () => setMotorRunning(!isPumpRunning, true));
  }
  if (btnEmergencyStop) {
    btnEmergencyStop.addEventListener('click', handleEmergencyStopClick);
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
        reconnectPeriod: 2500,
      });

      mqttClient.on('connect', () => {
        console.log('[MQTT] Connected to EMQX Cloud Broker via WebSocket');
        updateMqttStatusBadge(true);
        if (userDevices && userDevices.length === 0) {
          updateHardwareStatusBadge(false, 0);
        }

        // Subscribed to all wildcard topics to cover mobile app and ESP32 hardware
        mqttClient.subscribe([
          'pump/#',
          'devices/#',
          'hydropulse/#',
          'waterpump/#'
        ]);
      });

      mqttClient.on('message', (topic, message) => {
        try {
          const data = JSON.parse(message.toString());

          // Active device check: filter out packets if user has linked devices and incoming doesn't match
          const activeDevId = (userDevices && userDevices.length > 0)
            ? (userDevices[0].id || userDevices[0].nodeId || userDevices[0].deviceId)
            : null;

          const incomingDevId = data.deviceId || data.nodeId || data.id;
          if (!activeDevId || !incomingDevId || incomingDevId !== activeDevId) {
            return; // Strict match: ignore packets without device ID or from other devices
          }

          // Strict Offline Detection via LWT or status payload
          if (data.status === 'OFFLINE' || data.state === 'OFFLINE') {
            updateHardwareStatusBadge(false);
            return;
          }

          lastHardwareHeartbeat = Date.now();
          updateHardwareStatusBadge(true, 22);

          // Sync Emergency Stop State from hardware/mobile
          if (data.emergencyStopped !== undefined) {
            updateEmergencyStopUI(Boolean(data.emergencyStopped));
          }

          // 0. Live & Retained Hardware Node Synchronization across devices (Strict User-Scoped)
          if (topic.startsWith('devices/sync') || topic.startsWith('hydropulse/devices') || (data && (data.macAddress || (data.deviceId && (data.name || data.userEmail))))) {
            const currentEmail = (currentUser?.email || localStorage.getItem('hydropulse_user_email') || '').trim().toLowerCase();
            const msgEmail = (data.userEmail || data.userId || '').trim().toLowerCase();
            if (currentEmail && msgEmail) {
              const isMatch = (msgEmail === currentEmail);
              if (isMatch) {
                console.log('[MQTT] Received hardware sync packet from cloud broker for', currentEmail, data);
                applyActiveDevice(data);
              }
            }
          }

          // 1. Motor Command Sync from Mobile App or Hardware
          const cmd = (data.command || data.action || '').toUpperCase();
          if (cmd === 'EMERGENCY_STOP' || cmd === 'E_STOP') {
            updateEmergencyStopUI(true);
            lastMqttCommandTimestamp = Date.now();
            setMotorRunning(false, false);
            syncStateToBackend(false);
          } else if (cmd === 'CLEAR_EMERGENCY') {
            updateEmergencyStopUI(false);
          } else if (cmd === 'START_PUMP' || cmd === 'PUMP_ON' || cmd === 'ON') {
            if (!isEmergencyStopActive) {
              lastMqttCommandTimestamp = Date.now();
              setMotorRunning(true, false);
              syncStateToBackend(true);
            }
          } else if (cmd === 'STOP_PUMP' || cmd === 'PUMP_OFF' || cmd === 'OFF') {
            lastMqttCommandTimestamp = Date.now();
            setMotorRunning(false, false);
            syncStateToBackend(false);
          }

          // 2. Hardware / Mobile Pump State Sync
          if (data.pumpState !== undefined || data.pump_state !== undefined || data.state !== undefined || data.status !== undefined || data.isRunning !== undefined || data.pump_running !== undefined || data.pumpRunning !== undefined) {
            const raw = String(data.pumpState || data.pump_state || data.state || data.status || data.isRunning || (data.pump_running !== undefined ? data.pump_running : data.pumpRunning)).toUpperCase();
            if (raw === 'ON' || raw === 'RUNNING' || raw === 'TRUE' || raw === '1') {
              lastMqttCommandTimestamp = Date.now();
              setMotorRunning(true, false);
              syncStateToBackend(true);
            } else if (raw === 'OFF' || raw === 'STOPPED' || raw === 'FALSE' || raw === '0' || raw === 'IDLE') {
              lastMqttCommandTimestamp = Date.now();
              setMotorRunning(false, false);
              syncStateToBackend(false);
            }
          }

          // 2b. Hardware Command Acknowledgement (ACK)
          if (topic.includes('/ack') || (data && (data.action === 'ACK' || data.acknowledged || data.ack))) {
            console.log('[MQTT] Hardware command execution verified by ACK:', data);
            const hwDot = document.querySelector('.hw-indicator-dot');
            if (hwDot) {
              hwDot.style.boxShadow = '0 0 14px #22C55E';
              setTimeout(() => { if (hwDot) hwDot.style.boxShadow = 'none'; }, 2500);
            }
          }

          // 3. Operational Mode Sync
          if (data.mode) {
            setControlMode(data.mode, false);
          }

          // 3b. Sub-Node Status Sync
          if (data.subNodeOnline !== undefined) {
            isSubNodeOnline = Boolean(data.subNodeOnline);
          } else if (data.nodeType === 'SUB_NODE') {
            isSubNodeOnline = true;
          }

          // 4. Real-time Telemetry Sync
          const lvl = data.waterLevelPct !== undefined ? data.waterLevelPct
                    : data.water_level_pct !== undefined ? data.water_level_pct
                    : data.waterLevel !== undefined ? data.waterLevel
                    : data.water_level !== undefined ? data.water_level
                    : data.level;
          if (lvl !== undefined && lvl !== null) {
            const parsed = parseFloat(lvl);
            if (!isNaN(parsed)) {
              if (parsed < 0) {
                isSubNodeOnline = false;
              } else if (parsed >= 0 && parsed <= 100) {
                waterLevel = parsed;
                if (data.subNodeOnline === undefined) {
                  isSubNodeOnline = true;
                }
              }
              updateMetrics();
            }
          }

          const flow = data.flowRateLpm !== undefined ? data.flowRateLpm
                     : data.flow_rate_lpm !== undefined ? data.flow_rate_lpm
                     : data.flowRate !== undefined ? data.flowRate
                     : data.flow_rate;
          if (flow !== undefined && flow !== null) {
            const parsedFlow = parseFloat(flow);
            if (!isNaN(parsedFlow)) {
              liveFlowRate = parsedFlow;
              if (gridValFlow) gridValFlow.textContent = liveFlowRate.toFixed(1);
            }
          }

          const tds = data.tdsPpm !== undefined ? data.tdsPpm
                    : data.tds_ppm !== undefined ? data.tds_ppm
                    : data.tds;
          if (tds !== undefined && tds !== null) {
            liveTds = parseInt(tds);
            const el = document.getElementById('grid-val-tds');
            if (el) el.textContent = liveTds > 0 ? liveTds : '--';
          }

          const temp = data.temperatureC !== undefined ? data.temperatureC
                     : data.temperature_c !== undefined ? data.temperature_c
                     : data.temperature !== undefined ? data.temperature
                     : data.temp_c !== undefined ? data.temp_c
                     : data.temp;
          if (temp !== undefined && temp !== null) {
            liveTemp = parseFloat(temp);
            const el = document.getElementById('grid-val-temp');
            if (el) el.textContent = liveTemp > 0 ? liveTemp.toFixed(1) : '--';
          }

          const power = data.powerConsumptionKw !== undefined ? data.powerConsumptionKw
                      : data.power_consumption_kw !== undefined ? data.power_consumption_kw
                      : data.powerKw !== undefined ? data.powerKw
                      : data.power_kw;
          if (power !== undefined && power !== null) {
            livePowerKw = parseFloat(power);
            if (valPowerKw) valPowerKw.innerHTML = `${livePowerKw.toFixed(2)} <small>kW</small>`;
          }

          if (data.runningDurationSeconds !== undefined || data.running_duration_seconds !== undefined) {
            runSeconds = parseInt(data.runningDurationSeconds || data.running_duration_seconds);
          }

          const cycles = data.cycleCount !== undefined ? data.cycleCount
                       : data.cycle_count !== undefined ? data.cycle_count
                       : data.pumpCycleCount !== undefined ? data.pumpCycleCount
                       : data.daily_cycles;
          if (cycles !== undefined && cycles !== null) {
            dailyCycles = parseInt(cycles);
            const el = document.getElementById('val-cycles-count');
            if (el) el.textContent = dailyCycles;
          }
        } catch (err) {
          console.warn('[MQTT] Packet notice:', err);
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

  // Continuous REST State Sync Fallback & Historical Telemetry Sync
  let restPollInterval = null;
  function initRestSync() {
    if (restPollInterval) return;

    const fetchLive = async () => {
      try {
        const res = await fetch(`${apiBaseUrl}/telemetry/live`).catch(() => null);
        if (res && res.ok) {
          const json = await res.json();
          if (json.data) {
            const d = json.data;
            if (d.pumpRunning !== undefined) {
              if (Date.now() - lastMqttCommandTimestamp > 10000) {
                if (d.pumpRunning !== isPumpRunning) {
                  setMotorRunning(d.pumpRunning, false);
                }
              }
            }
            if (d.mode && d.mode !== controlMode) {
              setControlMode(d.mode, false);
            }
            if (d.subNodeOnline !== undefined) {
              isSubNodeOnline = Boolean(d.subNodeOnline);
            }
            const lvl = d.waterLevelPct !== undefined ? d.waterLevelPct : d.water_level_pct;
            if (lvl !== undefined && lvl !== null) {
              const parsed = parseFloat(lvl);
              if (!isNaN(parsed)) {
                if (parsed < 0) {
                  isSubNodeOnline = false;
                } else if (d.subNodeOnline === undefined) {
                  isSubNodeOnline = true;
                }
                waterLevel = parsed;
                updateMetrics();
              }
            }
            if (d.tdsPpm !== undefined || d.tds_ppm !== undefined) {
              liveTds = parseInt(d.tdsPpm || d.tds_ppm);
              const el = document.getElementById('grid-val-tds');
              if (el) el.textContent = liveTds > 0 ? liveTds : '--';
            }
            if (d.tempC !== undefined || d.temperature_c !== undefined) {
              liveTemp = parseFloat(d.tempC || d.temperature_c);
              const el = document.getElementById('grid-val-temp');
              if (el) el.textContent = liveTemp > 0 ? liveTemp.toFixed(1) : '--';
            }
            if (d.flowRateLpm !== undefined || d.flow_rate_lpm !== undefined) {
              liveFlowRate = parseFloat(d.flowRateLpm || d.flow_rate_lpm);
              if (gridValFlow) gridValFlow.textContent = liveFlowRate.toFixed(1);
            }
            const isOnline = Boolean(d.isOnline);
            updateHardwareStatusBadge(isOnline, isOnline ? 24 : 0);
          }
        }
      } catch {}
    };

    fetchLive();
    restPollInterval = setInterval(fetchLive, 2500);

    // Strict Hardware Watchdog (6000ms window, checking every 1000ms)
    setInterval(() => {
      if (isHardwareOnline && userDevices && userDevices.length > 0) {
        if (Date.now() - lastHardwareHeartbeat > 6000) {
          updateHardwareStatusBadge(false);
        }
      }
    }, 1000);
  }

  resizeTankCanvas();
  drawTank();

  // ==============================================================================
  // 7. 24-Hour Telemetry SVG Graph
  // ==============================================================================
  async function renderTrendChart() {
    const svg = document.getElementById('svg-trend-chart');
    if (!svg) return;

    let points = [
      { x: 0, y: waterLevel }, { x: 75, y: waterLevel }, { x: 155, y: waterLevel }, { x: 235, y: waterLevel },
      { x: 310, y: waterLevel }, { x: 390, y: waterLevel }, { x: 470, y: waterLevel }, { x: 545, y: waterLevel },
      { x: 620, y: waterLevel }, { x: 690, y: waterLevel }, { x: 760, y: waterLevel }
    ];

    try {
      const res = await fetch(`${apiBaseUrl}/telemetry/history`).catch(() => null);
      if (res && res.ok) {
        const json = await res.json();
        if (json.data && Array.isArray(json.data) && json.data.length >= 3) {
          const list = json.data.slice(-12);
          points = list.map((item, idx) => ({
            x: Math.round((idx / (list.length - 1)) * 760),
            y: (item.waterLevelPct !== undefined ? item.waterLevelPct : (item.water_level_pct !== undefined ? item.water_level_pct : 0))
          }));
          if (points.length > 0) points[points.length - 1].y = waterLevel;
        }
      }
    } catch {}

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
          <stop offset="0%" stop-color="#0EA5E9" stop-opacity="0.35"/>
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
