import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { selectAuth } from './auth/authProvider';
import './styles.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App auth={selectAuth(import.meta.env)} />
  </StrictMode>,
);
