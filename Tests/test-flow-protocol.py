import concurrent.futures
import json
import pathlib
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1])
count = 0

def invoke(mode, folder, event=None):
    result = subprocess.run([str(binary), mode, str(folder)], input=json.dumps(event or {}), text=True, capture_output=True, check=True)
    return json.loads(result.stdout)

def event(kind='Stop', **extra):
    return {'hook_event_name': kind, 'session_id': 'synthetic-chat', 'cwd': '/synthetic-project', 'turn_id': 'synthetic-turn', 'last_assistant_message': 'synthetic completion', 'stop_hook_active': False, **extra}

def check(condition, title):
    global count
    assert condition, title
    count += 1
    print('PASS', title)

with tempfile.TemporaryDirectory(prefix='agent-deck-flow-protocol-', dir='/private/tmp') as temp:
    folder = pathlib.Path(temp)
    invoke('seed', folder)
    for number, message in enumerate(['  primero\ncon detalles  ', 'segundo', 'tercero']):
        result = invoke('event', folder, event(turn_id=f'turn-{number}', last_assistant_message=f'result-{number}')) if number else invoke('event', folder, event())
        check(result == {'decision': 'block', 'reason': message}, f'process protocol preserves exact ordered message {number+1}')
        invoke('event', folder, event('UserPromptSubmit', prompt=message, turn_id=f'turn-{number+1}'))
    result = invoke('event', folder, event(turn_id='turn-3', last_assistant_message='last result'))
    check(result == {}, 'last response emits no extra continuation')
    state = invoke('read', folder)
    check(state['run']['issued'] == 3 and state['run']['state'] == 'completed', 'count and completion persist across separate helper processes')
    check('last result' not in (folder/'state.json').read_text(), 'raw completion text does not enter persistent state')

with tempfile.TemporaryDirectory(prefix='agent-deck-flow-race-', dir='/private/tmp') as temp:
    folder = pathlib.Path(temp)
    invoke('seed', folder)
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        outputs = list(pool.map(lambda _: invoke('event', folder, event()), range(12)))
    check(sum(result.get('decision') == 'block' for result in outputs) == 1, 'twelve concurrent processes emit a duplicated completion only once')
    state = invoke('read', folder)
    check(state['run']['issued'] == 1 and state['run']['state'] == 'paused', 'cross-process locking preserves finite progress during replay')
    invoke('event', folder, event('UserPromptSubmit', prompt='OTHER PRIVATE SYNTHETIC INPUT'))
    check('OTHER PRIVATE SYNTHETIC INPUT' not in (folder/'state.json').read_text(), 'unrelated user prompt is not saved by hook protocol')

print(f'FLOW_PROTOCOL_OK {count} — temporary synthetic state only; no installed hooks or model calls')
