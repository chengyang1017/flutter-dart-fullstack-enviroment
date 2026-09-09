import { McpServer } from "@modelcontextprotocol/server";
import { createMcpHandler } from "agents/mcp/server";
import { z } from "zod";

const SHARE_API_BASE =
  "https://workspace-storage-production.up.railway.app";

function extractShareToken(value) {
  const input = value.trim();

  if (/^[A-Za-z0-9_-]{20,}$/.test(input)) {
    return input;
  }

  try {
    const url = new URL(input);
    const parts = url.pathname.split("/").filter(Boolean);

    if (
      parts.length === 2 &&
      parts[0] === "shares" &&
      /^[A-Za-z0-9_-]{20,}$/.test(parts[1])
    ) {
      return parts[1];
    }
  } catch (_) {
    // handled below
  }

  throw new Error(
    "Expected a workspace share URL or share token.",
  );
}

function normalizeFilePath(value) {
  const path = value.trim().replace(/^\/+/, "");

  if (!path) {
    throw new Error("File path cannot be empty.");
  }

  const segments = path.split("/");

  if (
    segments.some(
      (segment) =>
        segment === "" ||
        segment === "." ||
        segment === "..",
    )
  ) {
    throw new Error("Invalid workspace file path.");
  }

  return segments
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

function toolError(error) {
  return {
    isError: true,
    content: [
      {
        type: "text",
        text: String(error),
      },
    ],
  };
}

async function fetchShareJson(path) {
  const response = await fetch(
    `${SHARE_API_BASE}${path}`,
    {
      headers: {
        accept: "application/json",
      },
    },
  );

  const body = await response.text();

  if (!response.ok) {
    throw new Error(
      `Share API returned ${response.status}: ${body}`,
    );
  }

  return body;
}

async function fetchShareFile(token, path) {
  const encodedPath = normalizeFilePath(path);

  const response = await fetch(
    `${SHARE_API_BASE}/shares/${encodeURIComponent(token)}/raw/${encodedPath}`,
    {
      headers: {
        accept: "text/plain, application/json;q=0.9, */*;q=0.1",
      },
    },
  );

  const body = await response.text();

  if (!response.ok) {
    throw new Error(
      `Share API returned ${response.status}: ${body}`,
    );
  }

  return body;
}

function createServer() {
  const server = new McpServer({
    name: "workspace-share-reader",
    version: "1.0.0",
  });

  server.registerTool(
    "get_share_metadata",
    {
      description:
        "Read metadata for a read-only IDE workspace share. " +
        "Accepts either the full share URL or its token.",
      inputSchema: {
        share: z
          .string()
          .min(1)
          .describe("Workspace share URL or share token"),
      },
    },
    async ({ share }) => {
      try {
        const token = extractShareToken(share);

        const body = await fetchShareJson(
          `/shares/${encodeURIComponent(token)}`,
        );

        return {
          content: [
            {
              type: "text",
              text: body,
            },
          ],
        };
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "get_share_tree",
    {
      description:
        "Read the complete recursive file tree for a read-only IDE workspace share.",
      inputSchema: {
        share: z
          .string()
          .min(1)
          .describe("Workspace share URL or share token"),
      },
    },
    async ({ share }) => {
      try {
        const token = extractShareToken(share);

        const body = await fetchShareJson(
          `/shares/${encodeURIComponent(token)}/tree`,
        );

        return {
          content: [
            {
              type: "text",
              text: body,
            },
          ],
        };
      } catch (error) {
        return toolError(error);
      }
    },
  );

  server.registerTool(
    "get_share_file",
    {
      description:
        "Read one source or text file from a read-only IDE workspace share by its project-relative path.",
      inputSchema: {
        share: z
          .string()
          .min(1)
          .describe("Workspace share URL or share token"),
        path: z
          .string()
          .min(1)
          .describe(
            "Project-relative file path, for example lib/main.dart or pubspec.yaml",
          ),
      },
    },
    async ({ share, path }) => {
      try {
        const token = extractShareToken(share);
        const body = await fetchShareFile(
          token,
          path,
        );

        return {
          content: [
            {
              type: "text",
              text: body,
            },
          ],
        };
      } catch (error) {
        return toolError(error);
      }
    },
  );

  return server;
}

const mcpHandler = createMcpHandler(createServer, {
  route: "/mcp",
});

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(
        JSON.stringify({
          status: "ok",
          service: "workspace-share-mcp",
        }),
        {
          headers: {
            "content-type":
              "application/json; charset=utf-8",
          },
        },
      );
    }

    return mcpHandler(request, env, ctx);
  },
};
