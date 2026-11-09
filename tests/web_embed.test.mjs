import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const service = readFileSync(new URL('../scripts/community_service.gd', import.meta.url), 'utf8');
const cookieCalls = service.split('\n').filter(line => line.includes('JavaScriptBridge.eval(') && line.includes('document.cookie'));
const scripts = cookieCalls.map(line => {
  // Substitute the two GDScript interpolations before decoding its string literal.
  const substituted = line.replace('" + token + "', 'a'.repeat(64))
    .replace('" + JSON.stringify(ids) + "', '\\"[]\\"');
  const literal = substituted.slice(substituted.indexOf('eval(') + 5, substituted.lastIndexOf(')'));
  return JSON.parse(literal);
});

test('community startup and identity saves tolerate blocked iframe cookies', () => {
  assert.equal(scripts.length, 4);
  const document = {};
  Object.defineProperty(document, 'cookie', {
    get() { throw new DOMException('Cookies blocked in sandbox', 'SecurityError'); },
    set() { throw new DOMException('Cookies blocked in sandbox', 'SecurityError'); },
  });
  const context = vm.createContext({document});
  assert.equal(vm.runInContext(scripts[0], context), '');
  assert.equal(vm.runInContext(scripts[1], context), '[]');
  for (const script of scripts.slice(2)) assert.doesNotThrow(() => vm.runInContext(script, context));
});

test('available cookies preserve ownership, and malformed cookies fall back safely', () => {
  const token = 'b'.repeat(64);
  const context = vm.createContext({document: {cookie:`hearthline_owner=${token}; hearthline_levels=%5B%22level1%22%5D`}});
  assert.equal(vm.runInContext(scripts[0], context), token);
  assert.equal(vm.runInContext(scripts[1], context), '["level1"]');
  context.document.cookie = 'hearthline_levels=%broken';
  assert.equal(vm.runInContext(scripts[1], context), '[]');
});
