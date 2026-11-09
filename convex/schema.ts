import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  levels: defineTable({
    name: v.string(), author: v.string(), code: v.string(), owner: v.string(),
    revision: v.number(), created: v.number(), updated: v.number(),
    up: v.number(), down: v.number(), score: v.number(), hot: v.number(),
    replayCount: v.optional(v.number()),
  }).index("by_owner", ["owner"])
    .index("by_hot", ["hot"])
    .index("by_score", ["score"])
    .index("by_created", ["created"]),
  votes: defineTable({
    level: v.id("levels"), revision: v.number(), voter: v.string(), value: v.number(),
  }).index("by_level", ["level"])
    .index("by_level_revision", ["level", "revision"])
    .index("by_voter_level", ["voter", "level", "revision"]),
  replays: defineTable({
    level: v.id("levels"), revision: v.number(), author: v.string(), owner: v.string(),
    code: v.string(), levelCode: v.string(), duration: v.number(), won: v.boolean(),
    fingerprint: v.string(),
  }).index("by_level", ["level"])
    .index("by_level_revision", ["level", "revision"])
    .index("by_owner_fingerprint", ["owner", "fingerprint"]),
  limits: defineTable({
    owner: v.string(), bucket: v.string(), start: v.number(), count: v.number(),
  }).index("by_owner_bucket", ["owner", "bucket"]),
});
