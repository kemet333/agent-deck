// Agent Bar · Agentes: the board page inside the app (BoardWindow.swift). Same view as the Diego OS board.
import {createRoot} from 'react-dom/client';
import {TableroView} from './Board';
import './standalone.css';

createRoot(document.getElementById('root')!).render(<div className="jarvis view-agents"><TableroView/></div>);
