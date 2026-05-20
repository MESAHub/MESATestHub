// MESA Test Hub — mock data
// Fictional commits/computers/tests modeling a real test hub, including
// build-pass-but-flagged states (FPE, checksum mismatch) and partial-build
// (compile ok on some computers, fail on others), plus per-test multi-instance
// runs with the numerical columns the existing test-on-commit page exposes.

const COMPUTERS = [
  { id: 'rusty',    owner: 'Matteo Cantiello',  os: 'linux',  sdk: 'Rocky x86_64-linux 26.3.2 CRMATH',  fast: true  },
  { id: 'popeye',   owner: 'Robert Farmer',     os: 'linux',  sdk: 'CentOS x86_64-linux 26.3.2',         fast: true  },
  { id: 'derecho',  owner: 'Adam Jermyn',       os: 'linux',  sdk: 'RHEL x86_64-linux 26.3.2 ifx',       fast: false },
  { id: 'frontera', owner: 'Bill Wolf',         os: 'linux',  sdk: 'Rocky x86_64-linux 26.3.2',          fast: true  },
  { id: 'ranger',   owner: 'Earl Bellinger',    os: 'macos',  sdk: 'macOS arm64 26.3.2 CRMATH',          fast: false },
  { id: 'expanse',  owner: 'Ebraheem Farag',    os: 'linux',  sdk: 'Rocky x86_64-linux 26.3.2 ifx',      fast: true  },
];

const TEST_MODULES = [
  { id: 'star', name: 'star', count: 47 },
  { id: 'binary', name: 'binary', count: 18 },
  { id: 'eos', name: 'eos', count: 12 },
  { id: 'kap', name: 'kap', count: 9 },
  { id: 'net', name: 'net', count: 11 },
  { id: 'rates', name: 'rates', count: 4 },
  { id: 'astero', name: 'astero', count: 5 },
];

const TESTS = [
  { id: '20M_z2m2_high_rotation',   module: 'star',  weight: 'heavy', topic: 'rotation' },
  { id: '7M_prems_to_AGB',          module: 'star',  weight: 'heavy', topic: 'massive stars' },
  { id: 'wd_he_shell_flash',        module: 'star',  weight: 'heavy', topic: 'white dwarfs' },
  { id: 'irradiated_planet',        module: 'binary',weight: 'med',   topic: 'binary' },
  { id: 'pisn',                     module: 'star',  weight: 'heavy', topic: 'pair-instability' },
  { id: '1.5M_with_diffusion',      module: 'star',  weight: 'med',   topic: 'diffusion' },
  { id: 'eos_blend_to_PT',          module: 'eos',   weight: 'light', topic: 'EOS' },
  { id: 'kap_freedman_pure_tables', module: 'kap',   weight: 'light', topic: 'opacities' },
  { id: 'simple_basic_net',         module: 'net',   weight: 'light', topic: 'nuclear net' },
  { id: 'wd_aic_ignition',          module: 'star',  weight: 'heavy', topic: 'white dwarfs' },
];

// Per-commit scenarios drive both the matrix and the commit-level state.
//   builds:    which computers built (default: all built)
//   fails:     [{test, computer}]               — hard test failures
//   pending:   [{test, computer}]               — not yet reported
//   skips:     [{test, computer}]               — skipped tests
//   flags:     [{test, computer, kind}]         — pass-with-issue
//              kind ∈ 'fpe' | 'checksum' | 'inlists_full'
const COMMIT_SCENARIOS = {
  'aa27a08': { /* all clean */ },

  '7c4e2d1': {
    fails: [
      { test: 'eos_blend_to_PT', computer: 'derecho' },
      { test: 'eos_blend_to_PT', computer: 'ranger' },
      { test: 'kap_freedman_pure_tables', computer: 'derecho' },
      { test: 'pisn', computer: 'expanse' },
    ],
    flags: [
      { test: '1.5M_with_diffusion', computer: 'rusty', kind: 'inlists_full' },
      { test: 'rotating_massive_star', computer: 'popeye', kind: 'inlists_full' },
    ],
  },

  'b81f9a3': {
    fails: [{ test: '1.5M_with_diffusion', computer: 'ranger' }],
    flags: [
      { test: 'pisn', computer: 'derecho', kind: 'fpe' },
      { test: 'wd_aic_ignition', computer: 'rusty', kind: 'inlists_full' },
    ],
  },

  // In-progress commit: some computers still running. Used to demo "pending".
  '3d28c10': {
    pending: [
      { test: 'pisn', computer: 'ranger' },
      { test: '7M_prems_to_AGB', computer: 'ranger' },
      { test: 'wd_he_shell_flash', computer: 'ranger' },
      { test: 'wd_aic_ignition', computer: 'ranger' },
    ],
    flags: [
      { test: 'pisn', computer: 'derecho', kind: 'fpe' },
      { test: '7M_prems_to_AGB', computer: 'rusty', kind: 'inlists_full' },
    ],
  },

  // Mixed test outcomes (same test passes some, fails on others) on a single test
  'e91a5c2': {
    builds: { rusty: 'ok', popeye: 'ok', derecho: 'fail', frontera: 'ok', ranger: 'fail', expanse: 'fail' },
    fails: [
      { test: '1.5M_with_diffusion', computer: 'rusty' },
      { test: '1.5M_with_diffusion', computer: 'popeye' },
    ],
  },

  // Pass with checksum mismatch — bit-for-bit reproducibility issue
  '2f74b08': {
    flags: [
      { test: 'eos_blend_to_PT', computer: 'derecho', kind: 'checksum' },
      { test: 'eos_blend_to_PT', computer: 'expanse', kind: 'checksum' },
      { test: '1.5M_with_diffusion', computer: 'ranger', kind: 'checksum' },
    ],
  },

  '9a13fde': { /* clean */ },

  // Partial-build + uniform failures + mixed
  'c5e8a01': {
    builds: { rusty: 'ok', popeye: 'ok', derecho: 'ok', frontera: 'fail', ranger: 'ok', expanse: 'ok' },
    fails: [
      // Mixed: same test fails on some, passes on others
      { test: '1.5M_with_diffusion', computer: 'popeye' },
      { test: '1.5M_with_diffusion', computer: 'derecho' },
      // Uniform: fails everywhere that ran it
      { test: 'rotating_massive_star', computer: 'rusty' },
      { test: 'rotating_massive_star', computer: 'popeye' },
      { test: 'rotating_massive_star', computer: 'derecho' },
      { test: 'rotating_massive_star', computer: 'ranger' },
      { test: 'rotating_massive_star', computer: 'expanse' },
    ],
    flags: [
      { test: 'pisn', computer: 'rusty', kind: 'fpe' },
    ],
  },

  '6b41a9d': { /* clean */ },
  'f0d2e87': { /* clean */ },

  '4a92ce0': {
    fails: [{ test: '7M_prems_to_AGB', computer: 'ranger' }],
    flags: [{ test: 'wd_aic_ignition', computer: 'popeye', kind: 'inlists_full' }],
  },

  '8e7c1b3': {
    flags: [
      { test: 'rotating_massive_star', computer: 'derecho', kind: 'inlists_full' },
      { test: 'rotating_massive_star', computer: 'expanse', kind: 'inlists_full' },
    ],
  },

  // Total build fail
  'd1f8a92': {
    builds: { rusty: 'fail', popeye: 'fail', derecho: 'fail', frontera: 'fail', ranger: 'fail', expanse: 'fail' },
  },

  '5c0b8e3': { /* clean — old */ },
  '03ae51d': { /* clean — old */ },
  'a7cd221': {
    fails: [{ test: 'eos_blend_to_PT', computer: 'ranger' }],
  },
};

// Base commit list. Now spans more dates so age-grouping is meaningful.
// Reference "now" is 2026-05-19T20:30:00Z.
const COMMITS = [
  // Today (19 May)
  { sha: 'aa27a08', full: 'aa27a0870fd1c1e634f0bfc24cc79325f61e07d6',
    msg: 'Revert "Minor Bugfix in Plasmon Neutrino Cooling Rates" (#1002)',
    author: 'Ebraheem Farag', authorHandle: 'efarag', avatar: '#7c3aed',
    branch: 'main', whenISO: '2026-05-19T19:27:00Z',
    pr: 1002, files: 3, diff: '+12 −47' },
  { sha: '7c4e2d1', full: '7c4e2d1b88419f73a5e7a2cd9c0a6c2f3e1d4b07',
    msg: 'Update EOS interpolation tables for low-T helium burning (#1001)',
    author: 'Adam Jermyn', authorHandle: 'adamjermyn', avatar: '#0891b2',
    branch: 'main', whenISO: '2026-05-19T14:02:00Z',
    pr: 1001, files: 11, diff: '+428 −317' },
  // Yesterday (18 May)
  { sha: 'b81f9a3', full: 'b81f9a3e9c2b5d18f0a4e7c1b6d2a8c9f3e0d5b7',
    msg: 'Fix MLT++ regime transition at log Teff < 3.6 (#999)',
    author: 'Matteo Cantiello', authorHandle: 'mcantiello', avatar: '#dc2626',
    branch: 'main', whenISO: '2026-05-18T22:11:00Z',
    pr: 999, files: 5, diff: '+88 −62' },
  { sha: '3d28c10', full: '3d28c10a5b6f9e1d0c2b3a4d5e6f7a8b9c0d1e2f',
    msg: 'Add neutrino bremsstrahlung rates from Hannestad+Raffelt',
    author: 'Bill Paxton', authorHandle: 'billpaxton', avatar: '#16a34a',
    branch: 'main', whenISO: '2026-05-18T09:45:00Z',
    pr: null, files: 2, diff: '+147 −3' },
  // This week (Mon 13 → Sun 19)
  { sha: 'e91a5c2', full: 'e91a5c2d8b3a7e9f0c1d2e3f4a5b6c7d8e9f0a1b',
    msg: 'WIP: refactor opacity caching (do not merge)',
    author: 'Earl Bellinger', authorHandle: 'earlbellinger', avatar: '#ea580c',
    branch: 'main', whenISO: '2026-05-17T16:33:00Z',
    pr: null, files: 23, diff: '+612 −482' },
  { sha: '2f74b08', full: '2f74b08c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60',
    msg: 'Bump ifx tested version to 2025.2',
    author: 'Robert Farmer', authorHandle: 'robfarmer', avatar: '#0ea5e9',
    branch: 'main', whenISO: '2026-05-17T11:08:00Z',
    pr: 996, files: 1, diff: '+2 −2' },
  { sha: '9a13fde', full: '9a13fded4c5b6e7f8091a2b3c4d5e6f7a8b9c0d1',
    msg: 'Clean up unused fortran subroutines in star/private',
    author: 'Bill Wolf', authorHandle: 'billwolf', avatar: '#9333ea',
    branch: 'main', whenISO: '2026-05-16T20:14:00Z',
    pr: 993, files: 17, diff: '+0 −2,304' },
  { sha: 'c5e8a01', full: 'c5e8a01f2e3d4c5b6a7980f1e2d3c4b5a6978f0e',
    msg: 'Tune defaults for massive star convective boundary mixing',
    author: 'Matteo Cantiello', authorHandle: 'mcantiello', avatar: '#dc2626',
    branch: 'main', whenISO: '2026-05-15T14:45:00Z',
    pr: 991, files: 6, diff: '+74 −58' },
  { sha: '6b41a9d', full: '6b41a9d8e7f6c5b4a3920f1e2d3c4b5a69788e7f',
    msg: 'Docs: add chapter on rotating models',
    author: 'Adam Jermyn', authorHandle: 'adamjermyn', avatar: '#0891b2',
    branch: 'main', whenISO: '2026-05-15T09:00:00Z',
    pr: 990, files: 4, diff: '+912 −12' },
  { sha: 'f0d2e87', full: 'f0d2e8765b4a3920f1e2d3c4b5a69788e7f6c5b4',
    msg: 'Merge pull request #988 from rate-fixes',
    author: 'Ebraheem Farag', authorHandle: 'efarag', avatar: '#7c3aed',
    branch: 'main', whenISO: '2026-05-14T23:18:00Z',
    pr: 988, files: 8, diff: '+201 −44' },
  { sha: '4a92ce0', full: '4a92ce0d3c4b5a69788e7f6c5b4a3920f1e2d3c4',
    msg: 'Add test case for super-Eddington outflows',
    author: 'Bill Wolf', authorHandle: 'billwolf', avatar: '#9333ea',
    branch: 'main', whenISO: '2026-05-14T17:55:00Z',
    pr: null, files: 9, diff: '+318 −0' },
  // Last week (6 May → 12 May)
  { sha: '8e7c1b3', full: '8e7c1b3f6c5b4a3920f1e2d3c4b5a69788e7f6c5',
    msg: 'Increase nuclear network tolerance for stiff regimes',
    author: 'Earl Bellinger', authorHandle: 'earlbellinger', avatar: '#ea580c',
    branch: 'main', whenISO: '2026-05-12T10:24:00Z',
    pr: 987, files: 2, diff: '+18 −9' },
  { sha: 'd1f8a92', full: 'd1f8a924e7b6c5d4a3920f1e2d3c4b5a69788e7f',
    msg: 'WIP: experimental atomic line opacity tables',
    author: 'Adam Jermyn', authorHandle: 'adamjermyn', avatar: '#0891b2',
    branch: 'main', whenISO: '2026-05-09T15:42:00Z',
    pr: null, files: 41, diff: '+1,820 −33' },
  // This month (~14-30 days)
  { sha: '5c0b8e3', full: '5c0b8e3a4d2f1c5b6e7980a1b2c3d4e5f6789a0b',
    msg: 'Switch automated tests to ifx by default',
    author: 'Robert Farmer', authorHandle: 'robfarmer', avatar: '#0ea5e9',
    branch: 'main', whenISO: '2026-05-04T08:12:00Z',
    pr: 982, files: 3, diff: '+12 −12' },
  { sha: '03ae51d', full: '03ae51d8e7f6c5b4a3920f1e2d3c4b5a69788e7f',
    msg: 'Refactor: split star_data into per-module headers',
    author: 'Bill Paxton', authorHandle: 'billpaxton', avatar: '#16a34a',
    branch: 'main', whenISO: '2026-04-29T16:00:00Z',
    pr: 978, files: 92, diff: '+3,124 −2,890' },
  // Older
  { sha: 'a7cd221', full: 'a7cd2218e7f6c5b4a3920f1e2d3c4b5a69788e7f',
    msg: 'Tag release r25.04',
    author: 'Ebraheem Farag', authorHandle: 'efarag', avatar: '#7c3aed',
    branch: 'main', whenISO: '2026-04-12T18:30:00Z',
    pr: null, files: 1, diff: '+1 −1' },
];

const BRANCHES = [
  { name: 'main', commits: 412, current: true, lastCommitISO: '2026-05-19T19:27:00Z' },
  { name: 'develop', commits: 437, lastCommitISO: '2026-05-19T20:01:00Z' },
  { name: 'release/r24.05', commits: 28, lastCommitISO: '2026-04-12T18:30:00Z' },
  { name: 'feature/eos-update', commits: 6, lastCommitISO: '2026-05-18T11:00:00Z' },
  { name: 'feature/rotation-rework', commits: 14, lastCommitISO: '2026-05-15T14:45:00Z' },
  { name: 'fix/mlt-boundary', commits: 3, lastCommitISO: '2026-05-19T08:00:00Z' },
];

// =============================================================================
// Derived helpers
// =============================================================================

function getBuilds(sha) {
  const scenario = COMMIT_SCENARIOS[sha] || {};
  if (scenario.builds) return scenario.builds;
  const out = {};
  COMPUTERS.forEach(c => { out[c.id] = 'ok'; });
  return out;
}

// Returns { [testId]: { [compId]: { status, flags } } }
//   status ∈ 'pass' | 'fail' | 'skip' | 'pending' | 'no-build'
function getMatrixForCommit(sha) {
  const scenario = COMMIT_SCENARIOS[sha] || {};
  const builds = getBuilds(sha);
  const out = {};
  TESTS.forEach(t => {
    out[t.id] = {};
    COMPUTERS.forEach(c => {
      out[t.id][c.id] = {
        status: builds[c.id] === 'fail' ? 'no-build' : 'pass',
        flags: { fpe: false, checksum: false, inlists_full: false },
      };
    });
  });
  (scenario.fails || []).forEach(f => {
    if (out[f.test]?.[f.computer]) out[f.test][f.computer].status = 'fail';
  });
  (scenario.pending || []).forEach(f => {
    if (out[f.test]?.[f.computer]) out[f.test][f.computer].status = 'pending';
  });
  (scenario.skips || []).forEach(f => {
    if (out[f.test]?.[f.computer]) out[f.test][f.computer].status = 'skip';
  });
  (scenario.flags || []).forEach(f => {
    if (out[f.test]?.[f.computer]) out[f.test][f.computer].flags[f.kind] = true;
  });
  return out;
}

// =============================================================================
// Two-dimensional commit state: independent build + test summaries.
//   build:  { status, builtComputers, failedBuildComputers }
//   tests:  { status, uniformFailingTests, mixedTests, pendingTests, passingTests,
//             failingCellsCount, hasPending, hasMixed, hasUniformFail,
//             failingCells, mixedCells }
//   flags:  { fpe, checksum, inlistsFull }
// "status" in build is one of: 'all-ok' | 'some-fail' | 'all-fail'
// "status" in tests is the WORST of: 'fail' | 'mixed' | 'pending' | 'all-pass' | 'not-run'
//   plus the boolean flags so the UI can show multiple things at once.
// =============================================================================
function getCommitState(sha) {
  const builds = getBuilds(sha);
  const matrix = getMatrixForCommit(sha);
  const builtComputers = COMPUTERS.filter(c => builds[c.id] === 'ok').map(c => c.id);
  const failedBuildComputers = COMPUTERS.filter(c => builds[c.id] === 'fail').map(c => c.id);

  const buildStatus =
    failedBuildComputers.length === COMPUTERS.length ? 'all-fail' :
    failedBuildComputers.length > 0 ? 'some-fail' :
    'all-ok';

  // Per-test aggregation across computers that built.
  let uniformFailingTests = 0; // failed on every built computer that reported
  let mixedTests = 0;           // pass on some, fail on others
  let pendingTests = 0;         // at least one pending result on a built computer
  let passingTests = 0;         // ran on all built computers and all passed

  const failingCells = [];
  const mixedCells = [];

  TESTS.forEach(t => {
    const cells = builtComputers.map(id => ({ id, ...(matrix[t.id]?.[id] || {}) }));
    const pendings = cells.filter(c => c.status === 'pending');
    const ran = cells.filter(c => c.status === 'pass' || c.status === 'fail');
    const fails = cells.filter(c => c.status === 'fail');
    const passes = cells.filter(c => c.status === 'pass');

    if (pendings.length > 0) {
      pendingTests++;
    }
    if (fails.length > 0 && passes.length > 0) {
      mixedTests++;
      fails.forEach(c => mixedCells.push({
        test: t, computer: COMPUTERS.find(x => x.id === c.id),
      }));
    } else if (fails.length === ran.length && fails.length > 0) {
      uniformFailingTests++;
      fails.forEach(c => failingCells.push({
        test: t, computer: COMPUTERS.find(x => x.id === c.id),
      }));
    } else if (passes.length === ran.length && ran.length > 0 && pendings.length === 0) {
      passingTests++;
    }
  });

  const failingCellsCount = failingCells.length;
  const mixedCellsCount = mixedCells.length;

  const hasUniformFail = uniformFailingTests > 0;
  const hasMixed = mixedTests > 0;
  const hasPending = pendingTests > 0;

  // Single-token test-status for sparkline / dot summary, worst-first:
  let testStatus;
  if (builtComputers.length === 0)        testStatus = 'not-run';
  else if (hasUniformFail)                testStatus = 'fail';
  else if (hasMixed)                      testStatus = 'mixed';
  else if (hasPending && passingTests === 0) testStatus = 'pending';
  else if (hasPending)                    testStatus = 'pending-partial';
  else                                    testStatus = 'all-pass';

  // Flags across all cells
  let fpe = 0, checksum = 0, inlistsFull = 0;
  const flaggedCells = [];
  TESTS.forEach(t => COMPUTERS.forEach(c => {
    const cell = matrix[t.id]?.[c.id];
    if (!cell) return;
    if (cell.flags.fpe)          { fpe++;          flaggedCells.push({ test: t, computer: c, kind: 'fpe' }); }
    if (cell.flags.checksum)     { checksum++;     flaggedCells.push({ test: t, computer: c, kind: 'checksum' }); }
    if (cell.flags.inlists_full) { inlistsFull++;  flaggedCells.push({ test: t, computer: c, kind: 'inlists_full' }); }
  }));

  return {
    build: {
      status: buildStatus,
      builtComputers, failedBuildComputers,
    },
    tests: {
      status: testStatus,
      uniformFailingTests, mixedTests, pendingTests, passingTests,
      failingCellsCount, mixedCellsCount,
      hasUniformFail, hasMixed, hasPending,
      failingCells, mixedCells,
    },
    flags: { fpe, checksum, inlistsFull, flaggedCells },

    // Convenience flat counts for badges
    fail: failingCellsCount,
    mixed: mixedCellsCount,
    pending: pendingTests,
    fpeCount: fpe, checksumCount: checksum, inlistsFullCount: inlistsFull,
    builtComputers, failedBuildComputers,
    failingCells, flaggedCells, mixedCells,
  };
}

// =============================================================================
// Per-instance numerical data for the test-on-commit page.
// In real life MESA tests can have multiple "instances" per (commit, test,
// computer) — most commonly a base run + a photo-restart run, possibly across
// different inlists and thread counts. We model that here.
// =============================================================================

function _seed(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return () => { h ^= h << 13; h ^= h >>> 17; h ^= h << 5; return ((h >>> 0) % 10000) / 10000; };
}

const _INSTANCE_KINDS = [
  { variant: 'run',   label: 'PASS: Photo Checksum',      mark: 'out' },
  { variant: 'photo', label: 'PASS: Photo Checksum',      mark: 'mk',  hasFullInlist: true },
];

function getInstancesForTestOnCommit(sha, testId) {
  const matrix = getMatrixForCommit(sha);
  const out = [];
  COMPUTERS.forEach(comp => {
    const cell = matrix[testId]?.[comp.id];
    if (!cell || cell.status === 'no-build') return;
    const rnd = _seed(sha + testId + comp.id);
    const baseRuntime = 12 + rnd() * 16; // 12-28 min
    const baseSteps = 2400 + Math.floor(rnd() * 600);
    const baseModel = baseSteps + 12 + Math.floor(rnd() * 50);
    const baseAge = 1.2e7 + rnd() * 4e6;
    _INSTANCE_KINDS.forEach((kind, ki) => {
      const isPhoto = kind.variant === 'photo';
      const rt = baseRuntime + (isPhoto ? rnd() * 0.5 : 0);
      const checksumOk = cell.status === 'pass' && !cell.flags.checksum;
      const baseSum = '6bd9a47';
      const altSum  = '8b1cd93';
      const sum = (cell.flags.checksum && !isPhoto) ? altSum
        : (cell.flags.checksum && isPhoto && comp.id !== 'derecho') ? baseSum
        : baseSum;
      out.push({
        id: `${sha}-${testId}-${comp.id}-${kind.variant}`,
        computerId: comp.id, computerOs: comp.os,
        variant: kind.variant, label: kind.label, mark: kind.mark,
        status: cell.status,                      // 'pass'|'fail'|'pending'|'skip'
        statusLabel: cell.status === 'fail' ? 'FAIL'
          : cell.status === 'pending' ? 'PENDING'
          : cell.status === 'skip' ? 'SKIP'
          : 'PASS: Photo Checksum',
        flags: { ...cell.flags, inlists_full: cell.flags.inlists_full || (kind.hasFullInlist && (comp.id === 'rusty' || comp.id === 'popeye')) },

        // Numerical columns
        runtime: +rt.toFixed(2),                  // minutes
        ram: +(900 + rnd() * 800).toFixed(0),     // MB
        threads: comp.os === 'macos' ? 8 : 16,
        spec: comp.os === 'macos' ? 'arm64' : 'x86_64',
        checksum: sum,
        modelNumber: baseModel + (isPhoto ? -2 : 0),
        steps: baseSteps + (isPhoto ? -2 : 0),
        cumRetries: 200 + Math.floor(rnd() * 200),
        retries: 0 + Math.floor(rnd() * 12),
        redos: Math.floor(rnd() * 8),
        solverIters: 30000 + Math.floor(rnd() * 15000),
        solverCallsMade: 4500 + Math.floor(rnd() * 1500),
        solverCallsFailed: cell.status === 'fail' ? 800 + Math.floor(rnd() * 400) : 250 + Math.floor(rnd() * 100),
        logRelE: -(8 + rnd() * 3).toFixed(2),
        starAge: +(baseAge + (isPhoto ? rnd() * 1e3 : 0)).toExponential(3),
        numRetries: 0 + Math.floor(rnd() * 5),
        inlistRetries: 250 + Math.floor(rnd() * 100),
        date: '19 May 19:58',
      });
    });
  });
  return out;
}

// =============================================================================
// Helpers
// =============================================================================
function shortSha(s) { return s.slice(0, 7); }
const NOW_ISO = '2026-05-19T20:30:00Z';
function relTime(iso) {
  const t = new Date(iso).getTime();
  const now = new Date(NOW_ISO).getTime();
  const d = Math.max(0, (now - t) / 1000);
  if (d < 60) return 'just now';
  if (d < 3600) return Math.floor(d/60) + 'm ago';
  if (d < 86400) return Math.floor(d/3600) + 'h ago';
  return Math.floor(d/86400) + 'd ago';
}

// Group commits into age buckets relative to NOW_ISO.
// Buckets (in order): Today, Yesterday, This week, Last week, This month, Older.
function ageBucket(iso) {
  const now = new Date(NOW_ISO);
  const t = new Date(iso);
  const startOfDay = (d) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const today = startOfDay(now);
  const tDay  = startOfDay(t);
  const dayDiff = Math.round((today - tDay) / 86400000);
  if (dayDiff <= 0) return 'today';
  if (dayDiff === 1) return 'yesterday';
  // ISO weeks (Mon → Sun). Day of week of "today" with Monday=0.
  const dow = (today.getUTCDay() + 6) % 7;
  const startOfThisWeek = new Date(today.getTime() - dow * 86400000);
  const startOfLastWeek = new Date(startOfThisWeek.getTime() - 7 * 86400000);
  if (tDay >= startOfThisWeek) return 'this-week';
  if (tDay >= startOfLastWeek) return 'last-week';
  // This month: same calendar month-year
  if (t.getUTCFullYear() === now.getUTCFullYear() && t.getUTCMonth() === now.getUTCMonth()) return 'this-month';
  return 'older';
}

const AGE_BUCKETS = [
  { id: 'today',      label: 'Today' },
  { id: 'yesterday',  label: 'Yesterday' },
  { id: 'this-week',  label: 'Earlier this week' },
  { id: 'last-week',  label: 'Last week' },
  { id: 'this-month', label: 'Earlier this month' },
  { id: 'older',      label: 'Older' },
];

function groupCommitsByAge(commits) {
  const byBucket = {};
  AGE_BUCKETS.forEach(b => byBucket[b.id] = []);
  commits.forEach(c => byBucket[ageBucket(c.whenISO)].push(c));
  return AGE_BUCKETS
    .filter(b => byBucket[b.id].length > 0)
    .map(b => ({ ...b, commits: byBucket[b.id] }));
}

Object.assign(window, {
  COMPUTERS, COMMITS, BRANCHES, TEST_MODULES, TESTS, COMMIT_SCENARIOS,
  getMatrixForCommit, getCommitState, getBuilds, getInstancesForTestOnCommit,
  shortSha, relTime, ageBucket, AGE_BUCKETS, groupCommitsByAge,
});
