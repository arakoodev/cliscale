import knex from 'knex';
import pino from 'pino';

const log = pino({ level: process.env.LOG_LEVEL || 'info' });

// Initialize Knex with configuration
export const db = knex({
  client: 'pg',
  connection: process.env.DATABASE_URL || {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'cliscale',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
  },
  pool: {
    min: 2,
    max: process.env.DB_MAX_CONNECTIONS ? parseInt(process.env.DB_MAX_CONNECTIONS) : 20,
    idleTimeoutMillis: process.env.DB_IDLE_TIMEOUT_MILLIS ? parseInt(process.env.DB_IDLE_TIMEOUT_MILLIS) : 30000,
    acquireTimeoutMillis: 10000,
  },
  // Enable SSL for Cloud SQL in production
  ...(process.env.NODE_ENV === 'production' && {
    connection: {
      ...typeof process.env.DATABASE_URL === 'string'
        ? { connectionString: process.env.DATABASE_URL }
        : process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: true }
    }
  })
});

// Track pool health
let isPoolHealthy = true;
let isPoolClosed = false;

// Listen to pool events
const pool = db.client.pool;

pool.on('createSuccess', () => {
  log.debug('New database client connected');
  isPoolHealthy = true;
});

pool.on('createFail', (err: Error) => {
  log.error({ err }, 'Database pool connection failed - attempting recovery');
  isPoolHealthy = false;

  // Set a timer to mark as healthy again after a short period
  setTimeout(() => {
    isPoolHealthy = true;
  }, 5000);
});

pool.on('destroySuccess', () => {
  log.debug('Database client removed from pool');
});

// Health check function
export async function checkDatabaseHealth(): Promise<boolean> {
  if (!isPoolHealthy) {
    return false;
  }

  try {
    const result = await db.raw('SELECT 1');
    return result.rows.length === 1;
  } catch (err) {
    log.error({ err }, 'Database health check failed');
    return false;
  }
}

// Graceful shutdown
export async function closeDatabasePool(): Promise<void> {
  if (isPoolClosed) {
    log.debug('Database pool already closed, skipping');
    return;
  }

  isPoolClosed = true;
  log.info('Closing database pool');
  await db.destroy();
}

// Handle process termination
process.on('SIGTERM', async () => {
  log.info('SIGTERM received, closing database pool');
  await closeDatabasePool();
  process.exit(0);
});

process.on('SIGINT', async () => {
  log.info('SIGINT received, closing database pool');
  await closeDatabasePool();
  process.exit(0);
});