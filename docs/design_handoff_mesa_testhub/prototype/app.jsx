// MESA Test Hub — app shell (nav + routing + theme + tweaks panel)

const { useState: useStateA, useEffect: useEffectA, useMemo: useMemoA } = React;

// ============================================================================
// Theme controller
// ============================================================================
function useTheme() {
  const [override, setOverride] = useStateA(() => localStorage.getItem('mesa-theme') || 'system');
  const [systemDark, setSystemDark] = useStateA(() => window.matchMedia?.('(prefers-color-scheme: dark)').matches);
  useEffectA(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const h = e => setSystemDark(e.matches);
    mq.addEventListener('change', h);
    return () => mq.removeEventListener('change', h);
  }, []);
  const effective = override === 'system' ? (systemDark ? 'dark' : 'light') : override;
  useEffectA(() => {
    document.documentElement.setAttribute('data-theme', effective);
    localStorage.setItem('mesa-theme', override);
  }, [effective, override]);
  const cycle = () => {
    setOverride(o => o === 'system' ? (effective === 'dark' ? 'light' : 'dark') : (o === 'light' ? 'dark' : o === 'dark' ? 'system' : 'light'));
  };
  return { theme: effective, override, setOverride, cycle };
}

// ============================================================================
// TopNav — global chrome only. Branch picker lives inline in page headers
// where it belongs to the context.
// ============================================================================
function TopNav({ route, theme, cycleTheme }) {
  const fakeUser = false;
  return (
    <header style={{
      position: 'sticky', top: 0, zIndex: 30,
      height: 'var(--nav-h)', background: 'var(--bg-elev)',
      borderBottom: '1px solid var(--border)',
      display: 'flex', alignItems: 'center', gap: 14,
      padding: '0 24px', backdropFilter: 'blur(8px)',
    }}>
      <a href="#" onClick={(e) => { e.preventDefault(); window.appNav('commits'); }}
        style={{ display: 'flex', alignItems: 'center', gap: 10, color: 'var(--fg)', textDecoration: 'none' }}>
        <span style={{ color: 'var(--brand)', display: 'inline-flex' }}>
          <MesaMark size={24}/>
        </span>
        <span style={{ fontSize: 14, fontWeight: 600, letterSpacing: -0.1 }}>
          Test Hub
        </span>
      </a>

      <nav style={{ display: 'flex', gap: 2, marginLeft: 12 }}>
        <NavLink active={route.name === 'commits' || route.name === 'commit' || route.name === 'test'} onClick={() => window.appNav('commits')}>Commits</NavLink>
        <NavLink>Branches</NavLink>
        <NavLink>Computers</NavLink>
        <NavLink>Tests</NavLink>
        <NavLink href="https://docs.mesastar.org" external>Docs</NavLink>
      </nav>

      <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 8 }}>
        <div style={{ width: 260 }}><CommandPalette/></div>
        <button className="btn btn-ghost btn-sm" title="Toggle theme" onClick={cycleTheme}>
          <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={14}/>
        </button>
        <button className="btn btn-ghost btn-sm" title="Notifications"><Icon name="bell" size={14}/></button>
        {fakeUser
          ? <button className="btn btn-sm">EF</button>
          : <button className="btn btn-primary btn-sm">Log in</button>}
      </div>
    </header>
  );
}

function NavLink({ children, active, onClick, href, external }) {
  const style = {
    padding: '7px 10px', borderRadius: 6, fontSize: 13, fontWeight: 500,
    color: active ? 'var(--fg)' : 'var(--fg-muted)',
    background: active ? 'var(--bg-muted)' : 'transparent',
    textDecoration: 'none', cursor: 'pointer', border: 'none', fontFamily: 'inherit',
    display: 'inline-flex', alignItems: 'center', gap: 4,
  };
  if (href) return <a href={href} target={external?'_blank':undefined} rel={external?'noreferrer':undefined} style={style}>{children}{external && <span style={{ fontSize: 9, opacity: 0.6 }}>↗</span>}</a>;
  return <button onClick={onClick} style={style}>{children}</button>;
}

function CommandPalette() {
  return (
    <div style={{ position: 'relative' }}>
      <Icon name="search" size={12} style={{ position: 'absolute', left: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--fg-subtle)' }}/>
      <input type="text" placeholder="Search commits, tests…" style={{
        width: '100%', padding: '6px 36px 6px 28px', background: 'var(--bg-subtle)',
        border: '1px solid var(--border)', borderRadius: 6, fontSize: 12,
        color: 'var(--fg)', outline: 'none', fontFamily: 'inherit',
      }}/>
      <span style={{ position: 'absolute', right: 6, top: '50%', transform: 'translateY(-50%)' }}>
        <span className="kbd">⌘K</span>
      </span>
    </div>
  );
}

// ============================================================================
// Tweaks panel
// ============================================================================
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "fontPairing": "inter-jetbrains",
  "density": "comfortable",
  "showMatrixOnList": true,
  "monoSha": true
}/*EDITMODE-END*/;

function MesaTweaks() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  useEffectA(() => {
    const root = document.documentElement;
    const pairings = {
      'inter-jetbrains':  { sans: "'Inter', system-ui, sans-serif",    mono: "'JetBrains Mono', ui-monospace, monospace" },
      'plex':             { sans: "'IBM Plex Sans', system-ui, sans-serif", mono: "'IBM Plex Mono', ui-monospace, monospace" },
      'geist':            { sans: "'Geist', system-ui, sans-serif",    mono: "'Geist Mono', ui-monospace, monospace" },
      'system':           { sans: "system-ui, -apple-system, sans-serif", mono: "ui-monospace, SFMono-Regular, monospace" },
    };
    const p = pairings[t.fontPairing] || pairings['inter-jetbrains'];
    root.style.setProperty('--font-sans', p.sans);
    root.style.setProperty('--font-mono', p.mono);
    const densMap = {
      'compact':     { nav: '44px' },
      'comfortable': { nav: '52px' },
      'roomy':       { nav: '60px' },
    };
    root.style.setProperty('--nav-h', densMap[t.density]?.nav || '52px');
    root.setAttribute('data-density', t.density);
  }, [t]);

  return (
    <TweaksPanel title="Test Hub Tweaks">
      <TweakSection title="Typography">
        <TweakRadio
          label="Sans pairing"
          value={t.fontPairing}
          onChange={v => setTweak('fontPairing', v)}
          options={[
            { value: 'inter-jetbrains', label: 'Inter + JetBrains' },
            { value: 'plex',  label: 'IBM Plex' },
            { value: 'geist', label: 'Geist' },
            { value: 'system', label: 'System UI' },
          ]}
        />
      </TweakSection>
      <TweakSection title="Layout">
        <TweakRadio
          label="Density"
          value={t.density}
          onChange={v => setTweak('density', v)}
          options={[
            { value: 'compact',     label: 'Compact' },
            { value: 'comfortable', label: 'Comfortable' },
            { value: 'roomy',       label: 'Roomy' },
          ]}
        />
      </TweakSection>
    </TweaksPanel>
  );
}

// ============================================================================
// Router / App
// ============================================================================
function App() {
  const { theme, cycle } = useTheme();
  const [route, setRoute] = useStateA(() => parseHash());
  const [branch, setBranch] = useStateA('main');

  useEffectA(() => {
    const h = () => setRoute(parseHash());
    window.addEventListener('hashchange', h);
    return () => window.removeEventListener('hashchange', h);
  }, []);

  window.appNav = (name, params = {}) => {
    let hash = '#/' + name;
    if (name === 'commit') hash = '#/commit/' + params.sha;
    if (name === 'test')   hash = `#/test/${params.sha}/${params.testId}${params.focus ? '?' + params.focus : ''}`;
    location.hash = hash;
  };

  const onOpen = sha => window.appNav('commit', { sha });
  const onOpenTest = (sha, testId, focusComputerId) => window.appNav('test', { sha, testId, focus: focusComputerId });

  let page;
  if (route.name === 'commits') {
    page = <CommitsList commits={COMMITS} branch={branch} onChangeBranch={setBranch} onOpen={onOpen}/>;
  } else if (route.name === 'commit') {
    page = <CommitDetail sha={route.sha} branch={branch} onChangeBranch={setBranch}
             commits={COMMITS} onOpen={onOpen} onOpenTest={onOpenTest}/>;
  } else if (route.name === 'test') {
    page = <TestOnCommit sha={route.sha} testId={route.testId} focusComputerId={route.focusComputerId}
             commits={COMMITS} onBack={() => window.appNav('commit', { sha: route.sha })} onOpen={onOpen}/>;
  } else {
    page = <CommitsList commits={COMMITS} branch={branch} onChangeBranch={setBranch} onOpen={onOpen}/>;
  }

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg-subtle)', color: 'var(--fg)' }}>
      <TopNav route={route} theme={theme} cycleTheme={cycle}/>
      {page}
      <MesaTweaks/>
    </div>
  );
}

function parseHash() {
  const raw = location.hash.slice(2);
  const [path, query] = raw.split('?');
  const h = path.split('/');
  if (h[0] === 'commit' && h[1]) return { name: 'commit', sha: h[1] };
  if (h[0] === 'test' && h[1] && h[2]) return { name: 'test', sha: h[1], testId: h[2], focusComputerId: query || undefined };
  return { name: 'commits' };
}

// Mount
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App/>);
