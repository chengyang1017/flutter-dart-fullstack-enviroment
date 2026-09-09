export default {
  async fetch(request) {
    const incoming = new URL(request.url);

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method Not Allowed', { status: 405 });
    }

    if (
      incoming.pathname !== '/health' &&
      !incoming.pathname.startsWith('/shares/')
    ) {
      return new Response('Not Found', { status: 404 });
    }

    const target = new URL(
      incoming.pathname + incoming.search,
      'https://workspace-storage-production.up.railway.app',
    );

    return fetch(target, {
      method: request.method,
      headers: {
        accept: request.headers.get('accept') ?? '*/*',
      },
      redirect: 'follow',
    });
  },
};
