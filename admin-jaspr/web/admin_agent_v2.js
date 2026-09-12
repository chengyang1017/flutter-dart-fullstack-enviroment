(() => {
  const API_BASE =
    (window.FLUTTER_WORKBENCH_API_URL || '').trim() ||
    'https://workspace-storage-production.up.railway.app';
  const TOKEN_KEY = 'flutter_workbench_admin_token';
  const MESSAGES_KEY = 'flutter_workbench_admin_agent_messages_v1';
  const OPEN_KEY = 'flutter_workbench_admin_agent_open_v1';
  const MAX_MESSAGES = 40;

  const state = {
    open: sessionStorage.getItem(OPEN_KEY) === '1',
    messages: loadMessages(),
    busy: false,
    status: null,
    proposal: null,
  };

  let launcher;
  let panel;
  let contextLabel;
  let statusLabel;
  let messagesEl;
  let proposalEl;
  let composer;
  let sendButton;
  let translateEnButton;
  let translateZhButton;

  function loadMessages() {
    try {
      const raw = sessionStorage.getItem(MESSAGES_KEY);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed
        .filter(
          (item) =>
            item &&
            (item.role === 'user' || item.role === 'assistant') &&
            typeof item.content === 'string',
        )
        .slice(-MAX_MESSAGES);
    } catch (_) {
      return [];
    }
  }

  function persistMessages() {
    sessionStorage.setItem(
      MESSAGES_KEY,
      JSON.stringify(state.messages.slice(-MAX_MESSAGES)),
    );
  }

  function pushMessage(role, content) {
    const value = String(content || '').trim();
    if (!value) return;
    state.messages.push({ role, content: value });
    if (state.messages.length > MAX_MESSAGES) {
      state.messages = state.messages.slice(-MAX_MESSAGES);
    }
    persistMessages();
    renderMessages();
  }

  function token() {
    return (sessionStorage.getItem(TOKEN_KEY) || '').trim();
  }

  function currentCourseTextarea() {
    return document.querySelector(
      'textarea[aria-label="Current course JSON"]',
    );
  }

  function readCurrentCourse() {
    const textarea = currentCourseTextarea();
    if (!textarea) return null;
    try {
      const decoded = JSON.parse(textarea.value);
      return decoded && typeof decoded === 'object' ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  function currentSection() {
    const title = document.querySelector('.topbar h1');
    return (title?.textContent || '').trim() || 'Admin';
  }

  function currentEditLanguage() {
    const buttons = Array.from(document.querySelectorAll('button'));
    const english = buttons.find(
      (button) =>
        button.textContent?.trim() === 'English' &&
        button.classList.contains('primary-button'),
    );
    if (english) return 'en';

    const chinese = buttons.find(
      (button) =>
        button.textContent?.trim() === '中文' &&
        button.classList.contains('primary-button'),
    );
    if (chinese) return 'zh';

    return 'en';
  }

  function pick(source, keys) {
    const result = {};
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(source, key)) {
        result[key] = source[key];
      }
    }
    return result;
  }

  function compactCourse(course) {
    if (!course || typeof course !== 'object') return null;
    const result = pick(course, [
      'id',
      'title',
      'description',
      'difficulty',
      'category',
      'tags',
      'prerequisites',
    ]);
    result.steps = Array.isArray(course.steps)
      ? course.steps.slice(0, 24).map((step) =>
          pick(step || {}, [
            'id',
            'part',
            'title',
            'instruction',
            'explanation',
            'hints',
          ]),
        )
      : [];
    return result;
  }

  function currentContext() {
    return {
      section: currentSection(),
      language: currentEditLanguage(),
      course: compactCourse(readCurrentCourse()),
    };
  }

  function setText(element, value) {
    if (element && element.textContent !== value) {
      element.textContent = value;
    }
  }

  function syncContext() {
    if (!contextLabel || !translateEnButton || !translateZhButton) return;
    const course = readCurrentCourse();
    if (course) {
      const title = String(course.title || course.id || 'Selected course');
      setText(
        contextLabel,
        `${title} · ${currentEditLanguage().toUpperCase()}`,
      );
      translateEnButton.hidden = false;
      translateZhButton.hidden = false;
    } else {
      setText(contextLabel, `${currentSection()} · no course selected`);
      translateEnButton.hidden = true;
      translateZhButton.hidden = true;
    }
  }

  async function api(path, options = {}) {
    const accessToken = token();
    if (!accessToken) throw new Error('Admin session is not available.');

    const response = await fetch(`${API_BASE}${path}`, {
      ...options,
      headers: {
        authorization: `Bearer ${accessToken}`,
        accept: 'application/json',
        ...(options.body ? { 'content-type': 'application/json' } : {}),
        ...(options.headers || {}),
      },
    });

    let body = {};
    try {
      body = await response.json();
    } catch (_) {}

    if (!response.ok) {
      throw new Error(body.error || `Request failed (${response.status}).`);
    }
    return body;
  }

  async function refreshStatus() {
    if (!token()) return;
    try {
      state.status = await api('/admin/agent/status');
    } catch (error) {
      state.status = {
        configured: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
    renderStatus();
  }

  function renderStatus() {
    if (!statusLabel) return;
    if (state.busy) {
      setText(statusLabel, 'Agent is working…');
      statusLabel.dataset.state = 'checking';
      return;
    }
    if (!state.status) {
      setText(statusLabel, 'Checking agent…');
      statusLabel.dataset.state = 'checking';
      return;
    }
    if (state.status.configured) {
      setText(statusLabel, `${state.status.model || 'AI'} · ready`);
      statusLabel.dataset.state = 'ready';
      return;
    }
    setText(
      statusLabel,
      state.status.error
        ? 'Agent backend unavailable'
        : 'Agent key not configured',
    );
    statusLabel.dataset.state = 'offline';
  }

  function setBusy(value) {
    state.busy = value;
    if (sendButton) sendButton.disabled = value;
    if (translateEnButton) translateEnButton.disabled = value;
    if (translateZhButton) translateZhButton.disabled = value;
    if (composer) composer.disabled = value;
    renderStatus();
  }

  function renderMessages() {
    if (!messagesEl) return;
    messagesEl.replaceChildren();

    if (state.messages.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'fw-agent-empty';
      const title = document.createElement('strong');
      title.textContent = 'Course assistant';
      const copy = document.createElement('span');
      copy.textContent =
        'Ask about wording, localization or the current course. Use the quick actions for safe translation drafts.';
      empty.append(title, copy);
      messagesEl.appendChild(empty);
      return;
    }

    for (const message of state.messages) {
      const bubble = document.createElement('div');
      bubble.className = `fw-agent-message ${message.role}`;

      const role = document.createElement('span');
      role.className = 'fw-agent-message-role';
      role.textContent = message.role === 'user' ? 'You' : 'Agent';

      const content = document.createElement('div');
      content.className = 'fw-agent-message-content';
      content.textContent = message.content;

      bubble.append(role, content);
      messagesEl.appendChild(bubble);
    }
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function renderProposal() {
    if (!proposalEl) return;
    proposalEl.replaceChildren();
    proposalEl.hidden = !state.proposal;
    if (!state.proposal) return;

    const target =
      state.proposal.targetLanguage === 'zh' ? '中文' : 'English';

    const title = document.createElement('strong');
    title.textContent = `${target} translation ready`;

    const copy = document.createElement('span');
    copy.textContent =
      'Nothing is saved yet. Apply it to the current course draft, review it, then save the course JSON.';

    const actions = document.createElement('div');
    actions.className = 'fw-agent-proposal-actions';

    const dismiss = document.createElement('button');
    dismiss.className = 'fw-agent-secondary';
    dismiss.type = 'button';
    dismiss.textContent = 'Dismiss';
    dismiss.addEventListener('click', () => {
      state.proposal = null;
      renderProposal();
    });

    const apply = document.createElement('button');
    apply.className = 'fw-agent-primary';
    apply.type = 'button';
    apply.textContent = `Apply ${target}`;
    apply.addEventListener('click', applyProposal);

    actions.append(dismiss, apply);
    proposalEl.append(title, copy, actions);
  }

  async function sendMessage() {
    if (!composer || state.busy) return;
    const value = composer.value.trim();
    if (!value) return;

    composer.value = '';
    pushMessage('user', value);
    setBusy(true);

    try {
      const result = await api('/admin/agent/chat', {
        method: 'POST',
        body: JSON.stringify({
          messages: state.messages.slice(-16),
          context: currentContext(),
        }),
      });
      pushMessage('assistant', result.reply || 'No response.');
    } catch (error) {
      pushMessage(
        'assistant',
        `Agent error: ${error instanceof Error ? error.message : String(error)}`,
      );
    } finally {
      setBusy(false);
    }
  }

  async function requestTranslation(targetLanguage) {
    if (state.busy) return;
    const course = readCurrentCourse();
    if (!course) {
      openPanel();
      pushMessage(
        'assistant',
        'Select a course first. I translate the course currently open in Courses.',
      );
      return;
    }

    const target = targetLanguage === 'zh' ? 'zh' : 'en';
    const source = target === 'en' ? 'zh' : 'en';
    openPanel();
    pushMessage(
      'user',
      target === 'en'
        ? `Translate the current course “${course.title || course.id}” to English.`
        : `把当前课程“${course.title || course.id}”翻译成中文。`,
    );
    setBusy(true);

    try {
      const result = await api('/admin/agent/translate', {
        method: 'POST',
        body: JSON.stringify({
          course,
          sourceLanguage: source,
          targetLanguage: target,
        }),
      });
      state.proposal = result.proposal || null;
      pushMessage(
        'assistant',
        result.reply ||
          (target === 'en'
            ? 'English translation draft is ready.'
            : '中文翻译草稿已生成。'),
      );
      renderProposal();
    } catch (error) {
      pushMessage(
        'assistant',
        `Translation failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    } finally {
      setBusy(false);
    }
  }

  function applyNodeTranslation(node, targetLanguage, translated, fields) {
    const translations =
      node.translations && typeof node.translations === 'object'
        ? { ...node.translations }
        : {};
    const locale =
      translations[targetLanguage] &&
      typeof translations[targetLanguage] === 'object'
        ? { ...translations[targetLanguage] }
        : {};

    for (const field of fields) {
      if (Object.prototype.hasOwnProperty.call(translated, field)) {
        locale[field] = translated[field];
      }
    }
    translations[targetLanguage] = locale;
    node.translations = translations;

    if (currentEditLanguage() === targetLanguage) {
      for (const field of fields) {
        if (Object.prototype.hasOwnProperty.call(locale, field)) {
          node[field] = locale[field];
        }
      }
    }
  }

  function applyProposal() {
    const proposal = state.proposal;
    const textarea = currentCourseTextarea();
    const course = readCurrentCourse();

    if (!proposal || !textarea || !course) {
      pushMessage(
        'assistant',
        'The selected course changed, so the translation draft was not applied.',
      );
      state.proposal = null;
      renderProposal();
      return;
    }

    if (
      proposal.courseId &&
      String(course.id || '') !== String(proposal.courseId)
    ) {
      pushMessage(
        'assistant',
        'This translation belongs to another course. Re-run translation for the currently selected course.',
      );
      return;
    }

    const target = proposal.targetLanguage === 'zh' ? 'zh' : 'en';
    applyNodeTranslation(
      course,
      target,
      proposal.course || {},
      [
        'title',
        'description',
        'difficulty',
        'category',
        'tags',
        'prerequisites',
      ],
    );

    const stepsById = new Map(
      (Array.isArray(course.steps) ? course.steps : [])
        .filter((step) => step && step.id)
        .map((step) => [String(step.id), step]),
    );

    for (const translatedStep of Array.isArray(proposal.steps)
      ? proposal.steps
      : []) {
      const step = stepsById.get(String(translatedStep.id || ''));
      if (!step) continue;
      applyNodeTranslation(
        step,
        target,
        translatedStep,
        ['part', 'title', 'instruction', 'explanation', 'hints'],
      );
    }

    textarea.value = JSON.stringify(course, null, 2);
    textarea.dispatchEvent(new Event('input', { bubbles: true }));

    state.proposal = null;
    renderProposal();
    pushMessage(
      'assistant',
      target === 'en'
        ? 'Applied the English translation to the current course draft. Review it, then click “Validate & save course JSON”.'
        : '已把中文翻译写入当前课程草稿。检查后点击“Validate & save course JSON”保存。',
    );
  }

  function syncOpenState() {
    if (!panel || !launcher) return;
    panel.classList.toggle('open', state.open);
    panel.setAttribute('aria-hidden', state.open ? 'false' : 'true');
    launcher.classList.toggle('hidden', state.open);
    document.body.classList.toggle('fw-agent-open', state.open);
  }

  function openPanel() {
    state.open = true;
    sessionStorage.setItem(OPEN_KEY, '1');
    syncOpenState();
    syncContext();
    if (!state.status) refreshStatus();
    window.setTimeout(() => composer?.focus(), 50);
  }

  function closePanel() {
    state.open = false;
    sessionStorage.setItem(OPEN_KEY, '0');
    syncOpenState();
  }

  function syncAuthState() {
    if (!launcher || !panel) return;
    const loggedIn =
      Boolean(token()) && Boolean(document.querySelector('.console-shell'));
    launcher.hidden = !loggedIn;
    panel.hidden = !loggedIn;

    if (!loggedIn) {
      document.body.classList.remove('fw-agent-open');
      return;
    }

    syncOpenState();
    syncContext();
  }

  function mount() {
    launcher = document.createElement('button');
    launcher.id = 'fw-admin-agent-launcher';
    launcher.type = 'button';
    launcher.innerHTML = '<span>✦</span><strong>Agent</strong>';
    launcher.addEventListener('click', openPanel);

    panel = document.createElement('aside');
    panel.id = 'fw-admin-agent-panel';
    panel.setAttribute('aria-label', 'Flutter Workbench admin agent');
    panel.innerHTML = `
      <div class="fw-agent-header">
        <div class="fw-agent-brand">
          <div class="fw-agent-mark">✦</div>
          <div>
            <strong>Course Agent</strong>
            <span id="fw-agent-status">Checking agent…</span>
          </div>
        </div>
        <button class="fw-agent-icon-button" id="fw-agent-close" type="button" aria-label="Close agent">×</button>
      </div>
      <div class="fw-agent-context">
        <span>Current context</span>
        <strong id="fw-agent-context-label">Admin</strong>
      </div>
      <div class="fw-agent-quick-actions">
        <button id="fw-agent-translate-en" type="button">Translate → English</button>
        <button id="fw-agent-translate-zh" type="button">翻译 → 中文</button>
      </div>
      <div id="fw-agent-messages" class="fw-agent-messages"></div>
      <div id="fw-agent-proposal" class="fw-agent-proposal" hidden></div>
      <div class="fw-agent-composer">
        <textarea id="fw-agent-input" rows="3" placeholder="Ask the agent about the current course…"></textarea>
        <div class="fw-agent-composer-footer">
          <span>Ctrl/⌘ + Enter to send</span>
          <button id="fw-agent-send" class="fw-agent-primary" type="button">Send</button>
        </div>
      </div>
    `;

    document.body.append(launcher, panel);

    contextLabel = panel.querySelector('#fw-agent-context-label');
    statusLabel = panel.querySelector('#fw-agent-status');
    messagesEl = panel.querySelector('#fw-agent-messages');
    proposalEl = panel.querySelector('#fw-agent-proposal');
    composer = panel.querySelector('#fw-agent-input');
    sendButton = panel.querySelector('#fw-agent-send');
    translateEnButton = panel.querySelector('#fw-agent-translate-en');
    translateZhButton = panel.querySelector('#fw-agent-translate-zh');

    panel
      .querySelector('#fw-agent-close')
      .addEventListener('click', closePanel);
    sendButton.addEventListener('click', sendMessage);
    translateEnButton.addEventListener('click', () => requestTranslation('en'));
    translateZhButton.addEventListener('click', () => requestTranslation('zh'));
    composer.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        sendMessage();
      }
    });

    renderMessages();
    renderProposal();
    renderStatus();
    syncAuthState();

    // Deliberately poll at a low frequency instead of observing the whole DOM.
    // The previous MutationObserver wrote textContent from inside its own
    // callback, which could trigger an endless child-mutation loop and starve
    // the Jaspr client during startup.
    window.setInterval(syncAuthState, 900);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, { once: true });
  } else {
    mount();
  }
})();
