import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://platform770uz-dev.github.io";
const headers = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, x-supabase-api-version, content-type",
  "Access-Control-Max-Age": "86400",
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
  "Vary": "Origin",
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers });
}

async function ipHash(ip: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(ip));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return response(403, { error: "origin_not_allowed" });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return response(405, { error: "method_not_allowed" });
  if (!req.headers.get("content-type")?.toLowerCase().includes("application/json")) {
    return response(415, { error: "unsupported_media_type" });
  }

  let body: unknown;
  try {
    const raw = await req.text();
    if (raw.length > 128) return response(400, { error: "invalid_request" });
    body = raw ? JSON.parse(raw) : {};
  } catch {
    return response(400, { error: "invalid_request" });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 0) {
    return response(400, { error: "invalid_request" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return response(503, { error: "service_unavailable" });

  const clientIp = req.headers.get("cf-connecting-ip")
    ?? req.headers.get("x-real-ip")
    ?? req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? "unknown";
  try {
    const hashedIp = await ipHash(clientIp.slice(0, 128), serviceRoleKey);
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await supabase.rpc("start_public_contract", { p_ip_hash: hashedIp });
    if (error) {
      if (error.message.includes("rate_limited")) return response(429, { error: "rate_limited" });
      return response(500, { error: "contract_creation_failed" });
    }
    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.contract_id || row.monthly_price !== 400000) {
      return response(500, { error: "contract_creation_failed" });
    }
    return response(200, {
      contract_id: row.contract_id,
      contract_number: row.contract_number,
      monthly_price: row.monthly_price,
    });
  } catch {
    return response(500, { error: "contract_creation_failed" });
  }
});
