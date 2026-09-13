import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import process from 'node:process';

// The entry points are JavaScript only because `runs.using` accepts nothing
// else; the work itself lives in the shell script each one names.
export function runScript(name) {
  const script = join(import.meta.dirname, name);
  const { status, error } = spawnSync('bash', [script], { stdio: 'inherit' });

  if (error) {
    console.log(`::error::cannot run ${name}: ${error.message}`);
  }

  process.exit(status ?? 1);
}
