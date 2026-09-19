import { useCallback, useEffect, useState } from 'react';
import { ApiError, createApi, type Api, type Dashboard, type Principal } from './api';
import type { AuthProvider, Session } from './auth/authProvider';
import { ApprovalList } from './components/ApprovalList';
import { NewApprovalForm } from './components/NewApprovalForm';

interface Props {
  auth: AuthProvider;
  apiFactory?: (session: Session) => Api;
}

export function App({ auth, apiFactory = (s) => createApi(s) }: Props) {
  const [session, setSession] = useState<Session | null>(null);
  const [api, setApi] = useState<Api | null>(null);
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [approvers, setApprovers] = useState<Principal[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [devUser, setDevUser] = useState('alice');
  const [devApprover, setDevApprover] = useState(false);

  useEffect(() => {
    void auth.restore().then((s) => {
      if (s) {
        setSession(s);
        setApi(apiFactory(s));
      }
    });
  }, [auth, apiFactory]);

  const refresh = useCallback(async () => {
    if (!api) return;
    try {
      const [d, a] = await Promise.all([api.dashboard(), api.approvers()]);
      setDashboard(d);
      setApprovers(a);
      setError(null);
    } catch (e) {
      setError(e instanceof ApiError ? `${e.problem.title ?? e.status}: ${e.message}` : String(e));
    }
  }, [api]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function signIn() {
    const s = await auth.signIn({ user: devUser, roles: devApprover ? ['Requester', 'Approver'] : ['Requester'] });
    setSession(s);
    setApi(apiFactory(s));
  }

  async function signOut() {
    await session?.signOut();
    setSession(null);
    setApi(null);
    setDashboard(null);
  }

  if (!session) {
    return (
      <main className="signin">
        <h1>Meridian Approvals</h1>
        {auth.mode === 'development' && (
          <div className="dev">
            <label>
              User <input value={devUser} onChange={(e) => setDevUser(e.target.value)} />
            </label>
            <label>
              <input type="checkbox" checked={devApprover} onChange={(e) => setDevApprover(e.target.checked)} /> Approver
            </label>
          </div>
        )}
        <button onClick={signIn}>Sign in</button>
      </main>
    );
  }

  return (
    <main>
      <header>
        <h1>Meridian Approvals</h1>
        <div>
          <span>{dashboard?.me.name ?? session.name}</span>
          {dashboard?.me.canApprove && <span className="badge">Approver</span>}
          <button className="secondary" onClick={signOut}>
            Sign out
          </button>
        </div>
      </header>
      {error && <p role="alert">{error}</p>}
      {dashboard && (
        <>
          <section className="tiles" aria-label="Summary">
            <div>
              <strong>{dashboard.awaitingMyDecision}</strong>
              <span>awaiting my decision</span>
            </div>
            <div>
              <strong>{dashboard.myOpenRequests}</strong>
              <span>my open requests</span>
            </div>
            <div>
              <strong>{dashboard.overdue}</strong>
              <span>overdue</span>
            </div>
          </section>
          {dashboard.me.canApprove && (
            <ApprovalList
              title="To approve"
              items={dashboard.toApprove}
              canDecide
              onDecide={async (id, decision, comment) => {
                try {
                  await api!.decide(id, decision, comment);
                  await refresh();
                } catch (e) {
                  setError(e instanceof Error ? e.message : String(e));
                }
              }}
            />
          )}
          <ApprovalList title="My requests" items={dashboard.requested} />
          <NewApprovalForm
            approvers={approvers}
            onSubmit={async (body) => {
              await api!.create(body);
              await refresh();
            }}
          />
        </>
      )}
      <footer className="muted">v{import.meta.env.VITE_APP_VERSION ?? 'local'}</footer>
    </main>
  );
}
