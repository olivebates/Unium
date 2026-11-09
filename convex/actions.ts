"use node";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { createHash } from "node:crypto";
import { decodeLevel, decodeReplay, validateReplay } from "./codec";
import type { Id } from "./_generated/dataModel";

const hash = (text: string) => createHash("sha256").update(text).digest("hex");
const text = (value: unknown, limit: number) => {
  if (typeof value !== "string" || value.length > limit) throw new Error("Invalid request");
  return value;
};
const revision = (value: unknown) => {
  if (!Number.isInteger(value) || Number(value) < 0) throw new Error("Invalid revision");
  return Number(value);
};

export const dispatch = internalAction({
  args: { body: v.string() },
  handler: async (ctx, { body }): Promise<unknown> => {
    const input = JSON.parse(body);
    if (!input || typeof input !== "object" || Array.isArray(input) || !/^[a-f0-9]{64}$/.test(input.token)) throw new Error("Invalid identity");
    const owner = hash(input.token), action = text(input.action, 32);
    if (action === "list") return await ctx.runQuery(internal.community.list, { owner, sort: text(input.sort, 16), search: text(input.search, 128), cursor: input.cursor === null || input.cursor === undefined ? null : text(input.cursor, 8192) });
    if (action === "publish") {
      const code = text(input.code, 100_000), level = decodeLevel(code);
      const proof = decodeReplay(text(input.proof, 100_000), level.tiles.length);
      if (!validateReplay(level, proof).won) throw new Error("Complete the puzzle before publishing");
      return await ctx.runMutation(internal.community.publish, { owner, id: input.id ? text(input.id, 128) as Id<"levels"> : null, revision: revision(input.revision), code, name: level.name, author: level.author });
    }
    if (action === "deleteReplay") return await ctx.runMutation(internal.community.removeReplay, { owner, id: text(input.id, 128) as Id<"replays"> });
    const id = text(input.id, 128) as Id<"levels">;
    if (action === "delete") return await ctx.runMutation(internal.community.remove, { owner, id, revision: revision(input.revision) });
    if (action === "vote") return await ctx.runMutation(internal.community.vote, { owner, id, revision: revision(input.revision), value: Number(input.value) });
    if (action === "replays") return await ctx.runQuery(internal.community.replays, { id, owner, cursor: input.cursor === null || input.cursor === undefined ? null : text(input.cursor, 8192) });
    if (action === "publishReplay") {
      const level = await ctx.runQuery(internal.community.get, { id });
      if (level.revision !== revision(input.revision)) throw new Error("Level changed. Play it again");
      const code = text(input.code, 100_000), layout = decodeLevel(level.code);
      const events = decodeReplay(code, layout.tiles.length), result = validateReplay(layout, events);
      if (!result.won) throw new Error("Complete the puzzle before publishing a replay");
      const author = text(input.author, 192).trim();
      if (!author || [...author].length > 48 || /[\x00-\x1f\x7f]/.test(author)) throw new Error("Invalid author");
      return await ctx.runMutation(internal.community.publishReplay, { owner, id, revision: level.revision, author, code, levelCode: level.code, duration: result.duration, won: result.won, fingerprint: hash(id + ":" + level.revision + ":" + JSON.stringify(events)) });
    }
    throw new Error("Unknown action");
  },
});
