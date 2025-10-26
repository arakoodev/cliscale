// Knex configuration for database migrations
// Determines whether to use TypeScript source or compiled JavaScript
const useCompiledMigrations = process.env.NODE_ENV === 'production' ||
                               process.env.NODE_ENV === 'test' ||
                               process.env.CI === 'true';

export default {
  development: {
    client: 'pg',
    connection: {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'cliscale',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
    },
    migrations: {
      directory: useCompiledMigrations ? './dist/migrations' : './src/migrations',
      tableName: 'knex_migrations',
      extension: useCompiledMigrations ? 'js' : 'ts',
    },
    seeds: {
      directory: './src/seeds',
    },
  },

  staging: {
    client: 'pg',
    connection: {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'cliscale',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'postgres',
    },
    pool: {
      min: 2,
      max: 10,
    },
    migrations: {
      directory: useCompiledMigrations ? './dist/migrations' : './src/migrations',
      tableName: 'knex_migrations',
      extension: useCompiledMigrations ? 'js' : 'ts',
    },
  },

  production: {
    client: 'pg',
    connection: {
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    },
    pool: {
      min: 2,
      max: 20,
    },
    migrations: {
      directory: useCompiledMigrations ? './dist/migrations' : './src/migrations',
      tableName: 'knex_migrations',
      extension: useCompiledMigrations ? 'js' : 'ts',
    },
  },

  test: {
    client: 'pg',
    connection: {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432'),
      database: process.env.DB_NAME || 'cliscale_test',
      user: process.env.DB_USER || 'postgres',
      password: process.env.PASSWORD || 'postgres',
    },
    migrations: {
      directory: useCompiledMigrations ? './dist/migrations' : './src/migrations',
      tableName: 'knex_migrations',
      extension: useCompiledMigrations ? 'js' : 'ts',
    },
  },
};
