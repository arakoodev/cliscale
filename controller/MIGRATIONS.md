# Database Migrations with Knex

This project uses [Knex.js](https://knexjs.org/) for database migrations and query building.

## Overview

Knex provides:
- **Version-controlled migrations**: Track database schema changes over time
- **Query builder**: Type-safe, composable SQL queries
- **Connection pooling**: Efficient database connection management
- **Multiple environment support**: Development, staging, production configurations

## Configuration

Database configuration is in `knexfile.js` at the project root. It supports multiple environments:

- **development**: Local development database
- **staging**: Staging environment
- **production**: Production database with SSL
- **test**: Test database (used by Jest)

### Environment Variables

Configure your database connection using these environment variables:

```bash
DATABASE_URL=postgresql://user:password@host:5432/database
# OR individual variables:
DB_HOST=localhost
DB_PORT=5432
DB_NAME=cliscale
DB_USER=postgres
DB_PASSWORD=postgres
DB_MAX_CONNECTIONS=20
```

## Migration Commands

### Run all pending migrations
```bash
npm run migrate:latest
```

This applies all migrations that haven't been run yet. Run this:
- When deploying to a new environment
- After pulling changes that include new migrations
- When setting up a new database

### Rollback the last migration batch
```bash
npm run migrate:rollback
```

This undoes the most recent migration batch. Use with caution in production!

### Create a new migration
```bash
npm run migrate:make create_my_table
```

This creates a new migration file in `src/migrations/` with timestamp prefix.

## Migration Files

Migrations are TypeScript files in `controller/src/migrations/`:

```
src/migrations/
├── 20250126000001_create_sessions_table.ts
└── 20250126000002_create_token_jti_table.ts
```

### Migration Structure

Each migration file exports two functions:

```typescript
import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  // Create tables, add columns, etc.
  await knex.schema.createTable('my_table', (table) => {
    table.increments('id').primary();
    table.string('name').notNullable();
    table.timestamps(true, true);
  });
}

export async function down(knex: Knex): Promise<void> {
  // Reverse the changes from up()
  await knex.schema.dropTableIfExists('my_table');
}
```

## Using Knex in Code

The Knex instance is exported from `src/db.ts`:

```typescript
import { db } from './db';

// Insert
await db('sessions').insert({
  session_id: 'abc-123',
  owner_user_id: 'user-456',
  job_name: 'job-789',
  expires_at: new Date()
});

// Select with where clause
const session = await db('sessions')
  .where({ session_id: 'abc-123' })
  .first();

// Update
await db('sessions')
  .where({ session_id: 'abc-123' })
  .update({ pod_ip: '1.2.3.4' });

// Raw queries (when needed)
const result = await db.raw('SELECT 1');
```

## Deployment

### Initial Setup

When deploying to a new environment:

1. Set environment variables for database connection
2. Run migrations:
   ```bash
   npm run migrate:latest
   ```
3. Start the application:
   ```bash
   npm start
   ```

### Kubernetes Deployment

For Kubernetes deployments, you can run migrations as an init container or Job before the main application starts:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cliscale-migrate
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: your-controller-image
        command: ["npm", "run", "migrate:latest"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database-secret
              key: url
      restartPolicy: OnFailure
```

## Testing

Tests use an in-memory database (pg-mem) that's automatically set up in `src/tests/setup.ts`. No migration commands are needed for tests - the schema is created automatically.

## Best Practices

1. **Never edit existing migrations**: Create new migrations to modify the schema
2. **Test migrations**: Test both `up` and `down` functions
3. **Keep migrations small**: One logical change per migration
4. **Use transactions**: Knex wraps migrations in transactions by default
5. **Document breaking changes**: Add comments for complex migrations

## Troubleshooting

### Migration table doesn't exist
Run `npm run migrate:latest` to create the migrations table.

### Migration fails midway
Knex uses transactions, so partial changes are rolled back. Fix the migration and run again.

### Can't connect to database
Check your `DATABASE_URL` or individual DB_* environment variables.

### TypeScript errors in migrations
Make sure you have `import type { Knex } from 'knex'` at the top of your migration file.

## Resources

- [Knex.js Documentation](https://knexjs.org/)
- [Knex Schema Builder](https://knexjs.org/guide/schema-builder.html)
- [Knex Query Builder](https://knexjs.org/guide/query-builder.html)
- [Knex Migrations](https://knexjs.org/guide/migrations.html)
