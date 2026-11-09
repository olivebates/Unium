import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
const http = httpRouter();
http.route({ path: "/community", method: "OPTIONS", handler: httpAction(async () => new Response(null, { status: 204, headers })) });
http.route({
  path: "/community", method: "POST", handler: httpAction(async (ctx, request) => {
    const body = await request.text();
    if (new TextEncoder().encode(body).length > 240_000) return new Response(JSON.stringify({ error: "Request too large" }), { status: 413, headers });
    try {
      const result = await ctx.runAction(internal.actions.dispatch, { body });
      const status = result && typeof result === "object" && "error" in result && result.error === "publish_cooldown" ? 429 : 200;
      return new Response(JSON.stringify(result), { status, headers });
    } catch (error) {
      // Avoid returning internal stack traces, IDs, or database details.
      console.error("Community request failed", error);
      return new Response(JSON.stringify({ error: "Request failed. Refresh and try again" }), { status: 400, headers });
    }
  }),
});
export default http;
