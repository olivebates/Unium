import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import schema from "../convex/schema";
import { internal } from "../convex/_generated/api";
import { hotScore } from "../convex/ranking";
import { createCipheriv, createHash } from "node:crypto";
import { gzipSync } from "node:zlib";

const modules = import.meta.glob("../convex/**/*.{ts,js}");
const generated = new URL("../.test-user/community-fixture.json", import.meta.url);
const fixture = JSON.parse(readFileSync(existsSync(generated) ? generated : new URL("./fixtures/community.json", import.meta.url), "utf8"));
const owner = "a".repeat(64), stranger = "b".repeat(64);
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(1_800_000_000_000); });
afterEach(() => vi.useRealTimers());

// Portable replay containing just one click: valid input, unfinished puzzle.
function unfinishedReplay() {
  const raw = Buffer.from([1, 1, 0, 2]), size = Buffer.alloc(4), iv = Buffer.alloc(16, 7);
  size.writeUInt32LE(raw.length);
  const key = createHash("sha256").update("Hearthline/community/portable-save/v1").digest();
  const cipher = createCipheriv("aes-256-cbc", key, iv);
  return "HR1." + Buffer.concat([iv, cipher.update(Buffer.concat([size, gzipSync(raw)])), cipher.final()]).toString("base64url");
}

async function publish(t: ReturnType<typeof convexTest>, extra = {}) {
  const result = await t.mutation(internal.community.publish, { owner, id: null, revision: 0, name: "Puzzle", author: "Fox", code: fixture.code, ...extra });
  if (!result.id || result.revision === undefined) throw new Error(result.error);
  return { id: result.id, revision: result.revision };
}

test("ownership prevents edits/deletes, revisions prevent lost updates", async () => {
  const t = convexTest(schema, modules);
  const level = await publish(t);
  await expect(publish(t, { ...level, owner: stranger })).rejects.toThrow(/Only the author/);
  vi.advanceTimersByTime(300_000);
  const updated = await publish(t, level);
  expect(updated.revision).toBe(2);
  await expect(publish(t, level)).rejects.toThrow(/Level changed/);
  await expect(t.mutation(internal.community.remove, { owner: stranger, ...updated })).rejects.toThrow(/Only the author/);
  const list = await t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null });
  expect(list.owned).toEqual([level.id]);
  expect(list.levels[0]).not.toHaveProperty("owner");
});

test("votes are replaceable, idempotent and scoped to the current revision", async () => {
  const t = convexTest(schema, modules), level = await publish(t);
  const vote = (value: number) => t.mutation(internal.community.vote, { owner: stranger, ...level, value });
  expect((await vote(1)).score).toBe(1);
  expect((await vote(1)).score).toBe(1);
  expect(await vote(-1)).toMatchObject({ score: 0, rawScore: -1, vote: -1 });
  expect((await vote(0)).score).toBe(0);
  await expect(vote(2)).rejects.toThrow(/Invalid vote/);
  await vote(1);
  vi.advanceTimersByTime(300_000);
  await publish(t, level);
  await expect(vote(-1)).rejects.toThrow(/Level changed/);
  const list = await t.query(internal.community.list, { owner: stranger, sort: "All time", search: "fox", cursor: null });
  expect(list.levels[0].score).toBe(0);
  expect(list.levels[0].vote).toBe(0);
});

test("negative scores stay hidden for exactly 24 hours from original release", async () => {
  vi.useFakeTimers();
  try {
    const released = 1_800_000_000_000;
    vi.setSystemTime(released);
    const t = convexTest(schema, modules), level = await publish(t);
    const vote = (value: number, revision = 1) => t.mutation(internal.community.vote, { owner: stranger, id: level.id, revision, value });
    const list = () => t.query(internal.community.list, { owner: stranger, sort: "All time", search: "", cursor: null });
    expect(await vote(-1)).toMatchObject({ score: 0, rawScore: -1, created: released });
    expect((await list()).levels[0]).toMatchObject({ score: 0, rawScore: -1, vote: -1 });
    expect(await t.run(ctx => ctx.db.get(level.id))).toMatchObject({ up: 0, down: 1, score: -1 });
    vi.setSystemTime(released + 86_400_000 - 1);
    expect((await list()).levels[0].score).toBe(0);
    vi.setSystemTime(released + 86_400_000);
    expect((await list()).levels[0].score).toBe(-1);
    expect((await vote(-1)).score).toBe(-1);
    expect((await vote(1)).score).toBe(1);
    const updated = await publish(t, level);
    expect((await vote(-1, updated.revision)).score).toBe(-1);
  } finally { vi.useRealTimers(); }
});

test("publishing has an atomic personal five-minute cooldown shared by edits and new levels", async () => {
  const t = convexTest(schema, modules), start = Date.now();
  const args = { owner, id: null, revision: 0, name: "Puzzle", author: "Fox", code: fixture.code };
  const first = await publish(t);
  expect(await t.mutation(internal.community.publish, args)).toMatchObject({ error: "publish_cooldown", retryAfterMs: 300_000 });
  expect(await t.mutation(internal.community.publish, { ...args, ...first })).toMatchObject({ error: "publish_cooldown", nextPublishAt: start + 300_000 });
  await publish(t, { owner: stranger });
  vi.setSystemTime(start + 299_990);
  const listing = await t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null });
  expect(listing).toMatchObject({ nextPublishAt: start + 300_000, retryAfterMs: 10 });
  vi.setSystemTime(start + 299_999);
  expect(await t.mutation(internal.community.publish, args)).toMatchObject({ error: "publish_cooldown", retryAfterMs: 1 });
  vi.setSystemTime(start + 300_000);
  const edited = await publish(t, first);
  expect(edited.revision).toBe(2);
  expect(await t.mutation(internal.community.publish, args)).toMatchObject({ error: "publish_cooldown", nextPublishAt: start + 600_000 });
  await t.mutation(internal.community.remove, { owner, ...edited });
  expect(await t.mutation(internal.community.publish, args)).toMatchObject({ error: "publish_cooldown" });
  vi.advanceTimersByTime(300_000);
  const simultaneous = await Promise.all([t.mutation(internal.community.publish, args), t.mutation(internal.community.publish, args)]);
  expect(simultaneous.filter(result => result.id)).toHaveLength(1);
  expect(simultaneous.filter(result => result.error === "publish_cooldown")).toHaveLength(1);
});

test("old-version batch cleanup preserves new replays, votes and replay counts", async () => {
  const t = convexTest(schema, modules), level = await publish(t);
  const old = { level: level.id, revision: 1, author: "Fox", owner, code: fixture.proofCode, levelCode: fixture.code, duration: 200, won: true, fingerprint: "old" };
  await t.run(async ctx => {
    for (let i = 0; i < 105; i++) {
      await ctx.db.insert("replays", { ...old, fingerprint: "old-" + i });
      await ctx.db.insert("votes", { level: level.id, revision: 1, voter: "old-" + i, value: 1 });
    }
    await ctx.db.patch(level.id, { replayCount: 105, up: 105, score: 105 });
  });
  vi.setSystemTime(Date.now() + 300_000);
  const edited = await publish(t, level);
  expect((await t.query(internal.community.replays, { id: level.id, owner, cursor: null })).replays).toHaveLength(0);
  const fresh = await t.mutation(internal.community.publishReplay, { owner, ...edited, author: "New", code: fixture.proofCode, levelCode: fixture.code, duration: 200, won: true, fingerprint: "fresh" });
  await t.mutation(internal.community.vote, { owner: stranger, ...edited, value: 1 });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await t.run(ctx => ctx.db.query("replays").collect())).map(row => row._id)).toEqual([fresh.id]);
  expect(await t.run(ctx => ctx.db.query("votes").collect())).toMatchObject([{ revision: 2 }]);
  expect(await t.run(ctx => ctx.db.get(level.id))).toMatchObject({ revision: 2, score: 1, replayCount: 1 });
});

test("top periods exclude older puzzles; hot uses Reddit score", async () => {
  const t = convexTest(schema, modules), now = Date.now();
  const old = await publish(t, { name: "Older" }), fresh = await publish(t, { name: "Fresh", owner: stranger });
  await t.run(async ctx => {
    await ctx.db.patch(old.id, { created: now - 8 * 86_400_000, score: 20, up: 20, hot: hotScore(20, 0, now - 8 * 86_400_000) });
    await ctx.db.patch(fresh.id, { score: 2, up: 2, hot: hotScore(2, 0, now) });
  });
  const list = (sort: string) => t.query(internal.community.list, { owner, sort, search: "", cursor: null });
  expect((await list("Week")).levels.map(row => row.id)).toEqual([fresh.id]);
  expect((await list("Month")).levels.map(row => row.id)).toEqual([old.id, fresh.id]);
  expect((await list("All time")).levels[0].id).toBe(old.id);
  expect((await list("Hot")).levels[0].id).toBe(fresh.id);
});

test("republishing deletes previous votes and replays and resets all counts", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules), level = await publish(t);
    const args = { owner, ...level, author: "Fox", code: fixture.replayCode, levelCode: fixture.code, duration: 5050, won: true, fingerprint: "same-input" };
    await expect(t.mutation(internal.community.publishReplay, { ...args, won: false })).rejects.toThrow(/Complete the puzzle/);
    const a = await t.mutation(internal.community.publishReplay, args);
    expect(await t.mutation(internal.community.publishReplay, args)).toEqual(a);
    await t.mutation(internal.community.vote, { owner: stranger, ...level, value: 1 });
    vi.advanceTimersByTime(300_000);
    await publish(t, level);
    const replays = await t.query(internal.community.replays, { id: level.id, owner, cursor: null });
    expect(replays.replays).toHaveLength(0);
    expect(await t.run(ctx => ctx.db.get(a.id))).toBeNull();
    expect(await t.run(ctx => ctx.db.query("votes").collect())).toHaveLength(0);
    const listing = await t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null });
    expect(listing.levels[0]).toMatchObject({ replayCount: 0, score: 0, vote: 0 });
    await expect(t.mutation(internal.community.publishReplay, args)).rejects.toThrow(/Level changed/);
    await t.mutation(internal.community.remove, { owner, id: level.id, revision: 2 });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(await t.run(ctx => ctx.db.query("replays").collect())).toHaveLength(0);
  } finally { vi.useRealTimers(); }
});

test("replay counts include legacy rows and increase only for new uploads", async () => {
  const t = convexTest(schema, modules), level = await publish(t);
  const args = { owner, ...level, author: "Fox", code: fixture.proofCode, levelCode: fixture.code, duration: 200, won: true, fingerprint: "one" };
  await t.mutation(internal.community.publishReplay, args);
  await t.mutation(internal.community.publishReplay, args);
  const list = () => t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null });
  expect((await list()).levels[0].replayCount).toBe(1);
  await t.run(ctx => ctx.db.patch(level.id, { replayCount: undefined }));
  expect((await list()).levels[0].replayCount).toBe(1);
  await t.mutation(internal.community.publishReplay, { ...args, fingerprint: "two" });
  expect((await list()).levels[0].replayCount).toBe(2);
});

test("only replay owners can delete, and deletion updates counts once", async () => {
  const t = convexTest(schema, modules), level = await publish(t);
  const args = { owner, ...level, author: "Fox", code: fixture.proofCode, levelCode: fixture.code, duration: 200, won: true, fingerprint: "owned" };
  const replay = await t.mutation(internal.community.publishReplay, args);
  const mine = await t.query(internal.community.replays, { id: level.id, owner, cursor: null });
  const theirs = await t.query(internal.community.replays, { id: level.id, owner: stranger, cursor: null });
  expect(mine.replays[0].owned).toBe(true);
  expect(theirs.replays[0].owned).toBe(false);
  expect(mine.replays[0]).not.toHaveProperty("owner");
  await expect(t.mutation(internal.community.removeReplay, { id: replay.id, owner: stranger })).rejects.toThrow(/Only the author/);
  expect(await t.run(ctx => ctx.db.get(replay.id))).not.toBeNull();
  await t.mutation(internal.community.removeReplay, { id: replay.id, owner });
  await t.mutation(internal.community.removeReplay, { id: replay.id, owner });
  expect((await t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null })).levels[0].replayCount).toBe(0);
  expect(await t.run(ctx => ctx.db.get(level.id))).not.toBeNull();
});

test("deleting legacy replays leaves derived counts accurate", async () => {
  const t = convexTest(schema, modules), level = await publish(t);
  const replay = await t.mutation(internal.community.publishReplay, { owner, ...level, author: "Fox", code: fixture.proofCode, levelCode: fixture.code, duration: 200, won: true, fingerprint: "legacy" });
  await t.run(ctx => ctx.db.patch(level.id, { replayCount: undefined }));
  await t.mutation(internal.community.removeReplay, { id: replay.id, owner });
  expect((await t.query(internal.community.list, { owner, sort: "Hot", search: "", cursor: null })).levels[0].replayCount).toBe(0);
});

test("HTTP handles CORS and requires a real completion proof", async () => {
  const t = convexTest(schema, modules);
  const preflight = await t.fetch("/community", { method: "OPTIONS" });
  expect(preflight.status).toBe(204);
  expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe("*");
  const response = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "publish", token: owner, id: "", revision: 0, code: fixture.code, proof: "bad" }) });
  expect(response.status).toBe(400);
  expect(await t.run(ctx => ctx.db.query("levels").collect())).toHaveLength(0);
  const published = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "publish", token: owner, id: "", revision: 0, code: fixture.code, proof: fixture.proofCode }) });
  expect(published.status).toBe(200);
  const result = await published.json();
  expect(result.revision).toBe(1);
  const blocked = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "publish", token: owner, id: "", revision: 0, code: fixture.code, proof: fixture.proofCode }) });
  expect(blocked.status).toBe(429);
  const cooldown = await blocked.json();
  expect(cooldown.error).toBe("publish_cooldown");
  expect(cooldown.retryAfterMs).toBeGreaterThan(299_990);
  expect(cooldown.retryAfterMs).toBeLessThanOrEqual(300_000);
  const unfinished = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "publishReplay", token: owner, id: result.id, revision: 1, author: "Fox", code: unfinishedReplay() }) });
  expect(unfinished.status).toBe(400);
  expect(await t.run(ctx => ctx.db.query("replays").collect())).toHaveLength(0);
  const replay = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "publishReplay", token: owner, id: result.id, revision: 1, author: "Fox", code: fixture.proofCode }) });
  expect(replay.status).toBe(200);
  const replayId = (await replay.json()).id;
  const denied = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "deleteReplay", token: stranger, id: replayId }) });
  expect(denied.status).toBe(400);
  const deleted = await t.fetch("/community", { method: "POST", body: JSON.stringify({ action: "deleteReplay", token: owner, id: replayId }) });
  expect(deleted.status).toBe(200);
});
