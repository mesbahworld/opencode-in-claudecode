#!/usr/bin/env node
/**
 * oc-proxy.js — portable Anthropic<->OpenAI streaming translator.
 *
 * Claude Code only speaks the Anthropic /v1/messages protocol (streaming SSE).
 * Some providers (opencode-go's GLM/Kimi/DeepSeek, LiteLLM OpenAI routes, etc.)
 * only expose the OpenAI /v1/chat/completions protocol. This proxy bridges that
 * gap with REAL-TIME streaming: it converts the Anthropic request to OpenAI,
 * streams the OpenAI SSE back, and re-emits proper Anthropic SSE chunks as
 * tokens arrive — so Claude Code sees incremental text/tool deltas live.
 *
 * Configuration (env vars):
 *   PX_PORT                  local listen port           (default 8322)
 *   PX_UPSTREAM_BASE_URL      upstream OpenAI base URL    (default https://opencode.ai/zen/go)
 *   PX_UPSTREAM_API_KEY       key sent as "Authorization: Bearer <key>"
 *                             falls back to x-api-key header from the client request.
 *
 * The upstream path is "<base URL>/v1/chat/completions".
 *
 * Usage:  node ~/.claude/oc-proxy.js
 */
"use strict";

const http = require("http");
const https = require("https");
const { URL } = require("url");

const PORT = parseInt(process.env.PX_PORT || "8322", 10);
const UPSTREAM_BASE =
  process.env.PX_UPSTREAM_BASE_URL || "https://opencode.ai/zen/go";

const STOP_REASON_MAP = {
  stop: "end_turn",
  length: "max_tokens",
  tool_calls: "tool_use",
  function_call: "tool_use",
  content_filter: "end_turn",
};

// ── Anthropic request -> OpenAI request ─────────────────────────────────────

function toOpenAI(body, isStreaming) {
  const messages = [];

  if (body.system) {
    const sys =
      typeof body.system === "string"
        ? body.system
        : body.system
            .map((b) => (typeof b === "string" ? b : b.text || ""))
            .join("\n");
    messages.push({ role: "system", content: sys });
  }

  for (const msg of body.messages || []) {
    if (msg.role === "assistant") {
      const m = { role: "assistant" };
      const textParts = [];
      const toolCalls = [];
      if (Array.isArray(msg.content)) {
        for (const block of msg.content) {
          if (block.type === "text") textParts.push(block.text);
          else if (block.type === "tool_use") {
            toolCalls.push({
              id: block.id,
              type: "function",
              function: {
                name: block.name,
                arguments: JSON.stringify(block.input),
              },
            });
          }
        }
      } else if (typeof msg.content === "string") {
        textParts.push(msg.content);
      }
      m.content = textParts.join("") || (toolCalls.length ? "" : " ");
      if (toolCalls.length) m.tool_calls = toolCalls;
      messages.push(m);
    } else if (msg.role === "user") {
      if (Array.isArray(msg.content)) {
        const textParts = [];
        for (const block of msg.content) {
          if (block.type === "text") {
            textParts.push(block.text);
          } else if (block.type === "tool_result") {
            if (textParts.length) {
              messages.push({ role: "user", content: textParts.join("") });
              textParts.length = 0;
            }
            const rc =
              typeof block.content === "string"
                ? block.content
                : Array.isArray(block.content)
                  ? block.content
                      .map((b) => (typeof b === "string" ? b : b.text || ""))
                      .join("")
                  : JSON.stringify(block.content);
            messages.push({
              role: "tool",
              tool_call_id: block.tool_use_id,
              content: rc || " ",
            });
          } else if (block.type === "image") {
            if (textParts.length) {
              messages.push({ role: "user", content: textParts.join("") });
              textParts.length = 0;
            }
            const url =
              block.source.type === "base64"
                ? `data:${block.source.media_type};base64,${block.source.data}`
                : block.source.url || "";
            messages.push({
              role: "user",
              content: [{ type: "image_url", image_url: { url } }],
            });
          }
        }
        if (textParts.length)
          messages.push({ role: "user", content: textParts.join("") });
      } else {
        messages.push({ role: "user", content: msg.content });
      }
    }
  }

  const out = {
    model: body.model,
    messages,
    max_tokens: body.max_tokens || 4096,
    stream: isStreaming,
  };
  if (isStreaming) out.stream_options = { include_usage: true };

  if (body.tools && body.tools.length) {
    out.tools = body.tools.map((t) => ({
      type: "function",
      function: {
        name: t.name,
        description: t.description || "",
        parameters: t.input_schema || { type: "object", properties: {} },
      },
    }));
    if (body.tool_choice) {
      if (body.tool_choice.type === "auto") out.tool_choice = "auto";
      else if (body.tool_choice.type === "any") out.tool_choice = "required";
      else if (body.tool_choice.type === "tool")
        out.tool_choice = {
          type: "function",
          function: { name: body.tool_choice.name },
        };
    }
  }

  if (body.temperature !== undefined) out.temperature = body.temperature;
  if (body.top_p !== undefined) out.top_p = body.top_p;
  if (body.stop_sequences) out.stop = body.stop_sequences;

  return out;
}

// ── OpenAI non-streaming response -> Anthropic JSON ─────────────────────────

function convertOpenAIToAnthropic(rawData, requestModel) {
  const msg = JSON.parse(rawData);
  const choice = msg.choices && msg.choices[0];
  if (!choice) throw new Error("No choices in upstream response");
  const content = choice.message || {};
  const stopReason = STOP_REASON_MAP[choice.finish_reason] || "end_turn";

  const blocks = [];
  if (content.content) blocks.push({ type: "text", text: content.content });
  if (content.tool_calls) {
    for (const tc of content.tool_calls) {
      let input = {};
      try { input = JSON.parse(tc.function.arguments || "{}"); } catch {}
      blocks.push({ type: "tool_use", id: tc.id, name: tc.function.name, input });
    }
  }

  return {
    id: "msg_" + (msg.id || Math.random().toString(36).slice(2, 18)),
    type: "message",
    role: "assistant",
    content: blocks.length ? blocks : [{ type: "text", text: "" }],
    model: requestModel || msg.model || "unknown",
    stop_reason: stopReason,
    stop_sequence: null,
    usage: {
      input_tokens: msg.usage?.prompt_tokens || 0,
      output_tokens: msg.usage?.completion_tokens || 0,
    },
  };
}

// ── Real-time stream converter: OpenAI SSE -> Anthropic SSE ─────────────────

class StreamConverter {
  constructor(res, model) {
    this.res = res;
    this.model = model;
    this.started = false;
    this.blockIndex = -1;
    this.currentBlockType = null;
    this.toolCalls = {};
    this.usage = { input_tokens: 0, output_tokens: 0 };
    this.stopReason = "end_turn";
    this.buffer = "";
    this.msgId = "msg_" + Math.random().toString(36).slice(2, 18);
  }

  writeSSE(event, data) {
    this.res.write(`event: ${event}\n`);
    this.res.write(`data: ${JSON.stringify(data)}\n\n`);
  }

  ensureStarted() {
    if (this.started) return;
    this.started = true;
    this.res.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    });
    this.writeSSE("message_start", {
      type: "message_start",
      message: {
        id: this.msgId,
        type: "message",
        role: "assistant",
        content: [],
        model: this.model,
        stop_reason: null,
        stop_sequence: null,
        usage: { input_tokens: 0, output_tokens: 0 },
      },
    });
    this.writeSSE("ping", { type: "ping" });
  }

  closeCurrentBlock() {
    if (this.currentBlockType !== null) {
      this.writeSSE("content_block_stop", {
        type: "content_block_stop",
        index: this.blockIndex,
      });
      this.currentBlockType = null;
    }
  }

  feed(chunk) {
    this.buffer += chunk.toString();
    const lines = this.buffer.split("\n");
    this.buffer = lines.pop();
    for (const line of lines) this.processLine(line.trim());
  }

  processLine(line) {
    if (!line.startsWith("data:")) return;
    const data = line.slice(5).trim();
    if (!data || data === "[DONE]") return;

    let chunk;
    try { chunk = JSON.parse(data); } catch { return; }

    this.ensureStarted();

    if (chunk.usage) {
      this.usage = {
        input_tokens: chunk.usage.prompt_tokens || 0,
        output_tokens: chunk.usage.completion_tokens || 0,
      };
    }
    if (chunk.id) this.msgId = "msg_" + chunk.id;

    const choice = chunk.choices && chunk.choices[0];
    if (!choice) return;
    const delta = choice.delta || {};

    if (delta.content) {
      if (this.currentBlockType !== "text") {
        this.closeCurrentBlock();
        this.blockIndex++;
        this.currentBlockType = "text";
        this.writeSSE("content_block_start", {
          type: "content_block_start",
          index: this.blockIndex,
          content_block: { type: "text", text: "" },
        });
      }
      this.writeSSE("content_block_delta", {
        type: "content_block_delta",
        index: this.blockIndex,
        delta: { type: "text_delta", text: delta.content },
      });
    }

    if (delta.tool_calls) {
      for (const tc of delta.tool_calls) {
        const tcIdx = tc.index ?? 0;
        if (tc.id && tc.function && tc.function.name) {
          this.closeCurrentBlock();
          this.blockIndex++;
          this.currentBlockType = "tool_use";
          this.toolCalls[tcIdx] = {
            id: tc.id,
            name: tc.function.name,
            blockIndex: this.blockIndex,
          };
          this.writeSSE("content_block_start", {
            type: "content_block_start",
            index: this.blockIndex,
            content_block: {
              type: "tool_use",
              id: tc.id,
              name: tc.function.name,
              input: {},
            },
          });
        }
        if (tc.function && tc.function.arguments) {
          const blockIdx = this.toolCalls[tcIdx]?.blockIndex ?? this.blockIndex;
          this.writeSSE("content_block_delta", {
            type: "content_block_delta",
            index: blockIdx,
            delta: {
              type: "input_json_delta",
              partial_json: tc.function.arguments,
            },
          });
        }
      }
    }

    if (choice.finish_reason) {
      this.stopReason = STOP_REASON_MAP[choice.finish_reason] || "end_turn";
    }
  }

  finish() {
    this.ensureStarted();
    this.closeCurrentBlock();
    if (this.blockIndex === -1) {
      this.blockIndex = 0;
      this.writeSSE("content_block_start", {
        type: "content_block_start",
        index: 0,
        content_block: { type: "text", text: "" },
      });
      this.writeSSE("content_block_stop", { type: "content_block_stop", index: 0 });
    }
    this.writeSSE("message_delta", {
      type: "message_delta",
      delta: { stop_reason: this.stopReason, stop_sequence: null },
      usage: { output_tokens: this.usage.output_tokens },
    });
    this.writeSSE("message_stop", { type: "message_stop" });
    this.res.end();
  }
}

// ── HTTP server ──────────────────────────────────────────────────────────────

function forward(req, res, body) {
  const isStreaming = body.stream === true;
  const openaiReq = toOpenAI(body, isStreaming);

  const upstream = new URL(UPSTREAM_BASE + "/v1/chat/completions");
  const clientKey =
    req.headers["x-api-key"] ||
    req.headers["anthropic-api-key"] ||
    "";
  const apiKey = process.env.PX_UPSTREAM_API_KEY || clientKey;

  const transport = upstream.protocol === "https:" ? https : http;
  const fwdReq = transport.request(
    {
      host: upstream.hostname,
      port: upstream.port || (upstream.protocol === "https:" ? 443 : 80),
      path: upstream.pathname + upstream.search,
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${apiKey}`,
      },
    },
    (fwdRes) => {
      if (fwdRes.statusCode !== 200) {
        let data = "";
        fwdRes.on("data", (chunk) => (data += chunk));
        fwdRes.on("end", () => {
          res.writeHead(fwdRes.statusCode || 502, {
            "content-type": "application/json",
          });
          res.end(data);
        });
        return;
      }

      if (isStreaming) {
        const converter = new StreamConverter(res, body.model);
        fwdRes.on("data", (chunk) => converter.feed(chunk));
        fwdRes.on("end", () => {
          if (converter.buffer.trim()) {
            converter.processLine(converter.buffer.trim());
          }
          if (!converter.res.writableEnded) converter.finish();
        });
        fwdRes.on("error", () => {
          if (!converter.res.writableEnded) {
            converter.ensureStarted();
            converter.finish();
          }
        });
      } else {
        let data = "";
        fwdRes.on("data", (chunk) => (data += chunk));
        fwdRes.on("end", () => {
          try {
            const anthropicResp = convertOpenAIToAnthropic(data, body.model);
            res.writeHead(200, { "content-type": "application/json" });
            res.end(JSON.stringify(anthropicResp));
          } catch (e) {
            res.writeHead(502, { "content-type": "application/json" });
            res.end(
              JSON.stringify({
                type: "error",
                error: { type: "api_error", message: e.message },
              }),
            );
          }
        });
      }
    },
  );

  fwdReq.on("error", (err) => {
    res.writeHead(502, { "content-type": "application/json" });
    res.end(
      JSON.stringify({
        type: "error",
        error: { type: "api_error", message: err.message },
      }),
    );
  });

  fwdReq.write(JSON.stringify(openaiReq));
  fwdReq.end();
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST") {
    res.writeHead(405);
    res.end();
    return;
  }
  let raw = "";
  req.on("data", (chunk) => (raw += chunk));
  req.on("end", () => {
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      res.writeHead(400, { "content-type": "application/json" });
      res.end(
        JSON.stringify({
          type: "error",
          error: { type: "invalid_request_error", message: "Invalid JSON" },
        }),
      );
      return;
    }
    forward(req, res, body);
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(
    `[oc-proxy] listening on http://127.0.0.1:${PORT}  ->  ${UPSTREAM_BASE}  (Anthropic <-> OpenAI, streaming)`,
  );
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.log(`[oc-proxy] port ${PORT} already in use — assuming another instance is running.`);
  } else {
    console.error("[oc-proxy] error:", err.message);
  }
  process.exit(1);
});