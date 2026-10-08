'use strict';
// ════════════════════════════════════════════════════════════════════════════
// 2027 rollover Package C: disposable local PostgreSQL for the hermetic server tests.
//
// A throwaway cluster in a fresh temp directory, reachable only through a Unix socket
// (listen_addresses=''), holding synthetic data only. It never connects to Supabase, staging or
// production, and is deleted on stop(). Requires a local PostgreSQL server (Homebrew
// postgresql@17; PG_BIN overrides the binary directory).
//
// The schema is the repository's own SQL: each base object is extracted verbatim from the
// migration file that created it (BASE_OBJECTS), plus the stand-ins in
// fixtures/rollover/server/standins.sql for the Supabase pieces Package C does not test.
// ════════════════════════════════════════════════════════════════════════════
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync, spawn } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const PG_BIN = process.env.PG_BIN || '/opt/homebrew/opt/postgresql@17/bin';
const bin = n => path.join(PG_BIN, n);

// Base objects as deployed, in dependency order: [file, first line of the statement, end marker].
// The extract runs from the first line up to and including the first line matching the end marker.
const BASE_OBJECTS = [
  ['docs/phase-5d-1-migration.sql', 'CREATE OR REPLACE FUNCTION fn_set_updated_at()', /^\$\$;$/],
  ['docs/phase-5f-1-migration.sql', 'ALTER TABLE weekly_reconciliations', /;$/],
  ['docs/phase-5f-1-migration.sql', 'CREATE TABLE cash_commitments (', /^\);$/],
  ['docs/phase-5f-1-migration.sql', 'CREATE OR REPLACE FUNCTION fn_cash_commitments_set_updated()', /^\$\$;$/],
  ['docs/phase-5f-1-migration.sql', 'CREATE TRIGGER trg_cash_commitments_updated', /;$/],
  ['docs/phase-5f-1-migration.sql', 'CREATE OR REPLACE FUNCTION validate_commitment_state(', /^\$\$;$/],
  ['docs/phase-5f-1-migration.sql', 'CREATE OR REPLACE FUNCTION save_reconciliation_with_commitments(', /^\$\$;$/],
  ['docs/phase-5g-1c-2-prod-migration.sql', 'CREATE TABLE public.goal_funding_snapshots (', /^\);$/],
  ['docs/phase-5g-1c-2-prod-migration.sql', 'CREATE TRIGGER set_goal_funding_snapshots_updated_at', /;$/],
  ['docs/phase-5g-1c-2-prod-migration.sql', 'CREATE FUNCTION public.save_goal_funding_snapshots(', /^END \$\$;$/],
  ['docs/phase-5g-1d-migration.sql', 'CREATE FUNCTION public.save_weekly_closeout_with_snapshots(', /^END \$\$;$/],
  ['docs/phase-5g-1d-migration.sql', 'CREATE FUNCTION public.correct_goal_funding_snapshot(', /^END \$\$;$/],
];

function extract(file, first, end) {
  const lines = fs.readFileSync(path.join(REPO, file), 'utf8').split('\n');
  const i = lines.findIndex(l => l.startsWith(first));
  if (i < 0) throw new Error('base object not found: ' + file + ': ' + first);
  for (let j = i; j < lines.length; j++) if (end.test(lines[j])) return lines.slice(i, j + 1).join('\n');
  throw new Error('base object has no end: ' + file + ': ' + first);
}
function baseSql() {
  return BASE_OBJECTS.map(([f, first, end]) => '-- base: ' + f + '\n' + extract(f, first, end)).join('\n\n') + '\n';
}

// Production md5(pg_get_functiondef) pins recorded in the repository (5G-1D operator package
// 2026-07-18 and the AU-11 D3 baseline). A match proves the repository source is the deployed body.
const RECORDED_PROD_PINS = {
  'public.save_weekly_closeout_with_snapshots(int,int,numeric,numeric,numeric,numeric,numeric,text,jsonb,jsonb,jsonb,text,int)': 'e2a112b376dc32c43e1615e4a4abf24a',
  'public.save_reconciliation_with_commitments(int,int,numeric,numeric,numeric,numeric,numeric,text,timestamptz,jsonb,jsonb)': '1bfde751ac647c5e9a25ba168d08150c',
  'public.save_goal_funding_snapshots(int,int,jsonb)': '154231b3f180349ec328f08ccbe77076',
};

function run(cmd, args, opt) {
  const r = spawnSync(cmd, args, Object.assign({ encoding: 'utf8' }, opt || {}));
  if (r.error) throw r.error;
  return r;
}

function start() {
  if (!fs.existsSync(bin('postgres'))) throw new Error('no local PostgreSQL server at ' + PG_BIN + ' (set PG_BIN)');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hfos-pgc-'));
  const data = path.join(dir, 'data'), sock = dir;
  let r = run(bin('initdb'), ['-D', data, '-U', 'postgres', '-A', 'trust', '--no-instructions', '-E', 'UTF8', '--locale=C']);
  if (r.status !== 0) throw new Error('initdb failed: ' + r.stderr);
  // LC_ALL is required on macOS, or the postmaster refuses to start ("became multithreaded").
  r = run(bin('pg_ctl'), ['-D', data, '-l', path.join(dir, 'log'), '-w', '-o', "-k '" + sock + "' -c listen_addresses='' -c fsync=off -c deadlock_timeout=200ms", 'start'],
    { env: Object.assign({}, process.env, { LC_ALL: 'C' }) });
  if (r.status !== 0) {
    const log = fs.existsSync(path.join(dir, 'log')) ? fs.readFileSync(path.join(dir, 'log'), 'utf8') : '';
    fs.rmSync(dir, { recursive: true, force: true });
    throw new Error('pg_ctl start failed: ' + r.stderr + log);
  }
  const db = {
    dir, sock,
    version: null,
    stop() { run(bin('pg_ctl'), ['-D', data, '-m', 'immediate', 'stop']); fs.rmSync(dir, { recursive: true, force: true }); },
    psqlArgs(dbname) { return ['-h', sock, '-U', 'postgres', '-d', dbname || 'hfos', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']; },
    // Synchronous SQL. Returns { ok, out, err }. Never throws on a SQL error.
    sql(text, dbname) {
      const r2 = run(bin('psql'), db.psqlArgs(dbname), { input: text });
      return { ok: r2.status === 0, out: (r2.stdout || '').trim(), err: (r2.stderr || '').trim() };
    },
    // Asynchronous session (for the two-session tests). Resolves { ok, out, err, ms }.
    session(text, dbname) {
      return new Promise(resolve => {
        const t0 = Date.now();
        const p = spawn(bin('psql'), db.psqlArgs(dbname));
        let out = '', err = '';
        p.stdout.on('data', d => { out += d; }); p.stderr.on('data', d => { err += d; });
        p.on('close', code => resolve({ ok: code === 0, out: out.trim(), err: err.trim(), ms: Date.now() - t0 }));
        p.stdin.end(text);
      });
    },
  };
  const c = db.sql('CREATE DATABASE hfos;', 'postgres');
  if (!c.ok) { db.stop(); throw new Error('createdb failed: ' + c.err); }
  db.version = db.sql('SHOW server_version;').out;
  return db;
}

const STANDINS = path.join(REPO, 'fixtures', 'rollover', 'server', 'standins.sql');

// Build a database holding the deployed base (and, optionally, more SQL on top) as a template, so
// each test can clone a fresh copy cheaply.
function buildTemplate(db, name, extraSql) {
  let r = db.sql('CREATE DATABASE ' + name + ';', 'postgres');
  if (!r.ok) throw new Error(r.err);
  r = db.sql(fs.readFileSync(STANDINS, 'utf8') + '\n' + baseSql(), name);
  if (!r.ok) throw new Error('base load failed: ' + r.err);
  if (extraSql) { r = db.sql(extraSql, name); if (!r.ok) throw new Error('extra SQL failed: ' + r.err); }
  return name;
}
let _n = 0;
function cloneFrom(db, template) {
  const name = 't' + (++_n) + '_' + process.pid;
  const r = db.sql('CREATE DATABASE ' + name + ' TEMPLATE ' + template + ';', 'postgres');
  if (!r.ok) throw new Error(r.err);
  return name;
}

module.exports = { start, baseSql, extract, BASE_OBJECTS, RECORDED_PROD_PINS, buildTemplate, cloneFrom, PG_BIN };
