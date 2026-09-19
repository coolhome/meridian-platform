import { useState } from 'react';
import type { Approval } from '../api';

interface Props {
  title: string;
  items: Approval[];
  canDecide?: boolean;
  onDecide?: (id: string, decision: 'approved' | 'rejected', comment?: string) => Promise<void>;
}

export function ApprovalList({ title, items, canDecide = false, onDecide }: Props) {
  const [busy, setBusy] = useState<string | null>(null);
  const [comments, setComments] = useState<Record<string, string>>({});

  async function decide(id: string, decision: 'approved' | 'rejected') {
    if (!onDecide) return;
    setBusy(id);
    try {
      await onDecide(id, decision, comments[id]);
    } finally {
      setBusy(null);
    }
  }

  return (
    <section aria-label={title}>
      <h2>{title}</h2>
      {items.length === 0 ? (
        <p className="muted">Nothing here.</p>
      ) : (
        <ul className="approvals">
          {items.map((a) => (
            <li key={a.id} className={a.overdue ? 'overdue' : undefined}>
              <div>
                <strong>{a.title}</strong> <span className={`status status-${a.status.toLowerCase()}`}>{a.status}</span>
                <div className="muted">
                  by {a.requestedBy} · approvers {a.approvers.join(', ')}
                  {a.dueAt ? ` · due ${new Date(a.dueAt).toLocaleString()}` : ''}
                  {a.overdue ? ' · OVERDUE' : ''}
                </div>
              </div>
              {canDecide && a.status === 'Pending' && (
                <div className="actions">
                  <input
                    aria-label={`Comment for ${a.title}`}
                    placeholder="Comment (optional)"
                    value={comments[a.id] ?? ''}
                    onChange={(e) => setComments({ ...comments, [a.id]: e.target.value })}
                  />
                  <button disabled={busy === a.id} onClick={() => decide(a.id, 'approved')}>
                    Approve
                  </button>
                  <button disabled={busy === a.id} className="secondary" onClick={() => decide(a.id, 'rejected')}>
                    Reject
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
