// Builds the board page into Resources/board (index.html, board.js, board.css), copied into the app by build.sh.
// Dependencies (react, react-dom, @xterm/xterm, @xterm/addon-fit, lucide-react, esbuild) come from BOARD_DEPS, a folder
// with them in node_modules (by default the Diego OS checkout, whose board this page is).
import path from 'node:path';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const here = path.dirname(fileURLToPath(import.meta.url));
const deps = process.env.BOARD_DEPS || path.join(process.env.HOME, 'Diego-Operating-System/alfred-os');
const require = createRequire(path.join(deps, 'package.json'));
const {build} = require('esbuild');
const out = path.join(here, '..', 'Resources', 'board');
fs.mkdirSync(out, {recursive: true});
await build({entryPoints: [path.join(here, 'src/main.tsx')], outfile: path.join(out, 'board.js'), bundle: true, minify: true, format: 'iife',
  jsx: 'automatic', nodePaths: [path.join(deps, 'node_modules')], define: {'process.env.NODE_ENV': '"production"'}, loader: {'.css': 'css'}, logLevel: 'warning'});
fs.copyFileSync(path.join(here, 'index.html'), path.join(out, 'index.html'));
console.log('board →', out, fs.readdirSync(out).join(' '));
