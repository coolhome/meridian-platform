import { PublicClientApplication, type AccountInfo } from '@azure/msal-browser';

export interface Session {
  name: string;
  /** Headers to attach to every BFF call. */
  headers(): Promise<Record<string, string>>;
  signOut(): Promise<void>;
}

export interface AuthProvider {
  readonly mode: 'entra' | 'development';
  signIn(options?: { user?: string; roles?: string[] }): Promise<Session>;
  restore(): Promise<Session | null>;
}

const DEV_KEY = 'meridian.dev.session';

/** Development mode: identity is whatever the developer types; services must run with Meridian:Auth:Mode=Development. */
export const developmentAuth: AuthProvider = {
  mode: 'development',
  async signIn({ user = 'alice', roles = [] } = {}) {
    sessionStorage.setItem(DEV_KEY, JSON.stringify({ user, roles }));
    return devSession(user, roles);
  },
  async restore() {
    const raw = sessionStorage.getItem(DEV_KEY);
    if (!raw) return null;
    const { user, roles } = JSON.parse(raw) as { user: string; roles: string[] };
    return devSession(user, roles);
  },
};

function devSession(user: string, roles: string[]): Session {
  return {
    name: user,
    async headers() {
      const h: Record<string, string> = { 'X-Meridian-User': user };
      if (roles.length) h['X-Meridian-Roles'] = roles.join(',');
      return h;
    },
    async signOut() {
      sessionStorage.removeItem(DEV_KEY);
    },
  };
}

export function createEntraAuth(env: ImportMetaEnv): AuthProvider {
  const scope = env.VITE_ENTRA_BFF_SCOPE ?? 'api://meridian-bff/access_as_user';
  const msal = new PublicClientApplication({
    auth: {
      clientId: env.VITE_ENTRA_CLIENT_ID ?? '',
      authority: `https://login.microsoftonline.com/${env.VITE_ENTRA_TENANT_ID ?? 'common'}`,
      redirectUri: window.location.origin,
    },
    cache: { cacheLocation: 'sessionStorage' },
  });
  const ready = msal.initialize();

  const session = (account: AccountInfo): Session => ({
    name: account.username,
    async headers() {
      const result = await msal.acquireTokenSilent({ scopes: [scope], account });
      return { Authorization: `Bearer ${result.accessToken}` };
    },
    async signOut() {
      await msal.logoutPopup({ account });
    },
  });

  return {
    mode: 'entra',
    async signIn() {
      await ready;
      const result = await msal.loginPopup({ scopes: [scope] });
      return session(result.account);
    },
    async restore() {
      await ready;
      const [account] = msal.getAllAccounts();
      return account ? session(account) : null;
    },
  };
}

export function selectAuth(env: ImportMetaEnv): AuthProvider {
  return env.VITE_AUTH_MODE === 'development' ? developmentAuth : createEntraAuth(env);
}
