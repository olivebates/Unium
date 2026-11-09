"use node";
import { createDecipheriv, createHash } from "node:crypto";
import { inflateSync, unzipSync } from "node:zlib";

const key = createHash("sha256").update("Hearthline/community/portable-save/v1").digest();
export const MAX_EVENTS = 20_000;
export type Level = { width: number; height: number; color: string; name: string; author: string; tiles: number[] };
export type Event = [number, number];

function unpack(code: string, prefix: string): Buffer {
  if (typeof code !== "string" || code.length > 100_000 || !code.startsWith(prefix) || !/^[A-Za-z0-9_-]+$/.test(code.slice(4))) throw new Error("Invalid save");
  const bytes = Buffer.from(code.slice(prefix.length), "base64url");
  if (bytes.length < 32 || bytes.length % 16) throw new Error("Invalid save");
  const aes = createDecipheriv("aes-256-cbc", key, bytes.subarray(0, 16));
  const payload = Buffer.concat([aes.update(bytes.subarray(16)), aes.final()]);
  if (payload.length < 5) throw new Error("Invalid save");
  const length = payload.readUInt32LE(0);
  if (!length || length > 1_048_576) throw new Error("Save too large");
  // Godot's DEFLATE mode uses the gzip wrapper (also accept zlib for tools).
  let raw: Buffer;
  try { raw = unzipSync(payload.subarray(4), { maxOutputLength: length }); }
  catch { raw = inflateSync(payload.subarray(4), { maxOutputLength: length }); }
  if (raw.length !== length) throw new Error("Invalid save length");
  return raw;
}

function reader(raw: Buffer, start: number) {
  let position = start;
  const uint = () => {
    let value = 0;
    for (let shift = 0; shift <= 28; shift += 7) {
      if (position >= raw.length) throw new Error("Truncated save");
      const byte = raw[position++];
      value += (byte & 127) * 2 ** shift;
      if (byte < 128) return value;
    }
    throw new Error("Invalid integer");
  };
  const text = (limit: number) => {
    const length = uint();
    if (length > limit || position + length > raw.length) throw new Error("Invalid text");
    const result = new TextDecoder("utf-8", { fatal: true }).decode(raw.subarray(position, position + length));
    position += length;
    return result;
  };
  return { uint, text, position: () => position };
}

export function decodeLevel(code: string): Level {
  const raw = unpack(code, "HL1.");
  if (raw.length < 9 || raw[0] !== 1) throw new Error("Invalid level");
  const width = raw[1], height = raw[2];
  if (width < 1 || width > 32 || height < 1 || height > 32) throw new Error("Invalid dimensions");
  const input = reader(raw, 6);
  const name = input.text(320).trim(), author = input.text(192).trim();
  if (!name || !author || [...name].length > 80 || [...author].length > 48 || /[\x00-\x1f\x7f]/.test(name + author)) throw new Error("Invalid name or author");
  if (input.position() + Math.ceil(width * height / 4) !== raw.length) throw new Error("Invalid tiles");
  const tiles = Array.from({ length: width * height }, (_, cell) => (raw[input.position() + Math.floor(cell / 4)] >> ((cell % 4) * 2)) & 3);
  if (tiles.includes(3) || !tiles.includes(1)) throw new Error("Invalid tiles");
  return { width, height, name, author, color: raw.subarray(3, 6).toString("hex"), tiles };
}

export function decodeReplay(code: string, area: number): Event[] {
  const raw = unpack(code, "HR1.");
  if (raw[0] !== 1) throw new Error("Invalid replay");
  const input = reader(raw, 1), count = input.uint();
  if (!count || count > MAX_EVENTS) throw new Error("Replay too long");
  const events: Event[] = [];
  for (let i = 0; i < count; i++) {
    const delay = input.uint(), cell = input.uint() - 2;
    if (delay > 5000 || cell < -2 || cell >= area) throw new Error("Invalid input");
    events.push([delay, cell]);
  }
  if (input.position() !== raw.length) throw new Error("Invalid replay length");
  return events;
}

export function canAppend(path: number[], cell: number, width: number, height: number): boolean {
  if (!Number.isInteger(cell) || cell < 0 || cell >= width * height) return false;
  if (!path.length) return true;
  const end = path.at(-1)!;
  const vector = (from: number, to: number) => [to % width - from % width, Math.floor(to / width) - Math.floor(from / width)];
  const direction = vector(end, cell);
  if (Math.abs(direction[0]) + Math.abs(direction[1]) !== 1) return false;
  const count = (target: number) => path.reduce((sum, value) => sum + Number(value === target), 0);
  const equal = (a: number[], b: number[]) => a[0] === b[0] && a[1] === b[1];
  if (count(end) === 2 && !equal(vector(path.at(-2)!, end), direction)) return false;
  const visits = count(cell);
  if (!visits) return true;
  if (visits >= 2) return false;
  const index = path.indexOf(cell);
  if (index === path.length - 1) return false;
  const outgoing = vector(cell, path[index + 1]);
  if (outgoing[0] * direction[0] + outgoing[1] * direction[1] !== 0) return false;
  return index === 0 || equal(vector(path[index - 1], cell), outgoing);
}

export function validateReplay(level: Level, events: Event[]) {
  const path: number[] = [];
  const tiles = [...level.tiles];
  const flip = (cell: number) => { if (tiles[cell] !== 2) tiles[cell] = 1 - tiles[cell]; };
  let won = false, duration = 0;
  for (const [delay, cell] of events) {
    if (won) throw new Error("Input after completion");
    duration += delay;
    if (cell === -2) {
      while (path.length) flip(path.pop()!);
    } else if (cell === -1) {
      if (!path.length) throw new Error("Invalid undo");
      flip(path.pop()!);
    } else {
      if (!canAppend(path, cell, level.width, level.height)) throw new Error("Illegal move");
      path.push(cell);
      flip(cell);
    }
    won = path.length >= 2 && !tiles.includes(1);
  }
  return { won, duration, path };
}
