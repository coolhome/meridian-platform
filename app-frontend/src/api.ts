import type { Session } from './auth/authProvider';

export interface Principal {
  id: string;
  name: string;
  roles: string[];
  canApprove: boolean;
}

export interface Approval {
  id: string;
  title: string;
  requestedBy: string;
  status: 'Pending' | 'Approved' | 'Rejected';
  createdAt: string;
  dueAt: string | null;
  overdue: boolean;
  approvers: string[];
}

export interface Dashboard {
  me: Principal;
  awaitingMyDecision: number;
  myOpenRequests: number;
  overdue: number;
  toApprove: Approval[];
  requested: Approval[];
}

export interface ProblemDetails {
  title?: string;
  detail?: string;
  status?: number;
  correlationId?: string;
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly problem: ProblemDetails,
  ) {
    super(problem.detail ?? problem.title ?? `HTTP ${status}`);
  }
}

export function createApi(session: Session, baseUrl = import.meta.env.VITE_API_BASE_URL ?? '') {
  async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers = { 'Content-Type': 'application/json', ...(await session.headers()), ...(init.headers ?? {}) };
    const res = await fetch(`${baseUrl}/api${path}`, { ...init, headers });
    if (!res.ok) {
      let problem: ProblemDetails = { status: res.status };
      try {
        problem = (await res.json()) as ProblemDetails;
      } catch {
        /* non-JSON error body */
      }
      throw new ApiError(res.status, problem);
    }
    return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
  }

  return {
    dashboard: () => call<Dashboard>('/dashboard'),
    approvers: () => call<Principal[]>('/approvers'),
    create: (body: { title: string; description?: string; approvers: string[]; dueAt?: string | null }) =>
      call<Approval>('/approvals', { method: 'POST', body: JSON.stringify(body) }),
    decide: (id: string, decision: 'approved' | 'rejected', comment?: string) =>
      call<Approval>(`/approvals/${id}/decision`, { method: 'POST', body: JSON.stringify({ decision, comment }) }),
  };
}

export type Api = ReturnType<typeof createApi>;
