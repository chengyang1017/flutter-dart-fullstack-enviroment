(() => {
  const API_BASE =
    (window.FLUTTER_WORKBENCH_API_URL || '').trim() ||
    'https://workspace-storage-production.up.railway.app';
  const TOKEN_KEY = 'flutter_workbench_admin_token';
  const MESSAGES_KEY = 'flutter_workbench_admin_agent_messages_v1';

  let saving = false;

  function token() {
    return (sessionStorage.getItem(TOKEN_KEY) || '').trim();
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

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function findCourse(catalog, courseId) {
    const groups = Array.isArray(catalog?.projects) ? catalog.projects : [];
    for (const group of groups) {
      const lessons = Array.isArray(group?.lessons) ? group.lessons : [];
      for (const lesson of lessons) {
        if (String(lesson?.id || '') === courseId) return lesson;
      }
    }
    return null;
  }

  function copyTranslations(source, target) {
    if (!source || !target) return;

    if (source.translations && typeof source.translations === 'object') {
      target.translations = clone(source.translations);
    }

    const sourceSteps = Array.isArray(source.steps) ? source.steps : [];
    const targetSteps = new Map(
      (Array.isArray(target.steps) ? target.steps : [])
        .filter((step) => step && step.id)
        .map((step) => [String(step.id), step]),
    );

    for (const sourceStep of sourceSteps) {
      const targetStep = targetSteps.get(String(sourceStep?.id || ''));
      if (!targetStep) continue;
      if (
        sourceStep.translations &&
        typeof sourceStep.translations === 'object'
      ) {
        targetStep.translations = clone(sourceStep.translations);
      }
    }
  }

  function appendSavedMessage(courseId) {
    try {
      const parsed = JSON.parse(sessionStorage.getItem(MESSAGES_KEY) || '[]');
      if (!Array.isArray(parsed)) return;
      parsed.push({
        role: 'assistant',
        content:
          `Saved the applied translation for “${courseId}” to the course catalog. ` +
          'Courses are refreshing now.',
      });
      sessionStorage.setItem(MESSAGES_KEY, JSON.stringify(parsed.slice(-40)));
    } catch (_) {}
  }

  function showBridgeError(message) {
    const status = document.querySelector('#fw-agent-status');
    if (status) {
      status.textContent = `Save failed: ${message}`;
      status.dataset.state = 'offline';
    }
  }

  function clickRefresh() {
    const refresh = Array.from(document.querySelectorAll('button')).find(
      (button) => button.textContent?.includes('Refresh'),
    );
    if (refresh) {
      refresh.click();
      return;
    }
    window.location.reload();
  }

  async function persistAppliedDraft(textarea) {
    if (saving) return;

    let draft;
    try {
      draft = JSON.parse(textarea.value);
    } catch (_) {
      return;
    }

    const courseId = String(draft?.id || '').trim();
    if (!courseId || !draft.translations) return;

    saving = true;
    try {
      const catalog = await api('/admin/lessons');
      const course = findCourse(catalog, courseId);
      if (!course) {
        throw new Error(`Course “${courseId}” was not found in the catalog.`);
      }

      // Only copy localized presentation data. The persisted root fields stay
      // canonical Chinese, so existing Flutter lesson/checker decoding remains
      // compatible. AdminApi will materialize the selected language on refresh.
      copyTranslations(draft, course);

      await api('/admin/lessons', {
        method: 'PUT',
        body: JSON.stringify(catalog),
      });

      appendSavedMessage(courseId);
      clickRefresh();
    } catch (error) {
      showBridgeError(error instanceof Error ? error.message : String(error));
    } finally {
      saving = false;
    }
  }

  document.addEventListener(
    'input',
    (event) => {
      const textarea = event.target;
      if (!(textarea instanceof HTMLTextAreaElement)) return;
      if (textarea.getAttribute('aria-label') !== 'Current course JSON') return;

      // Agent apply dispatches a synthetic input event. Human JSON typing uses
      // trusted browser events and should keep the existing review/save flow.
      if (event.isTrusted) return;

      window.setTimeout(() => persistAppliedDraft(textarea), 0);
    },
    true,
  );
})();
