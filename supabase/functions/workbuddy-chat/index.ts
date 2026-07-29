const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

type WorkbuddyRequest = {
  syncKey?: string;
  currentDate?: string;
  message?: string;
  currentDayData?: unknown;
  localContext?: unknown;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return jsonResponse({}, 200);
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Only POST is supported" }, 405);
  }

  try {
    const body = await request.json() as WorkbuddyRequest;
    const syncKey = String(body.syncKey || "").trim();
    const message = String(body.message || "").trim();
    const currentDate = String(body.currentDate || "").trim();

    if (syncKey.length < 8) {
      return jsonResponse({ error: "先连接至少 8 位的云同步口令" }, 400);
    }
    if (!message) {
      return jsonResponse({ error: "消息不能为空" }, 400);
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      return jsonResponse({ error: "还没有配置 OPENAI_API_KEY" }, 500);
    }

    const cloudMemory = await loadCloudMemory(syncKey, currentDate);
    const context = {
      currentDate,
      currentDayData: body.currentDayData || {},
      localContext: body.localContext || [],
      cloudMemory
    };

    const reply = await callOpenAI(openaiKey, message, context);
    return jsonResponse({ reply }, 200);
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: error instanceof Error ? error.message : "GPT 暂时没有接上" }, 500);
  }
});

async function loadCloudMemory(syncKey: string, currentDate: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey || !currentDate) return [];

  const ownerId = await sha256Hex(syncKey);
  const url = new URL(`${supabaseUrl}/rest/v1/workbuddy_daily_entries`);
  url.searchParams.set("owner_id", `eq.${ownerId}`);
  url.searchParams.set("entry_date", `lte.${currentDate}`);
  url.searchParams.set("select", "entry_date,data,updated_at");
  url.searchParams.set("order", "entry_date.desc");
  url.searchParams.set("limit", "30");

  const response = await fetch(url, {
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`
    }
  });

  if (!response.ok) {
    console.error(await response.text());
    return [];
  }

  return await response.json();
}

async function callOpenAI(openaiKey: string, message: string, context: unknown) {
  const model = Deno.env.get("OPENAI_MODEL") || "gpt-5-mini";
  const systemPrompt = [
    "You are GPT inside Jade's Workbuddy, a mobile study dashboard for exam preparation.",
    "Answer Jade in concise Chinese unless she explicitly asks for English.",
    "You may use English when helping with foreign-press reading, vocabulary, translation, or writing practice.",
    "Use the provided tasks, finance records, articles, reviews, and chat history as memory.",
    "Do not invent records. If memory is missing, say what you can infer from the current context.",
    "Be practical, sharp, and gently ruthless about studying, but do not be cruel or demeaning.",
    "When useful, give a short next-action list that Jade can do immediately on her phone."
  ].join("\n");

  const userPrompt = [
    `Jade's message:\n${message}`,
    "",
    "Workbuddy memory JSON:",
    JSON.stringify(context).slice(0, 24000)
  ].join("\n");

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openaiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: systemPrompt }]
        },
        {
          role: "user",
          content: [{ type: "input_text", text: userPrompt }]
        }
      ],
      max_output_tokens: 900
    })
  });

  const payload = await response.json();
  if (!response.ok) {
    console.error(payload);
    throw new Error(payload?.error?.message || "OpenAI 请求失败");
  }

  return extractOutputText(payload) || "我接上了，但这次没有生成内容。";
}

function extractOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === "string") return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  return output.flatMap((item) => {
    const record = item as Record<string, unknown>;
    const content = Array.isArray(record.content) ? record.content : [];
    return content.map((part) => {
      const contentPart = part as Record<string, unknown>;
      return String(contentPart.text || contentPart.output_text || "");
    }).filter(Boolean);
  }).join("\n").trim();
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(payload: unknown, status: number) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}
