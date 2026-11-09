import { internalMutation, internalQuery } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { displayScore, hotScore, periods } from "./ranking";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";

const PUBLISH_INTERVAL = 300_000;

async function deleteRelated(ctx: MutationCtx, id: Id<"levels">, beforeRevision?: number) {
  const votes = await (beforeRevision === undefined
    ? ctx.db.query("votes").withIndex("by_level", q => q.eq("level", id))
    : ctx.db.query("votes").withIndex("by_level_revision", q => q.eq("level", id).lt("revision", beforeRevision))).take(100);
  const replays = await (beforeRevision === undefined
    ? ctx.db.query("replays").withIndex("by_level", q => q.eq("level", id))
    : ctx.db.query("replays").withIndex("by_level_revision", q => q.eq("level", id).lt("revision", beforeRevision))).take(100);
  for (const row of [...votes, ...replays]) await ctx.db.delete(row._id);
  return votes.length === 100 || replays.length === 100;
}

async function rateLimit(ctx: MutationCtx, owner: string, bucket: string, maximum: number) {
  const now = Date.now();
  const limit = await ctx.db.query("limits").withIndex("by_owner_bucket", q => q.eq("owner", owner).eq("bucket", bucket)).unique();
  if (!limit) {
    await ctx.db.insert("limits", { owner, bucket, start: now, count: 1 });
  } else if (now - limit.start >= 3_600_000) {
    await ctx.db.patch(limit._id, { start: now, count: 1 });
  } else {
    if (limit.count >= maximum) throw new Error("Try again later");
    await ctx.db.patch(limit._id, { count: limit.count + 1 });
  }
}

export const list = internalQuery({
  args: { owner: v.string(), sort: v.string(), search: v.string(), cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, args) => {
    if (!(args.sort in periods)) throw new Error("Invalid sort");
    const period = periods[args.sort];
    const cutoff = Number.isFinite(period) ? Date.now() - period : 0;
    const search = args.search.trim().toLocaleLowerCase().slice(0, 128);
    const query = ctx.db.query("levels").withIndex(args.sort === "Hot" ? "by_hot" : "by_score").order("desc");
    // Pagination bounds each read. Time and search filters run before paginate.
    const page = await query.filter(q => q.gte(q.field("created"), cutoff)).paginate({ cursor: args.cursor, numItems: 40 });
    const levels = [];
    for (const level of page.page) {
      if (search && !`${level.name} ${level.author}`.toLocaleLowerCase().includes(search)) continue;
      const vote = await ctx.db.query("votes").withIndex("by_voter_level", q => q.eq("voter", args.owner).eq("level", level._id).eq("revision", level.revision)).unique();
      const replayCount = level.replayCount ?? (await ctx.db.query("replays").withIndex("by_level_revision", q => q.eq("level", level._id).eq("revision", level.revision)).collect()).length;
      levels.push({ id: level._id, revision: level.revision, name: level.name, author: level.author, code: level.code, created: level.created, score: displayScore(level.score, level.created), rawScore: level.score, replayCount, vote: vote?.value ?? 0 });
    }
    const owned = await ctx.db.query("levels").withIndex("by_owner", q => q.eq("owner", args.owner)).take(1000);
    const cooldown = await ctx.db.query("limits").withIndex("by_owner_bucket", q => q.eq("owner", args.owner).eq("bucket", "publish_cooldown")).unique();
    const nextPublishAt = cooldown ? cooldown.start + PUBLISH_INTERVAL : 0;
    return { levels, owned: owned.map(level => level._id), cursor: page.isDone ? null : page.continueCursor, nextPublishAt, retryAfterMs: Math.max(0, nextPublishAt - Date.now()) };
  },
});

export const get = internalQuery({
  args: { id: v.id("levels") },
  handler: async (ctx, { id }) => {
    const level = await ctx.db.get(id);
    if (!level) throw new Error("Level removed");
    return { code: level.code, revision: level.revision };
  },
});

export const publish = internalMutation({
  args: { owner: v.string(), id: v.union(v.id("levels"), v.null()), revision: v.number(), code: v.string(), name: v.string(), author: v.string() },
  handler: async (ctx, args) => {
    const now = Date.now();
    const level = args.id ? await ctx.db.get(args.id) : null;
    if (args.id) {
      if (!level || level.owner !== args.owner) throw new Error("Only the author can edit this level");
      if (level.revision !== args.revision) throw new Error("Level changed. Reopen it before editing");
    }
    const cooldown = await ctx.db.query("limits").withIndex("by_owner_bucket", q => q.eq("owner", args.owner).eq("bucket", "publish_cooldown")).unique();
    if (cooldown && now < cooldown.start + PUBLISH_INTERVAL) {
      return { error: "publish_cooldown" as const, nextPublishAt: cooldown.start + PUBLISH_INTERVAL, retryAfterMs: cooldown.start + PUBLISH_INTERVAL - now };
    }
    if (cooldown) await ctx.db.patch(cooldown._id, { start: now, count: 1 });
    else await ctx.db.insert("limits", { owner: args.owner, bucket: "publish_cooldown", start: now, count: 1 });
    const nextPublishAt = now + PUBLISH_INTERVAL;
    if (args.id && level) {
      const revision = level.revision + 1;
      await ctx.db.patch(args.id, { code: args.code, name: args.name, author: args.author, revision, updated: now, up: 0, down: 0, score: 0, hot: hotScore(0, 0, level.created), replayCount: 0 });
      if (await deleteRelated(ctx, args.id, revision)) await ctx.scheduler.runAfter(0, internal.community.cleanup, { id: args.id, beforeRevision: revision });
      return { id: args.id, revision, nextPublishAt, retryAfterMs: PUBLISH_INTERVAL };
    }
    const id = await ctx.db.insert("levels", { name: args.name, author: args.author, code: args.code, owner: args.owner, revision: 1, created: now, updated: now, up: 0, down: 0, score: 0, hot: hotScore(0, 0, now), replayCount: 0 });
    return { id, revision: 1, nextPublishAt, retryAfterMs: PUBLISH_INTERVAL };
  },
});

export const remove = internalMutation({
  args: { owner: v.string(), id: v.id("levels"), revision: v.number() },
  handler: async (ctx, args) => {
    const level = await ctx.db.get(args.id);
    if (!level || level.owner !== args.owner) throw new Error("Only the author can delete this level");
    if (level.revision !== args.revision) throw new Error("Level changed. Refresh first");
    await ctx.db.delete(args.id);
    // Related rows are removed in bounded scheduled batches.
    await ctx.scheduler.runAfter(0, internal.community.cleanup, { id: args.id });
    return { ok: true };
  },
});

export const cleanup = internalMutation({
  args: { id: v.id("levels"), beforeRevision: v.optional(v.number()) },
  handler: async (ctx, args) => {
    if (await deleteRelated(ctx, args.id, args.beforeRevision)) await ctx.scheduler.runAfter(0, internal.community.cleanup, args);
  },
});

export const vote = internalMutation({
  args: { owner: v.string(), id: v.id("levels"), revision: v.number(), value: v.number() },
  handler: async (ctx, args) => {
    if (![-1, 0, 1].includes(args.value)) throw new Error("Invalid vote");
    await rateLimit(ctx, args.owner, "vote", 300);
    const level = await ctx.db.get(args.id);
    if (!level || level.revision !== args.revision) throw new Error("Level changed. Refresh first");
    const previous = await ctx.db.query("votes").withIndex("by_voter_level", q => q.eq("voter", args.owner).eq("level", args.id).eq("revision", args.revision)).unique();
    const before = previous?.value ?? 0;
    if (previous) await ctx.db.patch(previous._id, { value: args.value });
    else await ctx.db.insert("votes", { level: args.id, revision: args.revision, voter: args.owner, value: args.value });
    const up = level.up - Number(before === 1) + Number(args.value === 1);
    const down = level.down - Number(before === -1) + Number(args.value === -1);
    await ctx.db.patch(args.id, { up, down, score: up - down, hot: hotScore(up, down, level.created) });
    return { ok: true, score: displayScore(up - down, level.created), rawScore: up - down, created: level.created, vote: args.value };
  },
});

export const replays = internalQuery({
  args: { id: v.id("levels"), owner: v.string(), cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, args) => {
    const level = await ctx.db.get(args.id);
    if (!level) throw new Error("Level removed");
    const page = await ctx.db.query("replays").withIndex("by_level_revision", q => q.eq("level", args.id).eq("revision", level.revision)).order("desc").paginate({ cursor: args.cursor, numItems: 25 });
    return { replays: page.page.map(row => ({ id: row._id, author: row.author, code: row.code, levelCode: row.levelCode, duration: row.duration, won: row.won, revision: row.revision, owned: row.owner === args.owner })), cursor: page.isDone ? null : page.continueCursor };
  },
});

export const removeReplay = internalMutation({
  args: { id: v.id("replays"), owner: v.string() },
  handler: async (ctx, args) => {
    const replay = await ctx.db.get(args.id);
    if (!replay) return { ok: true };
    if (replay.owner !== args.owner) throw new Error("Only the author can delete this replay");
    const level = await ctx.db.get(replay.level);
    await ctx.db.delete(args.id);
    if (level?.revision === replay.revision && level.replayCount !== undefined) await ctx.db.patch(level._id, { replayCount: Math.max(0, level.replayCount - 1) });
    return { ok: true };
  },
});

export const publishReplay = internalMutation({
  args: { owner: v.string(), id: v.id("levels"), revision: v.number(), author: v.string(), code: v.string(), levelCode: v.string(), duration: v.number(), won: v.boolean(), fingerprint: v.string() },
  handler: async (ctx, args) => {
    if (!args.won) throw new Error("Complete the puzzle before publishing a replay");
    const level = await ctx.db.get(args.id);
    if (!level || level.revision !== args.revision || level.code !== args.levelCode) throw new Error("Level changed. Play it again");
    const existing = await ctx.db.query("replays").withIndex("by_owner_fingerprint", q => q.eq("owner", args.owner).eq("fingerprint", args.fingerprint)).first();
    if (existing) return { id: existing._id };
    await rateLimit(ctx, args.owner, "replay", 60);
    const count = level.replayCount ?? (await ctx.db.query("replays").withIndex("by_level_revision", q => q.eq("level", args.id).eq("revision", level.revision)).collect()).length;
    const { id, ...fields } = args;
    const replayId = await ctx.db.insert("replays", { ...fields, level: id });
    await ctx.db.patch(args.id, { replayCount: count + 1 });
    return { id: replayId };
  },
});
