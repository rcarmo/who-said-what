#!/usr/bin/env python3
"""Sequential, offline benchmark of a packaged Who Said What app."""
import argparse
import json
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('input', type=Path)
parser.add_argument('--app', type=Path, default=Path('WhoSaidWhat.app'))
parser.add_argument('--output', type=Path, default=Path('benchmarks'))
parser.add_argument('--primary-language', default='auto', help='Base-language hint, e.g. en, es, pt or it')
parser.add_argument('--backends', nargs='+', choices=['apple', 'voz'], default=['apple', 'voz'])
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
executable = args.app.resolve() / 'Contents/MacOS/WhoSaidWhat'
probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'a:0', '-show_entries', 'stream=duration', '-of', 'json', str(args.input.resolve())]))
duration = float(probe['streams'][0]['duration'])
report = {'input': args.input.name, 'audio_seconds': duration, 'started': datetime.now().astimezone().isoformat(),
          'network': 'denied by sandbox-exec', 'primary_language': args.primary_language, 'results': []}

def save():
    (args.output / 'results.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')

for backend in args.backends:
    output = args.output.resolve() / (backend + '.vtt')
    log = args.output.resolve() / (backend + '.stderr.log')
    started = time.perf_counter()
    print(f'Starting {backend}: {duration / 60:.1f} minutes of audio', flush=True)
    command = ['/usr/bin/time', '-l', 'sandbox-exec', '-p', '(version 1) (allow default) (deny network*)',
               str(executable), '--print', str(args.input.resolve()), '--backend', backend,
               '--primary-language', args.primary_language, '--output', str(output)]
    with log.open('w') as stderr:
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=stderr)
        while True:
            try:
                process.wait(timeout=10)
                break
            except subprocess.TimeoutExpired:
                lines = log.read_text(errors='replace').strip().splitlines()
                print(f'{backend}: {time.perf_counter() - started:.0f}s elapsed' + (f' · {lines[-1]}' if lines else ''), flush=True)
    elapsed = time.perf_counter() - started
    text = log.read_text(errors='replace')
    stats = re.search(r'(\d+) speakers, (\d+) words · Who: ([\d.]+)s.*speech to text: ([\d.]+)s', text)
    decoded = re.search(r'Audio decoded: ([\d.]+)s', text)
    effective_duration = float(decoded[1]) if decoded else duration
    memory = re.search(r'(\d+)\s+maximum resident set size', text)
    result = {'backend': backend, 'exit_code': process.returncode, 'wall_seconds': round(elapsed, 3),
              'wall_realtime_factor': round(effective_duration / elapsed, 2) if process.returncode == 0 else None, 'decoded_audio_seconds': effective_duration, 'log': str(log)}
    if stats:
        result.update(speakers=int(stats[1]), words=int(stats[2]), who_seconds=float(stats[3]), asr_seconds=float(stats[4]))
    if memory:
        result['peak_rss_mib'] = round(int(memory[1]) / 1024**2, 1)
    if process.returncode == 0:
        vtt = output.read_text()
        result['vtt_cues'] = vtt.count(' --> ')
        result['attributed_cues'] = len(re.findall(r'<v [^>]+>', vtt))
        result['vtt'] = str(output)
        assert result['vtt_cues'] == result['attributed_cues'] > 0, 'Every cue must carry attribution'
    else:
        result['error'] = next((line for line in text.splitlines() if line.startswith('error:')), text[-2000:])
    report['results'].append(result)
    save()
    print(json.dumps(result, ensure_ascii=False), flush=True)
report['finished'] = datetime.now().astimezone().isoformat()
save()
print(f'Saved {args.output.resolve() / "results.json"}', flush=True)
