// Local-only Jest config wrapper used by `jest-fast`. Not committed to any project repo; CI is unchanged.
// Loads the project's own jest config (JEST_FAST_BASE, absolute path) and switches ts-jest to transpile-only
// (isolatedModules) — ts-jest's default mode builds a type checker per suite (measured ~5 s per suite on a mid-size service).
// Type errors are still caught by the separate tsc step and by CI. Everything else in the config stays as is.
const path = require('path');
const base = process.env.JEST_FAST_BASE;
if (!base || !path.isAbsolute(base)) throw new Error('jest-fast: set JEST_FAST_BASE to the absolute path of the jest config');
if (/\.ts$/.test(base)) {
  require(require.resolve('ts-node', { paths: [path.dirname(base)] }))
    .register({ transpileOnly: true, compilerOptions: { module: 'commonjs' } });
}
const fast = (v) => {
  if (v === 'ts-jest') return ['ts-jest', { isolatedModules: true }];
  if (Array.isArray(v) && v[0] === 'ts-jest') return ['ts-jest', { ...(v[1] || {}), isolatedModules: true }];
  return v;
};
const patch = (cfg) => {
  cfg = { ...cfg };
  cfg.rootDir = path.resolve(path.dirname(base), cfg.rootDir || '.');
  if (cfg.transform) cfg.transform = Object.fromEntries(Object.entries(cfg.transform).map(([k, v]) => [k, fast(v)]));
  else if (cfg.preset === 'ts-jest') cfg.transform = { '^.+\\.tsx?$': ['ts-jest', { isolatedModules: true }] };
  if (cfg.globals && cfg.globals['ts-jest']) cfg.globals = { ...cfg.globals, 'ts-jest': { ...cfg.globals['ts-jest'], isolatedModules: true } };
  return cfg;
};
let mod = require(base);
mod = mod && mod.__esModule ? mod.default : mod.default || mod;
module.exports = typeof mod === 'function' ? async () => patch(await mod()) : patch(mod);
