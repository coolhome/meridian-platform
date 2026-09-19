import { useState, type FormEvent } from 'react';
import type { Principal } from '../api';

interface Props {
  approvers: Principal[];
  onSubmit: (body: { title: string; description?: string; approvers: string[]; dueAt?: string | null }) => Promise<void>;
}

export function NewApprovalForm({ approvers, onSubmit }: Props) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [dueAt, setDueAt] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await onSubmit({ title, description, approvers: selected, dueAt: dueAt ? new Date(dueAt).toISOString() : null });
      setTitle('');
      setDescription('');
      setSelected([]);
      setDueAt('');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} aria-label="New approval">
      <h2>New request</h2>
      <label>
        Title
        <input value={title} onChange={(e) => setTitle(e.target.value)} required maxLength={200} />
      </label>
      <label>
        Description
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2} />
      </label>
      <label>
        Approvers
        <select
          multiple
          value={selected}
          onChange={(e) => setSelected(Array.from(e.target.selectedOptions, (o) => o.value))}
          required
        >
          {approvers.map((a) => (
            <option key={a.id} value={a.name}>
              {a.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        Due
        <input type="datetime-local" value={dueAt} onChange={(e) => setDueAt(e.target.value)} />
      </label>
      {error && <p role="alert">{error}</p>}
      <button type="submit" disabled={busy || selected.length === 0}>
        Submit
      </button>
    </form>
  );
}
