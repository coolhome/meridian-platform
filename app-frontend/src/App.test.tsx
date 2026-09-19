import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { App } from './App';
import { developmentAuth } from './auth/authProvider';
import type { Api, Dashboard } from './api';

function fakeApi(dashboard: Dashboard): Api {
  return {
    dashboard: vi.fn(async () => dashboard),
    approvers: vi.fn(async () => [{ id: 'bob', name: 'bob', roles: ['Approver'], canApprove: true }]),
    create: vi.fn(),
    decide: vi.fn(async () => dashboard.toApprove[0]),
  };
}

const pending = {
  id: '11111111-1111-1111-1111-111111111111',
  title: 'Laptop',
  requestedBy: 'alice',
  status: 'Pending' as const,
  createdAt: new Date().toISOString(),
  dueAt: null,
  overdue: false,
  approvers: ['bob'],
};

describe('App', () => {
  it('signs in as an approver in development mode and can approve', async () => {
    sessionStorage.clear();
    const api = fakeApi({
      me: { id: 'bob', name: 'bob', roles: ['Approver'], canApprove: true },
      awaitingMyDecision: 1,
      myOpenRequests: 0,
      overdue: 0,
      toApprove: [pending],
      requested: [],
    });

    render(<App auth={developmentAuth} apiFactory={() => api} />);
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() => expect(screen.getByText('Laptop')).toBeInTheDocument());
    expect(screen.getByText('awaiting my decision').previousSibling).toHaveTextContent('1');

    fireEvent.click(screen.getByRole('button', { name: 'Approve' }));
    await waitFor(() => expect(api.decide).toHaveBeenCalledWith(pending.id, 'approved', undefined));
  });

  it('hides the approval queue for plain requesters', async () => {
    sessionStorage.clear();
    const api = fakeApi({
      me: { id: 'alice', name: 'alice', roles: ['Requester'], canApprove: false },
      awaitingMyDecision: 0,
      myOpenRequests: 1,
      overdue: 0,
      toApprove: [],
      requested: [pending],
    });

    render(<App auth={developmentAuth} apiFactory={() => api} />);
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() => expect(screen.getByRole('region', { name: 'My requests' })).toBeInTheDocument());
    expect(screen.queryByRole('region', { name: 'To approve' })).not.toBeInTheDocument();
  });
});
