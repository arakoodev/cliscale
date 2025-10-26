import { newDb, DataType } from 'pg-mem';
import { randomUUID } from 'crypto';

// Create in-memory database
const db = newDb();

// Register the uuid-ossp extension
db.registerExtension('uuid-ossp', (schema) => {
  schema.registerFunction({
    name: 'uuid_generate_v4',
    returns: DataType.uuid,
    implementation: randomUUID,
  });
});

// Run migrations by creating tables directly
db.public.none(`
  CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

  CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id TEXT NOT NULL,
    job_name TEXT NOT NULL UNIQUE,
    pod_name TEXT,
    pod_ip TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_sessions_owner ON sessions(owner_user_id);
  CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);

  CREATE TABLE IF NOT EXISTS token_jti (
    jti TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_jti_expires ON token_jti(expires_at);
`);

// Mock knex to use pg-mem
jest.mock('knex', () => {
  return jest.fn(() => {
    // Create a Knex-like query builder interface
    const knexMock: any = (tableName: string) => {
      const queryBuilder = {
        _tableName: tableName,
        _wheres: [] as any[],
        _updates: {} as any,
        _inserts: [] as any[],

        where(conditions: any) {
          this._wheres.push(conditions);
          return this;
        },

        first() {
          const whereClause = this._wheres.length > 0
            ? 'WHERE ' + this._wheres.map(w => {
                return Object.entries(w).map(([k, v]) =>
                  `${k} = '${String(v).replace(/'/g, "''")}'`
                ).join(' AND ');
              }).join(' AND ')
            : '';

          const sql = `SELECT * FROM ${this._tableName} ${whereClause} LIMIT 1`;
          const result = db.public.query(sql);
          return result.rows[0] || null;
        },

        async update(updates: any) {
          const setClause = Object.entries(updates).map(([k, v]) => {
            if (v === null || v === undefined) return `${k} = NULL`;
            if (typeof v === 'string') return `${k} = '${v.replace(/'/g, "''")}'`;
            return `${k} = ${v}`;
          }).join(', ');

          const whereClause = this._wheres.length > 0
            ? 'WHERE ' + this._wheres.map(w => {
                return Object.entries(w).map(([k, v]) =>
                  `${k} = '${String(v).replace(/'/g, "''")}'`
                ).join(' AND ');
              }).join(' AND ')
            : '';

          const sql = `UPDATE ${this._tableName} SET ${setClause} ${whereClause}`;
          return db.public.none(sql);
        },

        async insert(data: any) {
          const keys = Object.keys(data);
          const values = Object.values(data).map(v => {
            if (v === null || v === undefined) return 'NULL';
            if (v instanceof Date) return `'${v.toISOString()}'`;
            if (typeof v === 'string') return `'${v.replace(/'/g, "''")}'`;
            return v;
          });

          const sql = `INSERT INTO ${this._tableName} (${keys.join(', ')}) VALUES (${values.join(', ')})`;
          return db.public.none(sql);
        }
      };

      return queryBuilder;
    };

    // Add raw query support
    knexMock.raw = async (sql: string) => {
      const result = db.public.query(sql);
      return { rows: result.rows || [result] };
    };

    // Add destroy method
    knexMock.destroy = jest.fn().mockResolvedValue(undefined);

    // Add client.pool mock
    knexMock.client = {
      pool: {
        on: jest.fn(),
      }
    };

    return knexMock;
  });
});

// Mock Kubernetes client
jest.mock('@kubernetes/client-node', () => ({
  KubeConfig: class {
    loadFromDefault = jest.fn();
    makeApiClient = () => ({
      createNamespacedJob: jest.fn().mockResolvedValue({ body: { metadata: { name: 'test-job' } } }),
      listNamespacedPod: jest.fn().mockResolvedValue({
        body: {
          items: [{
            status: { podIP: '1.2.3.4' },
            metadata: { name: 'test-pod' }
          }]
        }
      }),
    });
  },
  BatchV1Api: class {},
  CoreV1Api: class {},
}));

// Mock JWT signing
jest.mock('../sessionJwt', () => ({
  createSessionJWT: jest.fn().mockImplementation(async () => ({
    jti: 'test-jti-' + randomUUID(),
    token: 'mock-jwt-token-' + randomUUID(),
  })),
  getJWKS: jest.fn().mockResolvedValue({
    keys: [{ kty: 'RSA', kid: '1', alg: 'RS256', use: 'sig', n: 'test', e: 'AQAB' }],
  }),
  verifySessionJWT: jest.fn().mockResolvedValue({
    sub: 'test-user-uid',
    sid: 'test-session-id',
    aud: 'ws',
  }),
}));
