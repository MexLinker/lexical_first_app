const express = require('express');
const dotenv = require('dotenv');
const mysql = require('mysql2/promise');
const cors = require('cors');

dotenv.config();

const app = express();
app.use(cors({ origin: '*'}));
app.use(express.json());
const PORT = process.env.PORT || 3000;

const DB_HOST = process.env.DB_HOST;
const DB_PORT = Number(process.env.DB_PORT || 3306);
const DB_USER = process.env.DB_USER;
const DB_PASS = process.env.DB_PASS;
const DB_NAME = process.env.DB_NAME || '';

if (!DB_HOST || !DB_USER) {
  console.error('Missing DB environment configuration. Please set DB_HOST and DB_USER in .env');
  process.exit(1);
}

const pool = mysql.createPool({
  host: DB_HOST,
  port: DB_PORT,
  user: DB_USER,
  password: DB_PASS,
  waitForConnections: true,
  connectionLimit: 5,
  queueLimit: 0,
  multipleStatements: false,
});

// Candidate columns heuristics for lexical search
const WORD_COLUMNS = ['word', 'term', 'lemma', 'headword', 'entry', 'name'];
const DEF_COLUMNS = ['definition', 'meaning', 'gloss', 'description', 'explanation'];
const EX_COLUMNS = ['example', 'usage', 'sentence', 'samples'];

// Cache inspection summary in memory
let inspectionSummary = {
  databases: [],
  candidates: [],
};

async function inspectSchema() {
  const conn = await pool.getConnection();
  try {
    const [dbs] = await conn.query('SHOW DATABASES');
    const dbNames = dbs.map((row) => row.Database);
    const filteredDbNames = (DB_NAME ? [DB_NAME] : dbNames).filter(
      (d) => !['information_schema', 'mysql', 'performance_schema', 'sys'].includes(d)
    );

    console.log('Databases found:', dbNames.join(', '));
    if (DB_NAME) {
      console.log('Using specific database from .env DB_NAME =', DB_NAME);
    }

    for (const db of filteredDbNames) {
      const [tables] = await conn.query(`SHOW TABLES FROM \`${db}\``);
      const tableKey = Object.keys(tables[0] || {}).find((k) => k.startsWith(`Tables_in_${db}`));
      const tableNames = tables.map((row) => row[tableKey]).filter(Boolean);

      console.log(`\nDatabase: ${db}`);
      console.log(`Tables (${tableNames.length}):`, tableNames.join(', '));

      for (const table of tableNames) {
        try {
          const [desc] = await conn.query(`DESCRIBE \`${db}\`.\`${table}\``);
          const cols = desc.map((c) => c.Field.toLowerCase());
          const hasWord = WORD_COLUMNS.some((c) => cols.includes(c));
          const hasDef = DEF_COLUMNS.some((c) => cols.includes(c));
          const hasEx = EX_COLUMNS.some((c) => cols.includes(c));

          // Log concise description for this table
          console.log(`- ${table}: columns = ${cols.join(', ')}`);

          if (hasWord && (hasDef || hasEx)) {
            const wordCol = WORD_COLUMNS.find((c) => cols.includes(c));
            const defCols = DEF_COLUMNS.filter((c) => cols.includes(c));
            const exCols = EX_COLUMNS.filter((c) => cols.includes(c));
            inspectionSummary.candidates.push({
              db,
              table,
              wordCol,
              defCols,
              exCols,
              cols,
            });
          }
        } catch (e) {
          console.warn(`DESCRIBE ${db}.${table} failed:`, e.message);
        }
      }
    }
    inspectionSummary.databases = filteredDbNames;

    console.log('\n==== Lexical candidate tables summary ====');
    if (inspectionSummary.candidates.length === 0) {
      console.log('No obvious candidate tables found. The /api/search will attempt a fallback lookup.');
    } else {
      for (const c of inspectionSummary.candidates) {
        console.log(`* ${c.db}.${c.table} | word: ${c.wordCol} | defs: ${c.defCols.join(', ')} | examples: ${c.exCols.join(', ')}`);
      }
    }
    console.log('=========================================\n');
  } finally {
    conn.release();
  }
}

app.get('/api/search', async (req, res) => {
  const word = (req.query.word || '').toString().trim();
  if (!word) {
    return res.status(400).json({ error: 'Missing required query parameter: word' });
  }

  const conn = await pool.getConnection();
  try {
    const results = [];

    // Prefer candidates identified during inspection
    for (const cand of inspectionSummary.candidates) {
      const { db, table, wordCol } = cand;
      try {
        const [rows] = await conn.query(
          `SELECT * FROM \`${db}\`.\`${table}\` WHERE LOWER(\`${wordCol}\`) = LOWER(?) LIMIT 50`,
          [word]
        );
        for (const row of rows) {
          const defs = cand.defCols.map((c) => row[c]).filter(Boolean);
          const exs = cand.exCols.map((c) => row[c]).filter(Boolean);
          results.push({
            source: `${db}.${table}`,
            word: row[wordCol],
            definitions: defs,
            examples: exs,
            row,
          });
        }
      } catch (e) {
        console.warn(`Query error on ${db}.${table}:`, e.message);
      }
    }

    // Fallback: if no candidates found, try searching broadly across all DBs/tables
    if (results.length === 0) {
      const [dbs] = await conn.query('SHOW DATABASES');
      const dbNames = dbs.map((row) => row.Database).filter(
        (d) => !['information_schema', 'mysql', 'performance_schema', 'sys'].includes(d)
      );
      for (const db of dbNames) {
        const [tables] = await conn.query(`SHOW TABLES FROM \`${db}\``);
        const tableKey = Object.keys(tables[0] || {}).find((k) => k.startsWith(`Tables_in_${db}`));
        const tableNames = tables.map((row) => row[tableKey]).filter(Boolean);
        for (const table of tableNames) {
          try {
            const [desc] = await conn.query(`DESCRIBE \`${db}\`.\`${table}\``);
            const cols = desc.map((c) => c.Field.toLowerCase());
            const possibleWordCol = WORD_COLUMNS.find((c) => cols.includes(c));
            if (!possibleWordCol) continue;
            const [rows] = await conn.query(
              `SELECT * FROM \`${db}\`.\`${table}\` WHERE LOWER(\`${possibleWordCol}\`) = LOWER(?) LIMIT 25`,
              [word]
            );
            for (const row of rows) {
              const defs = DEF_COLUMNS.map((c) => row[c]).filter(Boolean);
              const exs = EX_COLUMNS.map((c) => row[c]).filter(Boolean);
              results.push({
                source: `${db}.${table}`,
                word: row[possibleWordCol],
                definitions: defs,
                examples: exs,
                row,
              });
            }
          } catch (e) {
            // ignore noisy errors
          }
        }
      }
    }

    if (results.length === 0) {
      return res.status(404).json({ word, results: [], message: 'Not found' });
    }
    return res.json({ word, count: results.length, results });
  } catch (err) {
    console.error('Search error:', err.message);
    return res.status(500).json({ error: 'Internal server error' });
  } finally {
    conn.release();
  }
});

app.get('/api/health', async (req, res) => {
  try {
    const conn = await pool.getConnection();
    await conn.query('SELECT 1');
    conn.release();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

(async () => {
  try {
    console.log('Connecting to MySQL…');
    const conn = await pool.getConnection();
    await conn.ping();
    conn.release();
    console.log('Connected. Inspecting schema…');
    await inspectSchema();
  } catch (e) {
    console.error('Failed to connect or inspect schema:', e.message);
  }

  app.listen(PORT, () => {
    console.log(`Backend server listening on http://localhost:${PORT}`);
  });
})();