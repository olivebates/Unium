import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { createCipheriv, createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { decodeLevel, decodeReplay, canAppend, validateReplay } from "../convex/codec.ts";
import { hotScore } from "../convex/ranking.ts";

const generated = new URL("../.test-user/community-fixture.json", import.meta.url);
const fixture = JSON.parse(readFileSync(existsSync(generated) ? generated : new URL("./fixtures/community.json", import.meta.url)));
const key = createHash("sha256").update("Hearthline/community/portable-save/v1").digest();
function seal(raw, prefix) {
  const size = Buffer.alloc(4);
  size.writeUInt32LE(raw.length);
  const iv = Buffer.alloc(16, 7);
  const aes = createCipheriv("aes-256-cbc", key, iv);
  return prefix + Buffer.concat([iv, aes.update(Buffer.concat([size, gzipSync(raw)])), aes.final()]).toString("base64url");
}

test("Godot encrypted level and replay decode byte for byte in Node", () => {
  assert.deepEqual(decodeLevel(fixture.code), fixture.level);
  assert.deepEqual(decodeReplay(fixture.replayCode, 9), fixture.events);
});
test("proofs follow gameplay and must solve the actual puzzle", () => {
  const level = fixture.level;
  assert.equal(validateReplay(level, [[0, 0], [0, 1]]).won, true);
  assert.equal(validateReplay(level, [[0, 0]]).won, false);
  assert.throws(() => validateReplay(level, [[0, 0], [0, 8]]), /Illegal move/);
  assert.throws(() => validateReplay(level, [[0, -1]]), /Invalid undo/);
  assert.throws(() => validateReplay(level, [[0, 0], [0, 1], [0, 2]]), /after completion/);
  assert.deepEqual(validateReplay(level, [[0, 0], [5, -1], [0, 0], [10, 1]]).path, [0, 1]);
});
test("crossings require straight perpendicular paths and straight exits", () => {
  assert.equal(canAppend([3, 4, 5, 8, 7], 4, 3, 3), true);
  assert.equal(canAppend([3, 4, 5, 8, 7, 4], 1, 3, 3), true);
  assert.equal(canAppend([3, 4, 5, 8, 7, 4], 3, 3, 3), false);
  assert.equal(canAppend([0, 1, 4, 3], 0, 3, 3), true);
  assert.equal(canAppend([0, 1, 4, 3], 4, 3, 3), false);
  assert.equal(canAppend([], 1024, 32, 32), false);
});
test("malformed, oversized and corrupt data fail closed", () => {
  for (const code of ["", "HL1.abc", fixture.code.slice(0, -5), fixture.code + "!", "HL1." + "a".repeat(100001)]) assert.throws(() => decodeLevel(code));
  assert.throws(() => decodeLevel(seal(Buffer.from([1, 33, 1, 0, 0, 0, 0, 0, 0]), "HL1.")), /dimensions/);
  assert.throws(() => decodeReplay(seal(Buffer.from([1, 1, 0, 127]), "HR1."), 9), /Invalid input/);
});
test("Reddit hot includes logarithmic score, sign and creation time", () => {
  const epoch = 1134028003 * 1000;
  assert.equal(hotScore(0, 0, epoch), 0);
  assert.equal(hotScore(100, 0, epoch), 2);
  assert.equal(hotScore(0, 100, epoch), -2);
  assert.equal(hotScore(1, 0, epoch + 45000 * 1000), 1);
});
