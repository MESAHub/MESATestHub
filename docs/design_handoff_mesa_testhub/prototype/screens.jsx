// MESA Test Hub — screens
// CommitsList, CommitDetail, TestOnCommit

const { useState: useStateS, useEffect: useEffectS, useMemo: useMemoS, useRef: useRefS } = React;

// ============================================================================
// BranchPicker — prominent inline picker used as a chip in page headlines
// ============================================================================
function BranchPicker({ branch, onChange, size = 'lg' }) {
  const isLg = size === 'lg';
  return (
    <Dropdown align="left" trigger={
      <button style={{
        display: 'inline-flex', alignItems: 'center', gap: 8,
        padding: isLg ? '6px 12px' : '4px 9px',
        background: 'var(--brand-soft)', color: 'var(--brand-soft-text)',
        border: '1px solid transparent',
        borderRadius: 8, fontWeight: 600,
        fontSize: isLg ? 18 : 13, letterSpacing: isLg ? -0.2 : 0,
        cursor: 'pointer', fontFamily: 'var(--font-mono)',
      }}
      onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--brand)'; }}
      onMouseLeave={e => { e.currentTarget.style.borderColor = 'transparent'; }}>
        <Icon name="branch" size={isLg ? 16 : 12}/>
        {branch}
        <Icon name="chevron" size={isLg ? 14 : 11}/>
      </button>
    }>
      <div style={{ padding: '6px 10px 4px', fontSize: 11, color: 'var(--fg-subtle)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
        Switch branch
      </div>
      {BRANCHES.map(b => (
        <DropdownItem key={b.name} active={b.name === branch} onClick={() => onChange(b.name)}>
          <Icon name="branch" size={12}/>
          <span className="mono">{b.name}</span>
          <span style={{ marginLeft: 'auto', color: 'var(--fg-subtle)', fontSize: 11 }}>{b.commits}</span>
        </DropdownItem>
      ))}
    </Dropdown>
  );
}

// ============================================================================
// CommitsList — entry page (grouped by age)
// ============================================================================
function CommitsList({ commits, branch, onChangeBranch, onOpen }) {
  const [search, setSearch] = useStateS('');
  const [filter, setFilter] = useStateS('all'); // all|fail|mixed|build|pending|clean
  const commitsWithState = useMemoS(() =>
    commits.map(c => ({ c, s: getCommitState(c.sha) })),
    [commits]);

  const filtered = commitsWithState.filter(({ c, s }) => {
    if (search && !c.msg.toLowerCase().includes(search.toLowerCase()) &&
        !c.sha.includes(search) && !c.author.toLowerCase().includes(search.toLowerCase())) return false;
    if (filter === 'fail'    && !s.tests.hasUniformFail) return false;
    if (filter === 'mixed'   && !s.tests.hasMixed) return false;
    if (filter === 'build'   && s.build.status === 'all-ok') return false;
    if (filter === 'pending' && !s.tests.hasPending) return false;
    if (filter === 'clean'   && (s.build.status !== 'all-ok' || s.tests.status !== 'all-pass')) return false;
    return true;
  });

  const counts = {
    fail:    commitsWithState.filter(({ s }) => s.tests.hasUniformFail).length,
    mixed:   commitsWithState.filter(({ s }) => s.tests.hasMixed).length,
    build:   commitsWithState.filter(({ s }) => s.build.status !== 'all-ok').length,
    pending: commitsWithState.filter(({ s }) => s.tests.hasPending).length,
    clean:   commitsWithState.filter(({ s }) => s.build.status === 'all-ok' && s.tests.status === 'all-pass').length,
  };

  const groups = groupCommitsByAge(filtered.map(f => f.c));
  const stateBySha = Object.fromEntries(filtered.map(({ c, s }) => [c.sha, s]));
  const branchInfo = BRANCHES.find(b => b.name === branch);

  return (
    <div style={{ maxWidth: 'var(--maxw)', margin: '0 auto', padding: '24px 32px 60px' }}>
      {/* Page headline with inline branch picker */}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 12, flexWrap: 'wrap', marginBottom: 6 }}>
        <h1 style={{ margin: 0, fontSize: 24, fontWeight: 600, letterSpacing: -0.3, display: 'inline-flex', alignItems: 'baseline', gap: 10 }}>
          Commits on
          <BranchPicker branch={branch} onChange={onChangeBranch}/>
        </h1>
      </div>
      <p style={{ color: 'var(--fg-muted)', marginTop: 4, marginBottom: 24, fontSize: 13 }}>
        {branchInfo?.commits} commits indexed on this branch · {commits.length} shown · last activity {relTime(branchInfo?.lastCommitISO || commits[0]?.whenISO)}
      </p>

      {/* Stat tiles + Sparkline */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr 2fr', gap: 12, marginBottom: 20 }}>
        <StatTile label="Clean" value={counts.clean} accent="success"/>
        <StatTile label="Failing tests" value={counts.fail} accent="danger"/>
        <StatTile label="Mixed results" value={counts.mixed} accent="warning"/>
        <StatTile label="Build issues" value={counts.build} accent="buildfail"/>
        <div className="card card-pad" style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between', gap: 8 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <div style={{ fontSize: 11, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
              Recent · last 12 commits
            </div>
            <div style={{ fontSize: 11, color: 'var(--fg-subtle)' }}>← older · newer →</div>
          </div>
          <Sparkline commits={commits.slice(0, 12)} width={360} height={44} onPick={sha => onOpen(sha)}/>
          <SparklineLegend/>
        </div>
      </div>

      {/* Toolbar */}
      <div className="card" style={{ overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 10, borderBottom: '1px solid var(--border)', background: 'var(--bg-subtle)', flexWrap: 'wrap' }}>
          <SearchInput value={search} onChange={setSearch} placeholder="Search SHA, message, author…"/>
          <SegmentedControl
            value={filter} onChange={setFilter}
            options={[
              { v: 'all', label: 'All', count: commits.length },
              { v: 'fail', label: 'Failing', count: counts.fail, dot: 'danger' },
              { v: 'mixed', label: 'Mixed', count: counts.mixed, dot: 'warning' },
              { v: 'build', label: 'Build issue', count: counts.build, dot: 'buildfail' },
              { v: 'pending', label: 'Running', count: counts.pending, dot: 'info' },
              { v: 'clean', label: 'Clean', count: counts.clean, dot: 'success' },
            ]}
          />
        </div>

        {/* Table header */}
        <div role="row" style={{
          display: 'grid', gridTemplateColumns: '32px 1fr 110px 130px 170px 170px 130px 90px',
          padding: '8px 14px', fontSize: 11, fontWeight: 500, color: 'var(--fg-muted)',
          textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid var(--border)',
          background: 'var(--bg-subtle)',
        }}>
          <div></div>
          <div>Commit</div>
          <div>SHA</div>
          <div>Author</div>
          <div>Build</div>
          <div>Tests</div>
          <div>Flags</div>
          <div style={{ textAlign: 'right' }}>When</div>
        </div>

        {/* Grouped rows */}
        {groups.map(g => (
          <React.Fragment key={g.id}>
            <div style={{
              padding: '8px 14px', background: 'var(--bg-muted)',
              fontSize: 11, fontWeight: 600, color: 'var(--fg-muted)',
              textTransform: 'uppercase', letterSpacing: 0.6,
              borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between',
            }}>
              <span>{g.label}</span>
              <span style={{ color: 'var(--fg-subtle)', fontWeight: 400 }}>{g.commits.length}</span>
            </div>
            {g.commits.map(c => <CommitRow key={c.sha} c={c} s={stateBySha[c.sha]} onOpen={onOpen}/>)}
          </React.Fragment>
        ))}
        {filtered.length === 0 && (
          <div style={{ padding: '40px 20px', textAlign: 'center', color: 'var(--fg-muted)' }}>
            No commits match.
          </div>
        )}
      </div>
    </div>
  );
}

function StatTile({ label, value, accent }) {
  const color = accent === 'success'   ? 'var(--success-soft-text)' :
                accent === 'warning'   ? 'var(--warning-soft-text)' :
                accent === 'danger'    ? 'var(--danger-soft-text)' :
                accent === 'buildfail' ? 'var(--buildfail-soft-text)' :
                accent === 'info'      ? 'var(--info-soft-text)' :
                'var(--fg)';
  return (
    <div className="card card-pad">
      <div style={{ fontSize: 11, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 26, fontWeight: 600, letterSpacing: -0.5, color, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
    </div>
  );
}

function CommitRow({ c, s, onOpen }) {
  return (
    <div role="row" onClick={() => onOpen(c.sha)} style={{
      display: 'grid', gridTemplateColumns: '32px 1fr 110px 130px 170px 170px 130px 90px',
      padding: '12px 14px', alignItems: 'center', cursor: 'pointer',
      borderBottom: '1px solid var(--border-subtle)', gap: 0,
      transition: 'background .08s',
    }}
      onMouseEnter={e => e.currentTarget.style.background = 'var(--bg-subtle)'}
      onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
    >
      <StatusDot state={s}/>
      <div style={{ overflow: 'hidden', minWidth: 0 }}>
        <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', fontWeight: 500, color: 'var(--fg)' }}>
          {c.msg}
        </div>
        <div style={{ fontSize: 12, color: 'var(--fg-muted)', marginTop: 2 }}>
          {c.pr ? `#${c.pr} · ` : ''}{c.files} files · {c.diff}
        </div>
      </div>
      <div className="mono" style={{ color: 'var(--brand)', fontSize: 12 }}>{c.sha}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'var(--fg-muted)', fontSize: 13, overflow: 'hidden' }}>
        <CommitAvatar author={c.author} color={c.avatar} size={20}/>
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.author}</span>
      </div>
      <div><BuildStatusPill build={s.build} size="sm"/></div>
      <div><TestStatusPill tests={s.tests} size="sm"/></div>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center', fontSize: 11, fontFamily: 'var(--font-mono)', flexWrap: 'wrap' }}>
        {s.fpeCount > 0      && <FlagCount kind="fpe"          count={s.fpeCount}/>}
        {s.checksumCount > 0 && <FlagCount kind="checksum"     count={s.checksumCount}/>}
        {s.inlistsFullCount > 0 && <FlagCount kind="inlists_full" count={s.inlistsFullCount}/>}
        {s.fpeCount + s.checksumCount + s.inlistsFullCount === 0 && <span style={{ color: 'var(--fg-subtle)' }}>—</span>}
      </div>
      <div style={{ textAlign: 'right', fontSize: 12, color: 'var(--fg-muted)', fontVariantNumeric: 'tabular-nums' }}>
        {relTime(c.whenISO)}
      </div>
    </div>
  );
}

function FlagCount({ kind, count }) {
  const map = {
    fpe:          { icon: 'wrench', color: 'var(--warning-soft-text)', title: 'FPE raised' },
    checksum:     { icon: 'neq',    color: 'var(--warning-soft-text)', title: 'checksum mismatch' },
    inlists_full: { icon: 'plus',   color: 'var(--info-soft-text)',    title: 'full-inlist run' },
  }[kind];
  return (
    <span title={`${count} ${map.title}`} style={{ display: 'inline-flex', alignItems: 'center', gap: 3, color: map.color }}>
      <Icon name={map.icon} size={11}/>{count}
    </span>
  );
}

function SearchInput({ value, onChange, placeholder }) {
  return (
    <div style={{ position: 'relative', flex: 1, maxWidth: 360 }}>
      <Icon name="search" size={13} style={{
        position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--fg-subtle)',
      }}/>
      <input
        type="text" value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder}
        style={{
          width: '100%', padding: '7px 10px 7px 30px',
          background: 'var(--bg-elev)', border: '1px solid var(--border)',
          borderRadius: 'var(--r-md)', color: 'var(--fg)',
          fontFamily: 'inherit', fontSize: 13, outline: 'none',
        }}
        onFocus={e => e.target.style.boxShadow = 'var(--shadow-focus)'}
        onBlur={e => e.target.style.boxShadow = 'none'}
      />
    </div>
  );
}

function SegmentedControl({ value, onChange, options }) {
  return (
    <div style={{ display: 'inline-flex', gap: 2, padding: 2, background: 'var(--bg-muted)', borderRadius: 'var(--r-md)' }}>
      {options.map(o => {
        const active = o.v === value;
        return (
          <button key={o.v} onClick={() => onChange(o.v)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '5px 10px', border: 'none', cursor: 'pointer',
            borderRadius: 4, fontSize: 12, fontWeight: 500,
            background: active ? 'var(--bg-elev)' : 'transparent',
            color: active ? 'var(--fg)' : 'var(--fg-muted)',
            boxShadow: active ? 'var(--shadow-sm)' : 'none',
            fontFamily: 'inherit',
          }}>
            {o.dot && <span className={`dot dot-${o.dot}`}/>}
            {o.label}
            {typeof o.count === 'number' && <span style={{ color: 'var(--fg-subtle)', fontVariantNumeric: 'tabular-nums', fontSize: 11 }}>{o.count}</span>}
          </button>
        );
      })}
    </div>
  );
}

// ============================================================================
// CommitDetail
// ============================================================================
function CommitDetail({ sha, branch, onChangeBranch, commits, onOpen, onOpenTest }) {
  const idx = commits.findIndex(c => c.sha === sha);
  const c = commits[idx] || commits[0];
  const prev = commits[idx + 1];
  const next = commits[idx - 1];
  const matrix = useMemoS(() => getMatrixForCommit(c.sha), [c.sha]);
  const state = useMemoS(() => getCommitState(c.sha), [c.sha]);
  const lastPassing = commits.slice(idx + 1).find(x => {
    const s = getCommitState(x.sha);
    return s.build.status === 'all-ok' && s.tests.status === 'all-pass';
  });

  // Context-sensitive default tab:
  //   build issues → Computers
  //   test failures or mixed → Tests
  //   pending only → Summary (still useful to see what's in progress)
  //   clean → Summary
  const defaultTab =
    state.build.status === 'all-fail' || state.build.status === 'some-fail' ? 'computers' :
    state.tests.hasUniformFail || state.tests.hasMixed ? 'tests' :
    'summary';
  const [tab, setTab] = useStateS(defaultTab);
  useEffectS(() => { setTab(defaultTab); }, [c.sha, defaultTab]);

  // Per-computer aggregate
  const perComputer = COMPUTERS.map(comp => {
    let pass = 0, fail = 0, skip = 0, noBuild = 0, pending = 0, fpe = 0, checksum = 0, inlistsFull = 0;
    TESTS.forEach(t => {
      const cell = matrix[t.id]?.[comp.id];
      if (!cell) return;
      if (cell.status === 'pass') pass++;
      else if (cell.status === 'fail') fail++;
      else if (cell.status === 'skip') skip++;
      else if (cell.status === 'no-build') noBuild++;
      else if (cell.status === 'pending') pending++;
      if (cell.flags.fpe) fpe++;
      if (cell.flags.checksum) checksum++;
      if (cell.flags.inlists_full) inlistsFull++;
    });
    const built = !state.failedBuildComputers.includes(comp.id);
    return { ...comp, pass, fail, skip, noBuild, pending, fpe, checksum, inlistsFull, built };
  });

  return (
    <div style={{ maxWidth: 'var(--maxw)', margin: '0 auto', padding: '20px 32px 60px' }}>
      {/* Breadcrumb / branch chip / prev-next */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14, fontSize: 13, color: 'var(--fg-muted)', flexWrap: 'wrap' }}>
        <button className="btn btn-ghost btn-sm" onClick={() => window.appNav('commits')}>
          <Icon name="arrowL" size={12}/> Commits
        </button>
        <span style={{ opacity: 0.5 }}>/</span>
        <BranchPicker branch={branch} onChange={onChangeBranch} size="sm"/>
        <span style={{ opacity: 0.5 }}>/</span>
        <span className="mono" style={{ color: 'var(--fg)' }}>{c.sha}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
          {prev && <button className="btn btn-sm" onClick={() => onOpen(prev.sha)} title={prev.msg}>
            <Icon name="arrowL" size={11}/> <span className="mono">{prev.sha}</span>
          </button>}
          {next && <button className="btn btn-sm" onClick={() => onOpen(next.sha)} title={next.msg}>
            <span className="mono">{next.sha}</span> <Icon name="arrow" size={11}/>
          </button>}
        </div>
      </div>

      {/* Hero header */}
      <div className="card" style={{ padding: 20, marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10, flexWrap: 'wrap' }}>
              <BuildStatusPill build={state.build}/>
              <TestStatusPill tests={state.tests}/>
              {c.pr && <span className="pill pill-muted">PR #{c.pr}</span>}
              {state.fpeCount > 0 && <span className="pill pill-warning"><Icon name="wrench" size={10}/> {state.fpeCount} FPE</span>}
              {state.checksumCount > 0 && <span className="pill pill-warning"><Icon name="neq" size={10}/> {state.checksumCount} checksum ≠</span>}
              {state.inlistsFullCount > 0 && <span className="pill pill-info"><Icon name="plus" size={10}/> {state.inlistsFullCount} full inlists</span>}
            </div>
            <h1 style={{ margin: '0 0 10px', fontSize: 20, fontWeight: 600, letterSpacing: -0.2, lineHeight: 1.35 }}>
              {c.msg}
            </h1>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', fontSize: 13, color: 'var(--fg-muted)' }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <CommitAvatar author={c.author} color={c.avatar} size={20}/>
                <strong style={{ color: 'var(--fg)', fontWeight: 500 }}>{c.author}</strong>
                <span className="mono" style={{ color: 'var(--fg-subtle)' }}>@{c.authorHandle}</span>
              </span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <Icon name="clock" size={12}/> committed {relTime(c.whenISO)}
              </span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                <Icon name="file" size={12}/> {c.files} files · {c.diff}
              </span>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-end' }}>
            <a className="btn" href={`https://github.com/MESAHub/mesa/commit/${c.full}`} target="_blank" rel="noreferrer">
              <Icon name="github" size={13}/> View on GitHub
            </a>
            <CopyButton value={c.full} label="Copy SHA"/>
          </div>
        </div>

        <div style={{ marginTop: 16, paddingTop: 14, borderTop: '1px solid var(--border-subtle)',
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr 1fr auto', gap: 16, alignItems: 'center' }}>
          <Stat label="Builds" value={`${state.builtComputers.length} / ${COMPUTERS.length}`}
            color={state.build.status === 'all-fail' ? 'var(--buildfail-soft-text)'
                : state.build.status === 'some-fail' ? 'var(--warning-soft-text)' : 'var(--success-soft-text)'}/>
          <Stat label="Tests failing" value={state.tests.uniformFailingTests} color={state.tests.uniformFailingTests ? 'var(--danger-soft-text)' : 'var(--fg-subtle)'}/>
          <Stat label="Mixed" value={state.tests.mixedTests} color={state.tests.mixedTests ? 'var(--warning-soft-text)' : 'var(--fg-subtle)'}/>
          <Stat label="Pending" value={state.tests.pendingTests} color={state.tests.pendingTests ? 'var(--info-soft-text)' : 'var(--fg-subtle)'}/>
          <Stat label="FPE / ≠" value={state.fpeCount + state.checksumCount} color={(state.fpeCount + state.checksumCount) ? 'var(--warning-soft-text)' : 'var(--fg-subtle)'}/>
          <div>
            <div style={{ fontSize: 11, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 6 }}>
              Recent · last 12
            </div>
            <Sparkline commits={commits.slice(0, 12)} current={c.sha} width={240} height={40} onPick={sha => onOpen(sha)}/>
          </div>
        </div>

        <div className="mono" style={{ marginTop: 14, paddingTop: 14, borderTop: '1px solid var(--border-subtle)',
          color: 'var(--fg-subtle)', fontSize: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
          <span>full SHA</span>
          <span style={{ color: 'var(--fg)' }}>{c.full}</span>
        </div>
      </div>

      {/* State-conditional banners (can stack) */}
      {state.build.status === 'all-fail' && <BuildFailBanner state={state} onJump={() => setTab('computers')}/>}
      {state.build.status === 'some-fail' && <BuildPartialBanner state={state} onJump={() => setTab('computers')}/>}
      {state.tests.hasUniformFail && lastPassing && <FailingBanner state={state} lastPassing={lastPassing} onJump={() => setTab('diff')} onOpen={onOpen}/>}
      {state.tests.hasMixed && <MixedBanner state={state} onJump={() => setTab('tests')}/>}
      {state.tests.hasPending && state.tests.status !== 'fail' && state.tests.status !== 'mixed' && <PendingBanner state={state}/>}

      {/* Tabs */}
      <div style={{ borderBottom: '1px solid var(--border)', margin: '16px 0 18px', display: 'flex', gap: 4 }}>
        {[
          { v: 'summary',   label: 'Summary' },
          { v: 'tests',     label: 'Tests',
            badge: state.tests.uniformFailingTests > 0 ? state.tests.uniformFailingTests
                 : state.tests.mixedTests > 0 ? state.tests.mixedTests
                 : (state.fpeCount + state.checksumCount) > 0 ? (state.fpeCount + state.checksumCount)
                 : null,
            badgeColor: state.tests.uniformFailingTests > 0 ? 'danger' : 'warning' },
          { v: 'computers', label: 'Computers',
            badge: state.failedBuildComputers.length || null,
            badgeColor: state.build.status === 'all-fail' ? 'buildfail' : 'warning' },
          { v: 'diff',      label: 'Diff vs last pass', disabled: !lastPassing },
          { v: 'logs',      label: 'Logs' },
        ].map(t => (
          <button key={t.v} onClick={() => !t.disabled && setTab(t.v)} disabled={t.disabled} style={{
            padding: '10px 14px', border: 'none', background: 'transparent',
            color: tab === t.v ? 'var(--fg)' : 'var(--fg-muted)',
            borderBottom: tab === t.v ? '2px solid var(--brand)' : '2px solid transparent',
            marginBottom: -1, cursor: t.disabled ? 'not-allowed' : 'pointer', fontSize: 13, fontWeight: 500,
            opacity: t.disabled ? 0.5 : 1,
            display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: 'inherit',
          }}>
            {t.label}
            {t.badge != null && (
              <span className={`pill pill-${t.badgeColor}`} style={{ fontSize: 10, padding: '1px 6px' }}>{t.badge}</span>
            )}
          </button>
        ))}
      </div>

      {tab === 'summary' && <SummaryTab c={c} state={state} matrix={matrix} perComputer={perComputer} onOpenTest={onOpenTest}/>}
      {tab === 'tests' && <TestsTab c={c} state={state} matrix={matrix} onOpenTest={onOpenTest}/>}
      {tab === 'computers' && <ComputersTab perComputer={perComputer} state={state} c={c}/>}
      {tab === 'diff' && <DiffTab c={c} lastPassing={lastPassing} state={state}/>}
      {tab === 'logs' && <LogsTab c={c} state={state}/>}
    </div>
  );
}

function Stat({ label, value, color }) {
  return (
    <div>
      <div style={{ fontSize: 11, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 600, letterSpacing: -0.4, color, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
    </div>
  );
}

// ============================================================================
// Banners
// ============================================================================
function BuildFailBanner({ state, onJump }) {
  return (
    <Banner accent="buildfail" icon="x" actionLabel="See computers" onAction={onJump}>
      <div style={{ fontWeight: 500, fontSize: 13 }}>
        <span style={{ color: 'var(--buildfail-soft-text)' }}>Build failed on every computer.</span> No test data for this commit.
      </div>
      <div style={{ fontSize: 12, color: 'var(--fg-muted)', marginTop: 2 }}>
        Failed: {state.failedBuildComputers.map(id => <span key={id} className="mono" style={{ color: 'var(--fg)' }}>{id} </span>)}
      </div>
    </Banner>
  );
}
function BuildPartialBanner({ state, onJump }) {
  return (
    <Banner accent="warning" icon="warn" actionLabel="See computers" onAction={onJump}>
      <div style={{ fontWeight: 500, fontSize: 13 }}>
        Build failed on <span style={{ color: 'var(--warning-soft-text)' }}>{state.failedBuildComputers.length}</span>{' '}
        of {COMPUTERS.length} computers · tests still ran on the others.
      </div>
      <div style={{ fontSize: 12, color: 'var(--fg-muted)', marginTop: 2 }}>
        No build: {state.failedBuildComputers.map(id => <span key={id} className="mono" style={{ color: 'var(--fg)' }}>{id} </span>)}
      </div>
    </Banner>
  );
}
function FailingBanner({ state, lastPassing, onJump, onOpen }) {
  return (
    <Banner accent="danger" icon="x" actionLabel="View diff" onAction={onJump}>
      <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 2 }}>
        <span style={{ color: 'var(--danger-soft-text)' }}>{state.tests.uniformFailingTests} test{state.tests.uniformFailingTests === 1 ? '' : 's'} failing</span>
        {' '}since last passing commit{' '}
        <button onClick={() => onOpen(lastPassing.sha)} className="mono" style={{
          background: 'none', border: 'none', color: 'var(--brand)',
          cursor: 'pointer', font: 'inherit', fontFamily: 'var(--font-mono)',
        }}>{lastPassing.sha}</button>
      </div>
      <div style={{ fontSize: 12, color: 'var(--fg-muted)' }}>
        {state.failingCells.slice(0, 3).map(f => (
          <span key={f.test.id + f.computer.id} style={{ marginRight: 12 }}>
            <span className="mono" style={{ color: 'var(--fg)' }}>{f.test.id}</span>
            {' on '}
            <span className="mono" style={{ color: 'var(--fg)' }}>{f.computer.id}</span>
          </span>
        ))}
        {state.failingCells.length > 3 && <span>+ {state.failingCells.length - 3} more</span>}
      </div>
    </Banner>
  );
}
function MixedBanner({ state, onJump }) {
  return (
    <Banner accent="warning" icon="warn" actionLabel="See mixed tests" onAction={onJump}>
      <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 2 }}>
        <span style={{ color: 'var(--warning-soft-text)' }}>{state.tests.mixedTests} test{state.tests.mixedTests === 1 ? '' : 's'} in mixed state</span>
        {' '}— same test passes on some computers, fails on others. Often points to a computer-specific issue.
      </div>
      <div style={{ fontSize: 12, color: 'var(--fg-muted)' }}>
        {state.mixedCells.slice(0, 3).map(f => (
          <span key={f.test.id + f.computer.id} style={{ marginRight: 12 }}>
            <span className="mono" style={{ color: 'var(--fg)' }}>{f.test.id}</span>
            {' fails on '}
            <span className="mono" style={{ color: 'var(--fg)' }}>{f.computer.id}</span>
          </span>
        ))}
        {state.mixedCells.length > 3 && <span>+ {state.mixedCells.length - 3} more</span>}
      </div>
    </Banner>
  );
}
function PendingBanner({ state }) {
  return (
    <Banner accent="info" icon="clock">
      <div style={{ fontSize: 13 }}>
        <span style={{ color: 'var(--info-soft-text)' }}>{state.tests.pendingTests} test{state.tests.pendingTests === 1 ? '' : 's'} still running.</span>
        {' '}Results below may be incomplete; the page auto-refreshes.
      </div>
    </Banner>
  );
}

function Banner({ accent, icon, children, actionLabel, onAction }) {
  const colorMap = {
    danger: 'var(--danger)', warning: 'var(--warning)',
    buildfail: 'var(--buildfail)', info: 'var(--info)', success: 'var(--success)',
  };
  return (
    <div className="card" style={{ padding: 14, borderLeft: `3px solid ${colorMap[accent]}`, marginBottom: 8 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <Icon name={icon} size={16} style={{ color: colorMap[accent] }}/>
        <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
        {actionLabel && <button className="btn btn-sm" onClick={onAction}>{actionLabel} <Icon name="chevronR" size={11}/></button>}
      </div>
    </div>
  );
}

// ============================================================================
// Summary tab
// ============================================================================
function SummaryTab({ c, state, matrix, perComputer, onOpenTest }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20 }}>
      <div>
        <div className="card" style={{ padding: 16, marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14, gap: 12, flexWrap: 'wrap' }}>
            <div>
              <h3 style={{ margin: 0, fontSize: 14, fontWeight: 600 }}>Test × Computer matrix</h3>
              <p style={{ margin: '2px 0 0', fontSize: 12, color: 'var(--fg-muted)' }}>
                Click any cell to see all instances of that test on this commit.
              </p>
            </div>
            <MatrixLegend/>
          </div>
          <StatusMatrix tests={TESTS} computers={COMPUTERS} matrix={matrix}
            onCellClick={(t, comp) => onOpenTest(c.sha, t.id, comp.id)}/>
          <div style={{ marginTop: 12, fontSize: 11, color: 'var(--fg-subtle)', fontFamily: 'var(--font-mono)' }}>
            Showing {TESTS.length} of 106 tests · <a href="#" style={{ color: 'var(--brand)' }}>view all</a>
          </div>
        </div>
      </div>

      <div>
        <div className="card" style={{ padding: 14, marginBottom: 16 }}>
          <h3 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Computers ({COMPUTERS.length})
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {perComputer.map(comp => {
              const compState = !comp.built ? 'build-fail'
                : comp.fail > 0 ? 'fail'
                : comp.pending > 0 ? 'pending'
                : (comp.fpe + comp.checksum) > 0 ? 'mixed'
                : 'all-pass';
              return (
                <div key={comp.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 0' }}>
                  <StatusDot state={compState}/>
                  <span style={{ flex: 1, minWidth: 0, fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--fg)' }}>
                    {comp.id}
                  </span>
                  <span style={{ fontSize: 11, color: 'var(--fg-muted)', fontFamily: 'var(--font-mono)', display: 'inline-flex', gap: 4, alignItems: 'center' }}>
                    {!comp.built && <span style={{ color: 'var(--buildfail-soft-text)' }}>no build</span>}
                    {comp.built && comp.fail > 0 && <span style={{ color: 'var(--danger-soft-text)' }}>{comp.fail} fail</span>}
                    {comp.built && comp.pending > 0 && <span style={{ color: 'var(--info-soft-text)' }}>{comp.pending} pending</span>}
                    {comp.built && comp.fail === 0 && comp.fpe > 0 && <span style={{ color: 'var(--warning-soft-text)' }}><Icon name="wrench" size={10}/>{comp.fpe}</span>}
                    {comp.built && comp.checksum > 0 && <span style={{ color: 'var(--warning-soft-text)' }}><Icon name="neq" size={10}/>{comp.checksum}</span>}
                    {comp.built && comp.fail === 0 && comp.fpe === 0 && comp.checksum === 0 && comp.pending === 0 && <span>{comp.pass} ok</span>}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        <div className="card" style={{ padding: 14 }}>
          <h3 style={{ margin: '0 0 10px', fontSize: 13, fontWeight: 600, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Activity
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, fontSize: 12 }}>
            <ActivityRow time="19 May 19:27" text={<>commit <span className="mono" style={{ color: 'var(--fg)' }}>{c.sha}</span> indexed</>}/>
            {state.builtComputers.slice(0, 2).map(id => (
              <ActivityRow key={id} time="20:14" text={<>build OK on <span className="mono" style={{ color: 'var(--fg)' }}>{id}</span></>}/>
            ))}
            {state.failedBuildComputers.slice(0, 2).map(id => (
              <ActivityRow key={id} time="20:42" text={<><span style={{ color: 'var(--buildfail-soft-text)' }}>build FAILED</span> on <span className="mono" style={{ color: 'var(--fg)' }}>{id}</span></>}/>
            ))}
            {state.failingCells.slice(0, 2).map(f => (
              <ActivityRow key={f.test.id + f.computer.id} time="20:58" text={<><span style={{ color: 'var(--danger-soft-text)' }}>FAIL</span> · {f.test.id} on {f.computer.id}</>}/>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function ActivityRow({ time, text }) {
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      <span style={{ width: 90, flexShrink: 0, color: 'var(--fg-subtle)', fontFamily: 'var(--font-mono)', fontSize: 11 }}>{time}</span>
      <span style={{ color: 'var(--fg-muted)' }}>{text}</span>
    </div>
  );
}

// ============================================================================
// Tests tab
// ============================================================================
function TestsTab({ c, state, matrix, onOpenTest }) {
  const initial = state.tests.uniformFailingTests > 0 ? 'fail'
    : state.tests.mixedTests > 0 ? 'mixed'
    : state.tests.pendingTests > 0 ? 'pending'
    : 'all';
  const [filter, setFilter] = useStateS(initial);
  const [search, setSearch] = useStateS('');
  const [moduleFilter, setModuleFilter] = useStateS('all');

  const rows = TESTS.map(t => {
    let pass = 0, fail = 0, skip = 0, noBuild = 0, pending = 0, fpe = 0, checksum = 0, inlistsFull = 0;
    COMPUTERS.forEach(comp => {
      const cell = matrix[t.id]?.[comp.id];
      if (!cell) return;
      if (cell.status === 'pass') pass++;
      else if (cell.status === 'fail') fail++;
      else if (cell.status === 'skip') skip++;
      else if (cell.status === 'no-build') noBuild++;
      else if (cell.status === 'pending') pending++;
      if (cell.flags.fpe) fpe++;
      if (cell.flags.checksum) checksum++;
      if (cell.flags.inlists_full) inlistsFull++;
    });
    const ran = pass + fail;
    let overall;
    if (fail > 0 && pass > 0) overall = 'mixed';
    else if (fail === ran && fail > 0) overall = 'fail';
    else if (pending > 0) overall = 'pending';
    else if ((fpe + checksum) > 0) overall = 'flagged';
    else overall = 'pass';
    return { ...t, pass, fail, skip, noBuild, pending, fpe, checksum, inlistsFull, overall };
  });

  const filtered = rows.filter(r => {
    if (filter !== 'all' && r.overall !== filter) return false;
    if (moduleFilter !== 'all' && r.module !== moduleFilter) return false;
    if (search && !r.id.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const count = (k) => rows.filter(r => r.overall === k).length;

  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 12, borderBottom: '1px solid var(--border)', background: 'var(--bg-subtle)', flexWrap: 'wrap' }}>
        <SearchInput value={search} onChange={setSearch} placeholder="Filter tests by name…"/>
        <SegmentedControl value={filter} onChange={setFilter} options={[
          { v: 'all', label: 'All', count: rows.length },
          { v: 'fail', label: 'Failing', count: count('fail'), dot: 'danger' },
          { v: 'mixed', label: 'Mixed', count: count('mixed'), dot: 'warning' },
          { v: 'flagged', label: 'Flagged', count: count('flagged'), dot: 'warning' },
          { v: 'pending', label: 'Running', count: count('pending'), dot: 'info' },
          { v: 'pass', label: 'Pass', count: count('pass'), dot: 'success' },
        ]}/>
        <Dropdown align="right" trigger={
          <button className="btn btn-sm"><Icon name="filter" size={11}/> Module: {moduleFilter}<Icon name="chevron" size={11}/></button>
        }>
          <DropdownItem active={moduleFilter==='all'} onClick={() => setModuleFilter('all')}>All modules</DropdownItem>
          {TEST_MODULES.map(m => (
            <DropdownItem key={m.id} active={moduleFilter===m.id} onClick={() => setModuleFilter(m.id)}>
              <span className="mono">{m.name}/</span>
              <span style={{ marginLeft: 'auto', color: 'var(--fg-subtle)', fontSize: 11 }}>{m.count}</span>
            </DropdownItem>
          ))}
        </Dropdown>
      </div>

      <div role="row" style={{
        display: 'grid', gridTemplateColumns: '32px 1fr 90px 180px 130px',
        padding: '8px 14px', fontSize: 11, fontWeight: 500, color: 'var(--fg-muted)',
        textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid var(--border)',
      }}>
        <div></div><div>Test</div><div>Module</div><div>Per computer</div><div style={{ textAlign: 'right' }}>Status</div>
      </div>

      {filtered.map(r => (
        <div key={r.id} role="row" onClick={() => onOpenTest(c.sha, r.id)} style={{
          display: 'grid', gridTemplateColumns: '32px 1fr 90px 180px 130px',
          padding: '10px 14px', alignItems: 'center',
          borderBottom: '1px solid var(--border-subtle)', cursor: 'pointer',
        }}
          onMouseEnter={e => e.currentTarget.style.background = 'var(--bg-subtle)'}
          onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
        >
          <StatusDot state={r.overall === 'fail' ? 'fail' : r.overall === 'mixed' ? 'mixed' : r.overall === 'pending' ? 'pending' : r.overall === 'flagged' ? 'mixed' : 'all-pass'}/>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 13, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {r.id}
            <span style={{ marginLeft: 8, color: 'var(--fg-subtle)', fontSize: 11, fontFamily: 'var(--font-sans)' }}>{r.topic}</span>
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--fg-muted)' }}>{r.module}/</div>
          <div style={{ display: 'flex', gap: 4 }}>
            {COMPUTERS.map(comp => {
              const cell = matrix[r.id]?.[comp.id];
              const a = cellAppearance(cell);
              return (
                <span key={comp.id} title={`${comp.id}: ${a.label}`}
                  style={{
                    position: 'relative', width: 20, height: 20, borderRadius: 3,
                    background: a.bg,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                  {a.glyph && <Icon name={a.glyph} size={11} style={{ color: a.glyphColor }}/>}
                  {a.corner && (
                    <span style={{ position: 'absolute', top: -2, right: -2, width: 9, height: 9, borderRadius: 999, background: 'var(--info)', border: '1px solid var(--bg-elev)' }}/>
                  )}
                </span>
              );
            })}
          </div>
          <div style={{ textAlign: 'right', fontFamily: 'var(--font-mono)', fontSize: 11, display: 'flex', justifyContent: 'flex-end', gap: 6 }}>
            {r.fail > 0 && r.pass > 0 && <span style={{ color: 'var(--warning-soft-text)' }}>{r.fail}/{r.pass + r.fail} mixed</span>}
            {r.fail > 0 && r.pass === 0 && <span style={{ color: 'var(--danger-soft-text)' }}>{r.fail} fail</span>}
            {r.fail === 0 && r.pending > 0 && <span style={{ color: 'var(--info-soft-text)' }}>{r.pending} running</span>}
            {r.fail === 0 && r.pending === 0 && r.fpe > 0 && <span style={{ color: 'var(--warning-soft-text)' }}><Icon name="wrench" size={10}/>{r.fpe}</span>}
            {r.fail === 0 && r.pending === 0 && r.checksum > 0 && <span style={{ color: 'var(--warning-soft-text)' }}><Icon name="neq" size={10}/>{r.checksum}</span>}
            {r.fail === 0 && r.pending === 0 && r.fpe === 0 && r.checksum === 0 && r.noBuild === 0 && <span style={{ color: 'var(--success-soft-text)' }}>ok</span>}
            {r.noBuild > 0 && r.fail === 0 && r.pending === 0 && <span style={{ color: 'var(--fg-subtle)' }}>{r.noBuild} n/b</span>}
          </div>
        </div>
      ))}
      {filtered.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: 'var(--fg-muted)' }}>No tests match.</div>}
    </div>
  );
}

// ============================================================================
// Computers tab
// ============================================================================
function ComputersTab({ perComputer, state, c }) {
  const order = (comp) => !comp.built ? 0 : comp.fail > 0 ? 1 : comp.pending > 0 ? 2 : (comp.fpe + comp.checksum) > 0 ? 3 : 4;
  const sorted = [...perComputer].sort((a, b) => order(a) - order(b));
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(330px, 1fr))', gap: 14 }}>
      {sorted.map(comp => {
        const compState = !comp.built ? 'build-fail'
          : comp.fail > 0 ? 'fail'
          : comp.pending > 0 ? 'pending'
          : (comp.fpe + comp.checksum) > 0 ? 'mixed'
          : 'all-pass';
        const borderColor =
          compState === 'build-fail' ? 'var(--buildfail)' :
          compState === 'fail'       ? 'var(--danger)' :
          compState === 'mixed'      ? 'var(--warning)' :
          compState === 'pending'    ? 'var(--info)' :
          'var(--success)';
        return (
          <div key={comp.id} className="card" style={{ padding: 14, borderLeft: `3px solid ${borderColor}` }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
              <StatusDot state={compState}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: 14, fontWeight: 600, color: 'var(--fg)' }}>{comp.id}</div>
                <div style={{ fontSize: 11, color: 'var(--fg-muted)' }}>maintained by {comp.owner}</div>
              </div>
              <span className="pill pill-muted" style={{ textTransform: 'lowercase' }}>{comp.os}</span>
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--fg-muted)', padding: '8px 10px', background: 'var(--bg-subtle)', borderRadius: 6, marginBottom: 10 }}>
              {comp.sdk}
            </div>
            {!comp.built ? (
              <>
                <div style={{ padding: '10px 12px', background: 'var(--buildfail-soft)', color: 'var(--buildfail-soft-text)', borderRadius: 6, fontSize: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Icon name="x" size={13}/>
                  <span><strong>Compilation failed.</strong> No test data.</span>
                </div>
                <div style={{ marginTop: 10, display: 'flex', justifyContent: 'space-between', fontSize: 11, color: 'var(--fg-muted)' }}>
                  <span>Last successful build: <span className="mono" style={{ color: 'var(--fg)' }}>3d28c10</span></span>
                  <a href="#" style={{ color: 'var(--brand)' }}>build logs ↗</a>
                </div>
              </>
            ) : (
              <>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 6, marginBottom: 10 }}>
                  <MiniStat label="pass" value={comp.pass} color="var(--success-soft-text)"/>
                  <MiniStat label="fail" value={comp.fail} color={comp.fail ? 'var(--danger-soft-text)' : 'var(--fg-subtle)'}/>
                  <MiniStat label="run" value={comp.pending} color={comp.pending ? 'var(--info-soft-text)' : 'var(--fg-subtle)'} icon="clock"/>
                  <MiniStat label="FPE" value={comp.fpe} color={comp.fpe ? 'var(--warning-soft-text)' : 'var(--fg-subtle)'} icon="wrench"/>
                  <MiniStat label="≠" value={comp.checksum} color={comp.checksum ? 'var(--warning-soft-text)' : 'var(--fg-subtle)'} icon="neq"/>
                </div>
                <div style={{ fontSize: 11, color: 'var(--fg-muted)', display: 'flex', justifyContent: 'space-between' }}>
                  <span>
                    Compilation: <strong style={{ color: 'var(--success-soft-text)' }}>Succeeded</strong>
                    {comp.inlistsFull > 0 && <> · <span style={{ color: 'var(--info-soft-text)' }}><Icon name="plus" size={10}/> {comp.inlistsFull} full-inlist</span></>}
                  </span>
                  <a href="#" style={{ color: 'var(--brand)' }}>logs ↗</a>
                </div>
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}

function MiniStat({ label, value, color, icon }) {
  return (
    <div style={{ padding: '6px 8px', background: 'var(--bg-subtle)', borderRadius: 6 }}>
      <div style={{ fontSize: 10, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.4, display: 'inline-flex', alignItems: 'center', gap: 3 }}>
        {icon && <Icon name={icon} size={9}/>}
        {label}
      </div>
      <div style={{ fontSize: 18, fontWeight: 600, color, fontVariantNumeric: 'tabular-nums', fontFamily: 'var(--font-mono)' }}>{value}</div>
    </div>
  );
}

// ============================================================================
// Diff tab
// ============================================================================
function DiffTab({ c, lastPassing, state }) {
  if (!lastPassing) return <EmptyState label="No prior passing commit available." icon="check"/>;
  const rows = [
    ...state.failingCells.map(f => ({ ...f, change: 'new-failure', kind: null })),
    ...state.mixedCells.map(f => ({ ...f, change: 'new-mixed', kind: null })),
    ...state.flaggedCells.filter(f => f.kind !== 'inlists_full').map(f => ({ ...f, change: 'new-flag' })),
  ];
  return (
    <div>
      <div className="card" style={{ padding: 14, marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span style={{ fontSize: 13, color: 'var(--fg-muted)' }}>Comparing</span>
          <span className="mono" style={{ color: 'var(--brand)', fontSize: 13 }}>{lastPassing.sha}</span>
          <Icon name="arrow" size={12} style={{ color: 'var(--fg-subtle)' }}/>
          <span className="mono" style={{ color: 'var(--fg)', fontSize: 13 }}>{c.sha}</span>
          <span style={{ marginLeft: 'auto', fontSize: 12, color: 'var(--fg-muted)' }}>{rows.length} change{rows.length === 1 ? '' : 's'}</span>
        </div>
      </div>
      <div className="card" style={{ overflow: 'hidden' }}>
        <div role="row" style={{ display: 'grid', gridTemplateColumns: '32px 1fr 1fr 180px', padding: '10px 14px', fontSize: 11, fontWeight: 500, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid var(--border)' }}>
          <div></div><div>Test</div><div>Computer</div><div style={{ textAlign: 'right' }}>Status change</div>
        </div>
        {rows.map((row, i) => (
          <div key={i} style={{ display: 'grid', gridTemplateColumns: '32px 1fr 1fr 180px', padding: '10px 14px', alignItems: 'center', borderBottom: '1px solid var(--border-subtle)' }}>
            <StatusDot state={row.change === 'new-failure' ? 'fail' : row.change === 'new-mixed' ? 'mixed' : 'mixed'}/>
            <span className="mono" style={{ fontSize: 13 }}>{row.test.id}</span>
            <span className="mono" style={{ fontSize: 13, color: 'var(--fg-muted)' }}>{row.computer.id}</span>
            <div style={{ textAlign: 'right', display: 'inline-flex', justifyContent: 'flex-end', alignItems: 'center', gap: 6, fontFamily: 'var(--font-mono)', fontSize: 11 }}>
              <span style={{ color: 'var(--success-soft-text)' }}>pass</span>
              <Icon name="arrow" size={10} style={{ color: 'var(--fg-subtle)' }}/>
              {row.change === 'new-failure'
                ? <span style={{ color: 'var(--danger-soft-text)' }}>fail</span>
                : row.change === 'new-mixed'
                  ? <span style={{ color: 'var(--warning-soft-text)' }}>mixed</span>
                  : <span style={{ color: 'var(--warning-soft-text)', display: 'inline-flex', alignItems: 'center', gap: 3 }}>
                      <Icon name={row.kind === 'fpe' ? 'wrench' : 'neq'} size={10}/>
                      {row.kind === 'fpe' ? 'FPE raised' : 'checksum ≠'}
                    </span>}
            </div>
          </div>
        ))}
        {rows.length === 0 && <div style={{ padding: 40, textAlign: 'center', color: 'var(--fg-muted)' }}>No regressions or new flags.</div>}
      </div>
    </div>
  );
}

// ============================================================================
// Logs tab
// ============================================================================
function LogsTab({ c, state }) {
  const initial = state.failedBuildComputers[0] || state.failingCells[0]?.computer.id || COMPUTERS[0].id;
  const [computer, setComputer] = useStateS(initial);

  let lines;
  if (state.failedBuildComputers.includes(computer)) {
    lines = [
      { t: '19:34:02', s: 'info', msg: '== build begin for ' + c.sha + ' on ' + computer + ' ==' },
      { t: '19:34:18', s: 'info', msg: 'cloning MESAHub/mesa @ ' + c.sha + '…' },
      { t: '19:35:02', s: 'info', msg: 'configure star: ok' },
      { t: '19:37:14', s: 'info', msg: 'compiling star/private/eps_grav.f90 …' },
      { t: '19:37:18', s: 'fail', msg: 'star/private/eps_grav.f90:842: error: cannot convert real(dp) to integer' },
      { t: '19:37:18', s: 'fail', msg: 'make: *** [star_lib] Error 1' },
      { t: '19:37:18', s: 'fail', msg: 'BUILD FAILED on ' + computer },
    ];
  } else if (state.failingCells.find(f => f.computer.id === computer)) {
    const failed = state.failingCells.find(f => f.computer.id === computer);
    lines = [
      { t: '19:34:02', s: 'info', msg: '== test_suite begin for ' + c.sha + ' on ' + computer + ' ==' },
      { t: '19:42:21', s: 'ok',   msg: 'compile: OK' },
      { t: '19:42:22', s: 'info', msg: 'running ' + failed.test.id + ' …' },
      { t: '20:38:43', s: 'fail', msg: 'ASSERT failed at star/test_suite/' + failed.test.id + '/test_check.f90:142' },
      { t: '20:38:43', s: 'fail', msg: '   actual   center_h1 = 2.91342e-02' },
      { t: '20:38:43', s: 'fail', msg: '   expected center_h1 = 3.00120e-02 ± 1.0e-04' },
      { t: '20:38:43', s: 'fail', msg: '   tolerance exceeded by 8.78e-04 (8.7×)' },
      { t: '20:38:43', s: 'fail', msg: failed.test.id + ' FAILED on ' + computer },
    ];
  } else {
    lines = [
      { t: '19:34:02', s: 'info', msg: '== test_suite begin for ' + c.sha + ' on ' + computer + ' ==' },
      { t: '19:42:21', s: 'ok',   msg: 'compile: OK' },
      { t: '19:42:22', s: 'info', msg: 'running 106 tests…' },
      { t: '20:08:14', s: 'ok',   msg: 'all 106 tests pass on ' + computer },
      { t: '20:08:14', s: 'info', msg: '== test_suite end ==' },
    ];
  }
  return (
    <div className="card" style={{ overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 10, borderBottom: '1px solid var(--border)', background: 'var(--bg-subtle)' }}>
        <Dropdown trigger={
          <button className="btn btn-sm"><Icon name="cpu" size={11}/> <span className="mono">{computer}</span> <Icon name="chevron" size={11}/></button>
        }>
          {COMPUTERS.map(comp => (
            <DropdownItem key={comp.id} active={comp.id === computer} onClick={() => setComputer(comp.id)}>
              <span className="mono">{comp.id}</span>
              {state.failedBuildComputers.includes(comp.id) && <span style={{ marginLeft: 'auto', color: 'var(--buildfail-soft-text)', fontSize: 11 }}>build fail</span>}
            </DropdownItem>
          ))}
        </Dropdown>
        <span style={{ fontSize: 12, color: 'var(--fg-muted)' }}>{state.failedBuildComputers.includes(computer) ? 'Build log' : 'Build & test log'}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
          <button className="btn btn-sm"><Icon name="download" size={11}/> Download</button>
          <button className="btn btn-sm"><Icon name="expand" size={11}/> Fullscreen</button>
        </div>
      </div>
      <div style={{ fontFamily: 'var(--font-mono)', fontSize: 12, padding: '12px 14px', background: 'var(--bg-subtle)', minHeight: 280 }}>
        {lines.map((l, i) => (
          <div key={i} style={{ display: 'flex', gap: 14, padding: '2px 0' }}>
            <span style={{ color: 'var(--fg-subtle)', width: 70, flexShrink: 0 }}>{l.t}</span>
            <span style={{
              color: l.s === 'ok' ? 'var(--success-soft-text)' :
                     l.s === 'fail' ? 'var(--danger-soft-text)' :
                     'var(--fg-muted)',
              width: 50, flexShrink: 0, textTransform: 'uppercase', fontSize: 10, marginTop: 2,
            }}>{l.s}</span>
            <span style={{ color: 'var(--fg)', flex: 1, whiteSpace: 'pre-wrap' }}>{l.msg}</span>
          </div>
        ))}
        <div style={{ color: 'var(--fg-subtle)', padding: '6px 0', borderTop: '1px dashed var(--border)', marginTop: 8 }}>
          — end of log (truncated · <a href="#" style={{ color: 'var(--brand)' }}>view full</a>) —
        </div>
      </div>
    </div>
  );
}

function EmptyState({ label, icon }) {
  return (
    <div style={{ padding: 60, textAlign: 'center', color: 'var(--fg-muted)' }}>
      <Icon name={icon} size={32} style={{ marginBottom: 12 }}/>
      <div>{label}</div>
    </div>
  );
}

// ============================================================================
// TestOnCommit — all instances for one (commit, test) pair.
// Grouped, toggleable, presettable columns.
// ============================================================================

// Column definitions. group = the section in the picker. default = shown by default.
const COLUMN_DEFS = [
  // Run
  { id: 'computer',  group: 'Run',         label: 'Computer',  default: true,  width: 96,  align: 'left',  format: (i) => i.computerId, mono: true },
  { id: 'variant',   group: 'Run',         label: 'Variant',   default: true,  width: 70,  align: 'left',  format: (i) => i.mark, badge: true },
  { id: 'date',      group: 'Run',         label: 'Date',      default: false, width: 110, align: 'left',  format: (i) => i.date },
  { id: 'threads',   group: 'Run',         label: 'Threads',   default: false, width: 70,  align: 'right', format: (i) => i.threads },
  { id: 'spec',      group: 'Run',         label: 'Spec',      default: false, width: 80,  align: 'left',  format: (i) => i.spec, mono: true },
  { id: 'runtime',   group: 'Run',         label: 'Runtime',   default: true,  width: 90,  align: 'right', format: (i) => i.runtime.toFixed(2) + ' m' },
  { id: 'ram',       group: 'Run',         label: 'RAM',       default: false, width: 80,  align: 'right', format: (i) => i.ram + ' MB' },

  // Output
  { id: 'checksum',  group: 'Output',      label: 'Checksum',  default: true,  width: 100, align: 'left',  format: (i) => i.checksum, mono: true },
  { id: 'modelNumber',group:'Output',      label: 'Model №',   default: false, width: 80,  align: 'right', format: (i) => i.modelNumber },
  { id: 'steps',     group: 'Output',      label: 'Steps',     default: true,  width: 80,  align: 'right', format: (i) => i.steps },
  { id: 'starAge',   group: 'Output',      label: 'Star Age',  default: true,  width: 110, align: 'right', format: (i) => i.starAge },

  // Convergence
  { id: 'cumRetries',     group: 'Convergence', label: 'Cum. Retries',     default: true,  width: 100, align: 'right', format: (i) => i.cumRetries },
  { id: 'retries',        group: 'Convergence', label: 'Retries',          default: false, width: 80,  align: 'right', format: (i) => i.retries },
  { id: 'redos',          group: 'Convergence', label: 'Redos',            default: false, width: 70,  align: 'right', format: (i) => i.redos },
  { id: 'solverIters',    group: 'Convergence', label: 'Solver Iters',     default: false, width: 110, align: 'right', format: (i) => i.solverIters },
  { id: 'solverCallsMade',group: 'Convergence', label: 'Solver Calls',     default: false, width: 110, align: 'right', format: (i) => i.solverCallsMade },
  { id: 'solverCallsFailed', group:'Convergence',label:'Calls Failed',     default: true,  width: 100, align: 'right', format: (i) => i.solverCallsFailed },
  { id: 'logRelE',        group: 'Convergence', label: 'log Rel E',        default: false, width: 90,  align: 'right', format: (i) => i.logRelE },
  { id: 'numRetries',     group: 'Convergence', label: 'Num Retries',      default: false, width: 100, align: 'right', format: (i) => i.numRetries },
  { id: 'inlistRetries',  group: 'Convergence', label: 'Inlist Retries',   default: true,  width: 110, align: 'right', format: (i) => i.inlistRetries },
];

const COLUMN_PRESETS = {
  default: COLUMN_DEFS.filter(d => d.default).map(d => d.id),
  performance: ['computer', 'variant', 'threads', 'spec', 'runtime', 'ram', 'steps', 'checksum'],
  convergence: ['computer', 'variant', 'checksum', 'cumRetries', 'retries', 'redos', 'solverCallsMade', 'solverCallsFailed', 'numRetries', 'inlistRetries'],
  all: COLUMN_DEFS.map(d => d.id),
};

function TestOnCommit({ sha, testId, focusComputerId, commits, onBack, onOpen }) {
  const c = commits.find(x => x.sha === sha);
  const t = TESTS.find(x => x.id === testId);
  const instances = useMemoS(() => getInstancesForTestOnCommit(sha, testId), [sha, testId]);
  const [visibleCols, setVisibleCols] = useStateS(COLUMN_PRESETS.default);
  const [pickerOpen, setPickerOpen] = useStateS(false);
  const [search, setSearch] = useStateS('');
  const [statusFilter, setStatusFilter] = useStateS('all');

  if (!c || !t) return null;

  // Headline: status + checksum summary
  const checksums = [...new Set(instances.map(i => i.checksum))];
  const statuses = [...new Set(instances.map(i => i.status))];
  let testStatusWord, testStatusColor;
  if (statuses.includes('fail') && statuses.includes('pass')) { testStatusWord = 'mixed'; testStatusColor = 'var(--warning-soft-text)'; }
  else if (statuses.includes('fail')) { testStatusWord = 'failing'; testStatusColor = 'var(--danger-soft-text)'; }
  else if (statuses.includes('pending')) { testStatusWord = 'running'; testStatusColor = 'var(--info-soft-text)'; }
  else { testStatusWord = 'passing'; testStatusColor = 'var(--success-soft-text)'; }

  const checksumWord = checksums.length === 1 ? 'one' : checksums.length === 2 ? 'two' : checksums.length === 3 ? 'three' : checksums.length;
  const checksumColor = checksums.length === 1 ? 'var(--success-soft-text)' : 'var(--warning-soft-text)';

  const filteredInstances = instances.filter(i => {
    if (statusFilter !== 'all' && i.status !== statusFilter) return false;
    if (search && !i.computerId.toLowerCase().includes(search.toLowerCase()) && !i.checksum.includes(search)) return false;
    return true;
  });

  return (
    <div style={{ maxWidth: 'var(--maxw)', margin: '0 auto', padding: '20px 32px 60px' }}>
      {/* Breadcrumb */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14, fontSize: 13, color: 'var(--fg-muted)', flexWrap: 'wrap' }}>
        <button className="btn btn-ghost btn-sm" onClick={() => window.appNav('commits')}>
          <Icon name="arrowL" size={12}/> Commits
        </button>
        <span style={{ opacity: 0.5 }}>/</span>
        <button className="btn btn-ghost btn-sm" onClick={onBack}>
          <span className="mono">{c.sha}</span>
        </button>
        <span style={{ opacity: 0.5 }}>/</span>
        <span className="mono" style={{ color: 'var(--fg)' }}>{t.module}/{t.id}</span>
      </div>

      {/* Headline card */}
      <div className="card" style={{ padding: 22, marginBottom: 16 }}>
        <div style={{ fontSize: 22, fontWeight: 500, lineHeight: 1.35, letterSpacing: -0.2 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 10px', background: 'var(--bg-muted)', border: '1px solid var(--border)',
            borderRadius: 8, fontFamily: 'var(--font-mono)', fontSize: 17, fontWeight: 600,
            color: 'var(--fg)',
          }}>
            {t.id} <span style={{ color: 'var(--fg-subtle)', fontSize: 13, fontWeight: 400 }}>({t.module})</span>
          </span>{' '}
          is <strong style={{ color: testStatusColor, fontWeight: 600 }}>{testStatusWord}</strong>{' '}
          in <span className="mono" style={{ color: 'var(--brand)', fontWeight: 600 }}>{c.sha}</span>{' '}
          with <strong style={{ color: checksumColor, fontWeight: 600 }}>{checksumWord} unique checksum{checksums.length === 1 ? '' : 's'}</strong>.
        </div>
        {checksums.length > 1 && (
          <div style={{ marginTop: 10, fontSize: 12, color: 'var(--fg-muted)' }}>
            Bit-for-bit reproducibility broken on this commit. Checksums seen:{' '}
            {checksums.map((cs, i) => (
              <span key={cs} className="mono" style={{ color: 'var(--fg)', marginLeft: i ? 6 : 4 }}>{cs}{i < checksums.length - 1 ? ',' : ''}</span>
            ))}
          </div>
        )}

        {/* Sub-info — commit context, compact */}
        <div style={{ marginTop: 16, paddingTop: 14, borderTop: '1px solid var(--border-subtle)',
          display: 'flex', gap: 18, alignItems: 'center', flexWrap: 'wrap', fontSize: 13, color: 'var(--fg-muted)' }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <CommitAvatar author={c.author} color={c.avatar} size={18}/>
            <strong style={{ color: 'var(--fg)', fontWeight: 500 }}>{c.author}</strong>
          </span>
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1, color: 'var(--fg)' }}>{c.msg}</span>
          <span>{relTime(c.whenISO)}</span>
          <a className="btn btn-sm" href={`https://github.com/MESAHub/mesa/commit/${c.full}`} target="_blank" rel="noreferrer">
            <Icon name="github" size={11}/> GitHub
          </a>
          <button className="btn btn-sm" onClick={onBack}>← All tests on {c.sha}</button>
          <button className="btn btn-sm"><Icon name="clock" size={11}/> History of {t.id}</button>
        </div>
      </div>

      {/* Instances toolbar */}
      <div className="card" style={{ overflow: 'visible' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 12, borderBottom: '1px solid var(--border)', background: 'var(--bg-subtle)', flexWrap: 'wrap' }}>
          <strong style={{ fontSize: 13, color: 'var(--fg)' }}>{instances.length} instances</strong>
          <SearchInput value={search} onChange={setSearch} placeholder="Filter by computer or checksum…"/>
          <SegmentedControl value={statusFilter} onChange={setStatusFilter} options={[
            { v: 'all', label: 'All', count: instances.length },
            { v: 'fail', label: 'Failing', count: instances.filter(i => i.status === 'fail').length, dot: 'danger' },
            { v: 'pass', label: 'Pass', count: instances.filter(i => i.status === 'pass').length, dot: 'success' },
            { v: 'pending', label: 'Running', count: instances.filter(i => i.status === 'pending').length, dot: 'info' },
          ]}/>

          <div style={{ marginLeft: 'auto', position: 'relative' }}>
            <button className="btn btn-sm" onClick={() => setPickerOpen(o => !o)}>
              <Icon name="settings" size={11}/> Columns
              <span style={{ color: 'var(--fg-subtle)', fontSize: 11, marginLeft: 4 }}>{visibleCols.length}/{COLUMN_DEFS.length}</span>
              <Icon name="chevron" size={11}/>
            </button>
            {pickerOpen && (
              <ColumnPicker
                visibleCols={visibleCols} setVisibleCols={setVisibleCols}
                onClose={() => setPickerOpen(false)}
              />
            )}
          </div>
        </div>

        {/* Table — horizontal scroll if needed */}
        <div style={{ overflowX: 'auto' }}>
          <InstancesTable instances={filteredInstances} visibleCols={visibleCols} focusComputerId={focusComputerId}/>
        </div>
      </div>
    </div>
  );
}

function ColumnPicker({ visibleCols, setVisibleCols, onClose }) {
  const ref = useRefS(null);
  useEffectS(() => {
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) onClose(); };
    document.addEventListener('mousedown', h);
    return () => document.removeEventListener('mousedown', h);
  }, [onClose]);

  const grouped = {};
  COLUMN_DEFS.forEach(d => { (grouped[d.group] ||= []).push(d); });

  const toggle = (id) => {
    setVisibleCols(v => v.includes(id) ? v.filter(x => x !== id) : [...v, id]);
  };
  const setPreset = (p) => setVisibleCols([...COLUMN_PRESETS[p]]);
  const currentPreset = Object.entries(COLUMN_PRESETS).find(([k, v]) =>
    v.length === visibleCols.length && v.every(x => visibleCols.includes(x))
  )?.[0];

  return (
    <div ref={ref} style={{
      position: 'absolute', top: 'calc(100% + 6px)', right: 0,
      background: 'var(--bg-elev)', border: '1px solid var(--border)',
      borderRadius: 'var(--r-md)', boxShadow: 'var(--shadow-md)',
      padding: 14, width: 460, zIndex: 50,
    }}>
      {/* Presets */}
      <div style={{ marginBottom: 14 }}>
        <div style={{ fontSize: 10, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.6, marginBottom: 6 }}>Presets</div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {Object.keys(COLUMN_PRESETS).map(p => (
            <button key={p} onClick={() => setPreset(p)} style={{
              padding: '5px 12px', borderRadius: 999, border: '1px solid var(--border)',
              background: currentPreset === p ? 'var(--brand-soft)' : 'var(--bg-elev)',
              color: currentPreset === p ? 'var(--brand-soft-text)' : 'var(--fg-muted)',
              fontSize: 12, fontWeight: 500, cursor: 'pointer', fontFamily: 'inherit',
              textTransform: 'capitalize',
            }}>{p}</button>
          ))}
        </div>
      </div>

      {/* Grouped */}
      {Object.entries(grouped).map(([groupName, cols]) => (
        <div key={groupName} style={{ marginBottom: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div style={{ fontSize: 10, color: 'var(--fg-muted)', textTransform: 'uppercase', letterSpacing: 0.6 }}>{groupName}</div>
            <button onClick={() => {
              const all = cols.every(c => visibleCols.includes(c.id));
              setVisibleCols(v => all ? v.filter(x => !cols.find(c => c.id === x)) : [...new Set([...v, ...cols.map(c => c.id)])]);
            }} style={{ background: 'none', border: 'none', color: 'var(--brand)', fontSize: 10, cursor: 'pointer', fontFamily: 'inherit' }}>
              {cols.every(c => visibleCols.includes(c.id)) ? 'none' : 'all'}
            </button>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 2 }}>
            {cols.map(c => (
              <label key={c.id} style={{
                display: 'flex', alignItems: 'center', gap: 6, padding: '4px 6px',
                cursor: 'pointer', borderRadius: 4, fontSize: 12,
              }}
                onMouseEnter={e => e.currentTarget.style.background = 'var(--bg-muted)'}
                onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                <input type="checkbox" checked={visibleCols.includes(c.id)} onChange={() => toggle(c.id)} style={{ accentColor: 'var(--brand)' }}/>
                <span style={{ color: visibleCols.includes(c.id) ? 'var(--fg)' : 'var(--fg-muted)' }}>{c.label}</span>
              </label>
            ))}
          </div>
        </div>
      ))}

      <div style={{ marginTop: 10, paddingTop: 10, borderTop: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between' }}>
        <button onClick={() => setPreset('default')} className="btn btn-ghost btn-sm">Reset to default</button>
        <span style={{ fontSize: 11, color: 'var(--fg-subtle)' }}>Saved per browser</span>
      </div>
    </div>
  );
}

function InstancesTable({ instances, visibleCols, focusComputerId }) {
  const cols = visibleCols.map(id => COLUMN_DEFS.find(d => d.id === id)).filter(Boolean);
  const totalW = 32 + 160 + cols.reduce((a, c) => a + c.width, 0);
  return (
    <div style={{ minWidth: totalW }}>
      <div role="row" style={{
        display: 'grid',
        gridTemplateColumns: `32px 160px ${cols.map(c => c.width + 'px').join(' ')}`,
        padding: '8px 14px', fontSize: 11, fontWeight: 500, color: 'var(--fg-muted)',
        textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid var(--border)',
        background: 'var(--bg-subtle)',
      }}>
        <div></div>
        <div>Status</div>
        {cols.map(c => <div key={c.id} style={{ textAlign: c.align }}>{c.label}</div>)}
      </div>

      {instances.map((inst) => {
        const isFocus = inst.computerId === focusComputerId;
        return (
          <div key={inst.id} role="row" style={{
            display: 'grid',
            gridTemplateColumns: `32px 160px ${cols.map(c => c.width + 'px').join(' ')}`,
            padding: '10px 14px', alignItems: 'center',
            borderBottom: '1px solid var(--border-subtle)',
            background: isFocus ? 'var(--brand-soft)' : 'transparent',
          }}>
            <StatusDot state={inst.status === 'pass' ? 'all-pass' : inst.status === 'fail' ? 'fail' : inst.status === 'pending' ? 'pending' : 'mixed'}/>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
              <span style={{
                fontFamily: 'var(--font-mono)', fontSize: 12,
                color: inst.status === 'fail' ? 'var(--danger-soft-text)'
                  : inst.status === 'pass' ? 'var(--success-soft-text)'
                  : inst.status === 'pending' ? 'var(--info-soft-text)'
                  : 'var(--fg-muted)',
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{inst.statusLabel}</span>
              {inst.flags.fpe && <Icon name="wrench" size={11} style={{ color: 'var(--warning-soft-text)' }} title="FPE"/>}
              {inst.flags.checksum && <Icon name="neq" size={11} style={{ color: 'var(--warning-soft-text)' }} title="Checksum ≠"/>}
              {inst.flags.inlists_full && <Icon name="plus" size={11} style={{ color: 'var(--info-soft-text)' }} title="Full inlists"/>}
            </div>
            {cols.map(c => {
              const v = c.format(inst);
              const isMixedChecksum = c.id === 'checksum' && [...new Set(instances.map(i => i.checksum))].length > 1;
              return (
                <div key={c.id} style={{
                  textAlign: c.align,
                  fontFamily: c.mono ? 'var(--font-mono)' : 'inherit',
                  fontSize: c.mono ? 12 : 13,
                  fontVariantNumeric: 'tabular-nums',
                  color: isMixedChecksum && inst.flags.checksum ? 'var(--warning-soft-text)' : 'var(--fg)',
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>
                  {c.badge ? <span className="pill pill-muted" style={{ fontSize: 10, fontFamily: 'var(--font-mono)' }}>{v}</span> : v}
                </div>
              );
            })}
          </div>
        );
      })}
      {instances.length === 0 && (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--fg-muted)' }}>No instances match.</div>
      )}
    </div>
  );
}

Object.assign(window, {
  CommitsList, CommitDetail, TestOnCommit, BranchPicker,
});
