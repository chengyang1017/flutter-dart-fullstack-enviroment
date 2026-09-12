(() => {
  const API_BASE =
    (window.FLUTTER_WORKBENCH_API_URL || '').trim() ||
    'https://workspace-storage-production.up.railway.app';
  const TOKEN_KEY = 'flutter_workbench_admin_token';
  const MESSAGES_KEY = 'flutter_workbench_admin_agent_messages_v1';
  const OPEN_KEY = 'flutter_workbench_admin_agent_open_v1';
  const MAX_MESSAGES = 40;

  const COURSE_FIELDS = [
    'title',
    'description',
    'difficulty',
    'category',
    'tags',
    'prerequisites',
  ];
  const STEP_FIELDS = [
    'part',
    'title',
    'instruction',
    'explanation',
    'hints',
  ];
  const GROUP_FIELDS = ['title', 'description'];

  const state = {
    open: sessionStorage.getItem(OPEN_KEY) === '1',
    messages: loadMessages(),
    busy: false,
    status: null,
    proposal: null,
    batch: null,
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
  let batchAllEnButton;
  let batchMissingEnButton;
  let batchAllZhButton;
  let batchMissingZhButton;
  let batchStatusEl;
  let batchProgressBar;
  let batchSaveButton;
  let batchDiscardButton;

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
    const result = pick(course, ['id', ...COURSE_FIELDS]);
    result.steps = Array.isArray(course.steps)
      ? course.steps.slice(0, 24).map((step) =>
          pick(step || {}, ['id', ...STEP_FIELDS]),
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
    const buttons = [
      sendButton,
      translateEnButton,
      translateZhButton,
      batchAllEnButton,
      batchMissingEnButton,
      batchAllZhButton,
      batchMissingZhButton,
      batchSaveButton,
      batchDiscardButton,
    ];
    for (const button of buttons) {
      if (button) button.disabled = value;
    }
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

  function localizedMap(node, languageCode) {
    const translations =
      node &&
      node.translations &&
      typeof node.translations === 'object'
        ? node.translations
        : null;
    const locale =
      translations &&
      translations[languageCode] &&
      typeof translations[languageCode] === 'object'
        ? translations[languageCode]
        : null;
    return locale;
  }

  function containsCjk(value) {
    if (typeof value === 'string') {
      return /[\u3400-\u9fff]/u.test(value);
    }
    if (Array.isArray(value)) {
      return value.some((item) => containsCjk(String(item)));
    }
    return false;
  }

  function fieldNeedsTranslation(node, targetLanguage, field) {
    if (!node || typeof node !== 'object') return false;
    if (!Object.prototype.hasOwnProperty.call(node, field)) return false;

    const locale = localizedMap(node, targetLanguage);
    if (!locale || !Object.prototype.hasOwnProperty.call(locale, field)) {
      return true;
    }

    const source = node[field];
    const target = locale[field];

    if (typeof source === 'string' && source.trim() && !String(target || '').trim()) {
      return true;
    }

    if (
      Array.isArray(source) &&
      source.length > 0 &&
      (!Array.isArray(target) || target.length === 0)
    ) {
      return true;
    }

    if (targetLanguage === 'en' && containsCjk(target)) {
      return true;
    }

    return false;
  }

  function nodeNeedsTranslation(node, targetLanguage, fields) {
    return fields.some((field) =>
      fieldNeedsTranslation(node, targetLanguage, field),
    );
  }

  function courseNeedsTranslation(course, targetLanguage) {
    if (nodeNeedsTranslation(course, targetLanguage, COURSE_FIELDS)) {
      return true;
    }
    const steps = Array.isArray(course?.steps) ? course.steps : [];
    return steps.some((step) =>
      nodeNeedsTranslation(step, targetLanguage, STEP_FIELDS),
    );
  }

  function applyNodeTranslation(
    node,
    targetLanguage,
    translated,
    fields,
    options = {},
  ) {
    const { onlyMissing = false, materializeRoot = false } = options;
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
      if (!Object.prototype.hasOwnProperty.call(translated, field)) continue;
      if (
        onlyMissing &&
        !fieldNeedsTranslation(node, targetLanguage, field)
      ) {
        continue;
      }
      locale[field] = translated[field];
    }

    translations[targetLanguage] = locale;
    node.translations = translations;

    if (materializeRoot) {
      for (const field of fields) {
        if (Object.prototype.hasOwnProperty.call(locale, field)) {
          node[field] = locale[field];
        }
      }
    }
  }

  function applyCourseProposal(
    course,
    proposal,
    targetLanguage,
    options = {},
  ) {
    applyNodeTranslation(
      course,
      targetLanguage,
      proposal.course || {},
      COURSE_FIELDS,
      options,
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
        targetLanguage,
        translatedStep,
        STEP_FIELDS,
        options,
      );
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
    applyCourseProposal(course, proposal, target, {
      materializeRoot: currentEditLanguage() === target,
    });

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

  function batchTaskLabel(task) {
    const node = task.node || {};
    const name = String(node.title || node.id || 'Untitled');
    return task.kind === 'group' ? `Group · ${name}` : name;
  }

  function buildBatchTasks(catalog, targetLanguage, onlyMissing) {
    const tasks = [];
    const groups = Array.isArray(catalog?.projects) ? catalog.projects : [];

    for (const group of groups) {
      if (
        !onlyMissing ||
        nodeNeedsTranslation(group, targetLanguage, GROUP_FIELDS)
      ) {
        tasks.push({ kind: 'group', node: group });
      }

      const lessons = Array.isArray(group?.lessons) ? group.lessons : [];
      for (const course of lessons) {
        if (
          !onlyMissing ||
          courseNeedsTranslation(course, targetLanguage)
        ) {
          tasks.push({ kind: 'course', node: course });
        }
      }
    }
    return tasks;
  }

  function groupAsCourse(group) {
    return {
      id: String(group.id || group.title || 'course-group'),
      title: group.title || '',
      description: group.description || '',
      translations:
        group.translations && typeof group.translations === 'object'
          ? group.translations
          : {},
      steps: [],
    };
  }

  async function translateBatchTask(
    task,
    targetLanguage,
    onlyMissing,
  ) {
    const sourceLanguage = targetLanguage === 'en' ? 'zh' : 'en';
    const payloadCourse =
      task.kind === 'group' ? groupAsCourse(task.node) : task.node;

    const result = await api('/admin/agent/translate', {
      method: 'POST',
      body: JSON.stringify({
        course: payloadCourse,
        sourceLanguage,
        targetLanguage,
      }),
    });

    const proposal = result.proposal;
    if (!proposal || typeof proposal !== 'object') {
      throw new Error('Agent returned no translation proposal.');
    }

    if (task.kind === 'group') {
      applyNodeTranslation(
        task.node,
        targetLanguage,
        proposal.course || {},
        GROUP_FIELDS,
        { onlyMissing },
      );
    } else {
      applyCourseProposal(task.node, proposal, targetLanguage, {
        onlyMissing,
      });
    }
  }

  async function startBatchTranslation(targetLanguage, onlyMissing) {
    if (state.busy) return;
    const target = targetLanguage === 'zh' ? 'zh' : 'en';
    const targetLabel = target === 'zh' ? '中文' : 'English';
    const modeLabel = onlyMissing ? 'missing / stale only' : 'all content';

    openPanel();
    state.batch = {
      running: true,
      target,
      onlyMissing,
      total: 0,
      done: 0,
      success: 0,
      failed: 0,
      current: 'Loading catalog…',
      failures: [],
      catalog: null,
      dirty: false,
    };
    renderBatch();
    setBusy(true);
    pushMessage(
      'user',
      `Batch translate ${modeLabel} → ${targetLabel}.`,
    );

    try {
      const catalog = await api('/admin/lessons');
      const tasks = buildBatchTasks(catalog, target, onlyMissing);
      state.batch.catalog = catalog;
      state.batch.total = tasks.length;
      state.batch.current =
        tasks.length === 0 ? 'Nothing to translate.' : 'Starting…';
      renderBatch();

      if (tasks.length === 0) {
        state.batch.running = false;
        pushMessage(
          'assistant',
          `No ${targetLabel} translations need updating.`,
        );
        return;
      }

      for (const task of tasks) {
        state.batch.current = batchTaskLabel(task);
        renderBatch();

        try {
          await translateBatchTask(task, target, onlyMissing);
          state.batch.success += 1;
          state.batch.dirty = true;
        } catch (error) {
          state.batch.failed += 1;
          state.batch.failures.push(
            `${batchTaskLabel(task)}: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        } finally {
          state.batch.done += 1;
          renderBatch();
        }
      }

      state.batch.running = false;
      state.batch.current = '';
      renderBatch();

      const summary =
        `${state.batch.success}/${state.batch.total} ${targetLabel} translation tasks ready` +
        (state.batch.failed
          ? `; ${state.batch.failed} failed.`
          : '.');

      pushMessage(
        'assistant',
        `${summary} Nothing has been saved yet. Review the batch summary, then click “Save all translations”.`,
      );
    } catch (error) {
      state.batch.running = false;
      state.batch.current = '';
      state.batch.failed += 1;
      state.batch.failures.push(
        error instanceof Error ? error.message : String(error),
      );
      renderBatch();
      pushMessage(
        'assistant',
        `Batch translation failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    } finally {
      setBusy(false);
      renderBatch();
    }
  }

  async function saveBatchTranslations() {
    const batch = state.batch;
    if (
      state.busy ||
      !batch ||
      !batch.catalog ||
      !batch.dirty ||
      batch.running
    ) {
      return;
    }

    setBusy(true);
    try {
      await api('/admin/lessons', {
        method: 'PUT',
        body: JSON.stringify(batch.catalog),
      });
      const targetLabel = batch.target === 'zh' ? '中文' : 'English';
      pushMessage(
        'assistant',
        `${targetLabel} batch translations saved. Reloading Courses so the selected language is materialized everywhere.`,
      );
      state.batch = null;
      renderBatch();
      window.setTimeout(() => window.location.reload(), 650);
    } catch (error) {
      pushMessage(
        'assistant',
        `Saving batch translations failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    } finally {
      setBusy(false);
    }
  }

  function discardBatch() {
    if (state.busy || !state.batch) return;
    state.batch = null;
    renderBatch();
    pushMessage('assistant', 'Unsaved batch translation draft discarded.');
  }

  function renderBatch() {
    if (!batchStatusEl || !batchProgressBar) return;
    const batch = state.batch;

    if (!batch) {
      batchStatusEl.innerHTML =
        '<strong>Catalog localization</strong><span>Translate every course group, course and step. “Missing only” also repairs English fields that still contain Chinese.</span>';
      batchProgressBar.hidden = true;
      if (batchSaveButton) batchSaveButton.hidden = true;
      if (batchDiscardButton) batchDiscardButton.hidden = true;
      return;
    }

    const targetLabel = batch.target === 'zh' ? '中文' : 'English';
    const percent =
      batch.total > 0
        ? Math.round((batch.done / batch.total) * 100)
        : 0;

    if (batch.running) {
      batchStatusEl.innerHTML = '';
      const title = document.createElement('strong');
      title.textContent = `${targetLabel} · ${batch.done}/${batch.total}`;
      const copy = document.createElement('span');
      copy.textContent = batch.current || 'Translating…';
      batchStatusEl.append(title, copy);
      batchProgressBar.hidden = false;
      batchProgressBar.firstElementChild.style.width = `${percent}%`;
      if (batchSaveButton) batchSaveButton.hidden = true;
      if (batchDiscardButton) batchDiscardButton.hidden = true;
      return;
    }

    const title = document.createElement('strong');
    title.textContent = batch.dirty
      ? `${targetLabel} batch ready`
      : `${targetLabel} batch finished`;
    const copy = document.createElement('span');
    copy.textContent =
      `${batch.success} ready · ${batch.failed} failed · ${batch.total} checked.` +
      (batch.dirty ? ' Changes are not saved yet.' : '');

    batchStatusEl.replaceChildren(title, copy);
    batchProgressBar.hidden = false;
    batchProgressBar.firstElementChild.style.width = '100%';

    if (batch.failures.length) {
      const failures = document.createElement('span');
      failures.className = 'fw-agent-batch-failures';
      failures.textContent = batch.failures.slice(0, 3).join(' | ');
      batchStatusEl.appendChild(failures);
    }

    if (batchSaveButton) {
      batchSaveButton.hidden = !batch.dirty;
      batchSaveButton.disabled = state.busy;
    }
    if (batchDiscardButton) {
      batchDiscardButton.hidden = false;
      batchDiscardButton.disabled = state.busy;
    }
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
      <div class="fw-agent-batch">
        <div id="fw-agent-batch-status" class="fw-agent-batch-status"></div>
        <div class="fw-agent-batch-actions">
          <button id="fw-agent-batch-all-en" type="button">All → EN</button>
          <button id="fw-agent-batch-missing-en" type="button">Missing → EN</button>
          <button id="fw-agent-batch-all-zh" type="button">All → 中文</button>
          <button id="fw-agent-batch-missing-zh" type="button">Missing → 中文</button>
        </div>
        <div id="fw-agent-batch-progress" class="fw-agent-batch-progress" hidden>
          <div></div>
        </div>
        <div class="fw-agent-batch-review">
          <button id="fw-agent-batch-discard" class="fw-agent-secondary" type="button" hidden>Discard</button>
          <button id="fw-agent-batch-save" class="fw-agent-primary" type="button" hidden>Save all translations</button>
        </div>
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
    batchAllEnButton = panel.querySelector('#fw-agent-batch-all-en');
    batchMissingEnButton = panel.querySelector('#fw-agent-batch-missing-en');
    batchAllZhButton = panel.querySelector('#fw-agent-batch-all-zh');
    batchMissingZhButton = panel.querySelector('#fw-agent-batch-missing-zh');
    batchStatusEl = panel.querySelector('#fw-agent-batch-status');
    batchProgressBar = panel.querySelector('#fw-agent-batch-progress');
    batchSaveButton = panel.querySelector('#fw-agent-batch-save');
    batchDiscardButton = panel.querySelector('#fw-agent-batch-discard');

    panel
      .querySelector('#fw-agent-close')
      .addEventListener('click', closePanel);
    sendButton.addEventListener('click', sendMessage);
    translateEnButton.addEventListener('click', () => requestTranslation('en'));
    translateZhButton.addEventListener('click', () => requestTranslation('zh'));
    batchAllEnButton.addEventListener('click', () =>
      startBatchTranslation('en', false),
    );
    batchMissingEnButton.addEventListener('click', () =>
      startBatchTranslation('en', true),
    );
    batchAllZhButton.addEventListener('click', () =>
      startBatchTranslation('zh', false),
    );
    batchMissingZhButton.addEventListener('click', () =>
      startBatchTranslation('zh', true),
    );
    batchSaveButton.addEventListener('click', saveBatchTranslations);
    batchDiscardButton.addEventListener('click', discardBatch);
    composer.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
        event.preventDefault();
        sendMessage();
      }
    });

    renderMessages();
    renderProposal();
    renderBatch();
    renderStatus();
    syncAuthState();

    window.setInterval(syncAuthState, 900);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount, { once: true });
  } else {
    mount();
  }
})();
