const SHARE_API_BASE =
  'https://workspace-storage-production.up.railway.app';

const SHARE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{20,}$/;

function getViewToken(pathname) {
  const parts = pathname.split('/').filter(Boolean);

  if (
    parts.length === 2 &&
    parts[0] === 'view' &&
    SHARE_TOKEN_PATTERN.test(parts[1])
  ) {
    return parts[1];
  }

  return null;
}

function renderShareView(shareToken) {
  const scriptUrl =
    '/webmcp.js?share=' +
    encodeURIComponent(shareToken);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1"
  >
  <title>Workspace Share</title>

  <style>
    :root {
      color-scheme: light dark;
      font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        sans-serif;
    }

    body {
      margin: 0;
      padding: 32px;
      max-width: 860px;
    }

    code {
      word-break: break-all;
    }

    .card {
      border: 1px solid currentColor;
      border-radius: 16px;
      padding: 20px;
      opacity: 0.9;
    }

    #status {
      margin-top: 16px;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <h1>Read-only Workspace Share</h1>

  <div class="card">
    <p>
      This page exposes a fixed, read-only workspace
      snapshot to supported AI agents through WebMCP.
    </p>

    <p>
      Share token:
      <code>${shareToken}</code>
    </p>

    <p id="status">
      Detecting site tools…
    </p>
  </div>

  <script src="${scriptUrl}"></script>
</body>
</html>`;
}

function renderWebMcpScript(shareToken) {
  const encodedToken =
    encodeURIComponent(shareToken);

  return `
(() => {
  const status =
    document.getElementById('status');

  const modelContext =
    document.modelContext ||
    navigator.modelContext;

  if (
    !modelContext ||
    typeof modelContext.registerTool !== 'function'
  ) {
    if (status) {
      status.textContent =
        'WebMCP is not available in this browser.';
    }

    return;
  }

  const token = ${JSON.stringify(shareToken)};
  const encodedToken = ${JSON.stringify(encodedToken)};

  const controller = new AbortController();

  window.addEventListener(
    'pagehide',
    () => controller.abort(),
    { once: true },
  );

  async function fetchText(url, accept) {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        accept: accept || '*/*',
      },
    });

    const body = await response.text();

    if (!response.ok) {
      throw new Error(
        'Workspace share API returned ' +
        response.status +
        ': ' +
        body
      );
    }

    return body;
  }

  function normalizePath(value) {
    const path =
      String(value || '')
        .trim()
        .replace(/^\\/+/, '');

    if (!path) {
      throw new Error(
        'File path cannot be empty.'
      );
    }

    const segments = path.split('/');

    if (
      segments.some(
        (segment) =>
          !segment ||
          segment === '.' ||
          segment === '..'
      )
    ) {
      throw new Error(
        'Invalid workspace file path.'
      );
    }

    return segments
      .map((segment) =>
        encodeURIComponent(segment)
      )
      .join('/');
  }

  async function registerTools() {
    await modelContext.registerTool(
      {
        name: 'get_share_metadata',

        description:
          'Read metadata for the immutable, read-only ' +
          'workspace snapshot currently open in this page.',

        inputSchema: {
          type: 'object',
          properties: {},
          additionalProperties: false,
        },

        annotations: {
          readOnlyHint: true,
        },

        async execute() {
          return fetchText(
            '/shares/' + encodedToken,
            'application/json'
          );
        },
      },
      {
        signal: controller.signal,
      }
    );

    await modelContext.registerTool(
      {
        name: 'get_share_tree',

        description:
          'Read the complete recursive project file tree ' +
          'for the immutable workspace snapshot currently ' +
          'open in this page.',

        inputSchema: {
          type: 'object',
          properties: {},
          additionalProperties: false,
        },

        annotations: {
          readOnlyHint: true,
        },

        async execute() {
          return fetchText(
            '/shares/' +
              encodedToken +
              '/tree',
            'application/json'
          );
        },
      },
      {
        signal: controller.signal,
      }
    );

    await modelContext.registerTool(
      {
        name: 'get_share_file',

        description:
          'Read one text or source file from the immutable ' +
          'workspace snapshot currently open in this page. ' +
          'Use a project-relative path such as lib/main.dart.',

        inputSchema: {
          type: 'object',

          properties: {
            path: {
              type: 'string',
              minLength: 1,
              description:
                'Project-relative file path, for example ' +
                'lib/main.dart or pubspec.yaml.',
            },
          },

          required: ['path'],
          additionalProperties: false,
        },

        annotations: {
          readOnlyHint: true,
        },

        async execute(input) {
          const path =
            normalizePath(input.path);

          return fetchText(
            '/shares/' +
              encodedToken +
              '/raw/' +
              path,
            'text/plain, application/json;q=0.9, */*;q=0.1'
          );
        },
      },
      {
        signal: controller.signal,
      }
    );

    if (status) {
      status.textContent =
        '3 read-only WebMCP site tools are available.';
    }

    console.log(
      'WebMCP workspace tools registered for share:',
      token
    );
  }

  registerTools().catch((error) => {
    console.error(
      'Failed to register WebMCP tools:',
      error
    );

    if (status) {
      status.textContent =
        'Failed to register site tools: ' +
        String(error);
    }
  });
})();
`;
}

export default {
  async fetch(request) {
    const incoming =
      new URL(request.url);

    if (
      request.method !== 'GET' &&
      request.method !== 'HEAD'
    ) {
      return new Response(
        'Method Not Allowed',
        { status: 405 },
      );
    }

    const viewToken =
      getViewToken(incoming.pathname);

    if (viewToken) {
      const html =
        renderShareView(viewToken);

      return new Response(
        request.method === 'HEAD'
          ? null
          : html,
        {
          status: 200,
          headers: {
            'content-type':
              'text/html; charset=utf-8',

            'cache-control':
              'no-store',

            'content-security-policy':
              "default-src 'self'; " +
              "script-src 'self'; " +
              "connect-src 'self'; " +
              "style-src 'unsafe-inline'; " +
              "base-uri 'none'; " +
              "frame-ancestors 'none'",

            'referrer-policy':
              'no-referrer',

            'x-content-type-options':
              'nosniff',
          },
        },
      );
    }

    if (
      incoming.pathname ===
      '/webmcp.js'
    ) {
      const shareToken =
        incoming.searchParams.get(
          'share',
        );

      if (
        !shareToken ||
        !SHARE_TOKEN_PATTERN.test(
          shareToken,
        )
      ) {
        return new Response(
          'Invalid share token',
          { status: 400 },
        );
      }

      const script =
        renderWebMcpScript(
          shareToken,
        );

      return new Response(
        request.method === 'HEAD'
          ? null
          : script,
        {
          status: 200,
          headers: {
            'content-type':
              'text/javascript; charset=utf-8',

            'cache-control':
              'no-store',

            'x-content-type-options':
              'nosniff',
          },
        },
      );
    }

    if (
      incoming.pathname !==
        '/health' &&
      !incoming.pathname.startsWith(
        '/shares/',
      )
    ) {
      return new Response(
        'Not Found',
        { status: 404 },
      );
    }

    const target =
      new URL(
        incoming.pathname +
          incoming.search,
        SHARE_API_BASE,
      );

    return fetch(target, {
      method: request.method,

      headers: {
        accept:
          request.headers.get(
            'accept',
          ) ?? '*/*',
      },

      redirect: 'follow',
    });
  },
};
