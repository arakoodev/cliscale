# Running Database Migrations on Kubernetes

This document explains how to run database migrations safely on a Kubernetes cluster.

## Quick Start

**Migrations run automatically!** When you deploy with Helm, migrations run via a Helm hook before the application starts.

```bash
# This automatically runs migrations before deployment
helm upgrade cliscale ./cliscale-chart --install
```

## How It Works

### Automatic Migrations (Default)

The Helm chart includes a pre-upgrade/pre-install hook that:

1. **Runs before deployment** - Migrations complete before new pods start
2. **Uses Helm hooks** - Annotation: `helm.sh/hook: pre-upgrade,pre-install`
3. **Single execution** - `parallelism: 1` prevents concurrent migrations
4. **Idempotent** - Knex tracks applied migrations, safe to run multiple times
5. **Retries on failure** - `backoffLimit: 3` retries up to 3 times
6. **Auto-cleanup** - Successful jobs deleted before next deployment

### Migration Job Lifecycle

```
Helm Deployment Started
         ↓
    Namespace Created
         ↓
    Secrets Created
         ↓
   Migration Job Runs  ← You are here (pre-install/pre-upgrade hook)
         ↓
  [Success] → Continue deployment
         ↓
  Controller Pods Start
         ↓
  Gateway Pods Start
         ↓
    Deployment Complete
```

### Safety Guarantees

✅ **Idempotent**: Knex's migration table tracks which migrations ran
✅ **Atomic**: Each migration runs in a transaction (PostgreSQL)
✅ **Sequential**: Migrations run in timestamp order
✅ **Single process**: Only one migration job runs at a time
✅ **No data loss**: Failed migrations roll back automatically
✅ **Retry logic**: Jobs retry up to 3 times on failure

## Configuration

### Enable/Disable Automatic Migrations

In `values.yaml`:

```yaml
migrations:
  # Enable automatic migrations via Helm hooks
  enabled: true

  # Knex environment (production, staging, development)
  knexEnv: "production"

  # Number of retry attempts if migration fails
  backoffLimit: 3

  # Resource requests/limits
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
```

### Disable Automatic Migrations

If you want to run migrations manually:

```bash
helm upgrade cliscale ./cliscale-chart \
  --set migrations.enabled=false
```

## Manual Migration Operations

### Run Migrations Manually

If you disabled automatic migrations or need to run them separately:

```bash
# Create a one-off migration job
kubectl create job --from=cronjob/manual-migrate cliscale-migrate-manual -n ws-cli

# Or apply a standalone job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cliscale-migrate-manual
  namespace: ws-cli
spec:
  template:
    spec:
      serviceAccountName: ws-cli-controller
      restartPolicy: OnFailure
      containers:
      - name: migrate
        image: YOUR_CONTROLLER_IMAGE:TAG
        command: ["npm", "run", "migrate:latest"]
        env:
        - name: DB_HOST
          value: "127.0.0.1"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: pg
              key: database
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: pg
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pg
              key: password
        - name: NODE_ENV
          value: "production"
      # Cloud SQL Proxy sidecar (if using Cloud SQL)
      - name: cloud-sql-proxy
        image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0
        args:
          - "--structured-logs"
          - "--port=5432"
          - "YOUR_INSTANCE_CONNECTION_NAME"
EOF
```

### Check Migration Status

```bash
# View migration job logs
kubectl logs -n ws-cli -l app.kubernetes.io/component=migration --tail=100

# Check if migration job succeeded
kubectl get jobs -n ws-cli -l app.kubernetes.io/component=migration

# View migration history in database
kubectl exec -n ws-cli deployment/cliscale-controller -- \
  npm run knex migrate:list
```

### View Migration Job Pods

```bash
# List all migration jobs
kubectl get jobs -n ws-cli -l app.kubernetes.io/component=migration

# Get logs from the latest migration
LATEST_JOB=$(kubectl get jobs -n ws-cli -l app.kubernetes.io/component=migration \
  --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl logs -n ws-cli $LATEST_JOB
```

### Rollback Last Migration

⚠️ **Use with extreme caution in production!**

```bash
# Create a rollback job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: cliscale-migrate-rollback
  namespace: ws-cli
spec:
  template:
    spec:
      serviceAccountName: ws-cli-controller
      restartPolicy: OnFailure
      containers:
      - name: rollback
        image: YOUR_CONTROLLER_IMAGE:TAG
        command: ["npm", "run", "migrate:rollback"]
        env:
        # Same env vars as migrate job above
        - name: DB_HOST
          value: "127.0.0.1"
        # ... (same as above)
EOF
```

## Troubleshooting

### Migration Job Failed

```bash
# Check job status
kubectl describe job -n ws-cli -l app.kubernetes.io/component=migration

# View logs
kubectl logs -n ws-cli -l app.kubernetes.io/component=migration --tail=100

# Common issues:
# 1. Database connection failed
#    → Check Cloud SQL Proxy is running
#    → Verify database credentials in secrets
#    → Check Workload Identity bindings
#
# 2. Migration syntax error
#    → Fix the migration file locally
#    → Rebuild and redeploy the image
#    → Helm will run migrations again
#
# 3. Migration already applied
#    → This is fine! Knex skips already-applied migrations
```

### View Migration Table

```bash
# Connect to the database and check migration state
kubectl exec -n ws-cli deployment/cliscale-controller -- \
  psql $DATABASE_URL -c "SELECT * FROM knex_migrations ORDER BY id;"
```

### Job Not Running

```bash
# Check if migrations are enabled
helm get values cliscale -n ws-cli | grep -A 5 migrations

# Check job events
kubectl get events -n ws-cli --sort-by='.lastTimestamp' | grep migrate

# Check pod logs if stuck in pending
kubectl get pods -n ws-cli -l app.kubernetes.io/component=migration
kubectl describe pod -n ws-cli -l app.kubernetes.io/component=migration
```

### Clean Up Failed Jobs

```bash
# Delete failed migration jobs manually
kubectl delete job -n ws-cli -l app.kubernetes.io/component=migration

# Helm will create a new one on next deployment
```

## CI/CD Integration

### Skaffold

Migrations run automatically with Skaffold deployments:

```bash
# Development mode (runs migrations on every change)
skaffold dev

# Production deployment (runs migrations once)
skaffold run
```

### GitHub Actions

Add a migration step to your deployment workflow:

```yaml
- name: Deploy to Kubernetes
  run: |
    helm upgrade cliscale ./cliscale-chart \
      --install \
      --namespace ws-cli \
      --set migrations.enabled=true \
      --wait \
      --timeout 10m
```

The `--wait` flag ensures migrations complete before deployment proceeds.

## Best Practices

### DO ✅

- **Let Helm hooks run migrations automatically** - This is the safest approach
- **Test migrations locally first** - Run `npm run migrate:latest` locally
- **Use transactions** - Knex wraps migrations in transactions automatically
- **Keep migrations small** - One logical change per migration
- **Version control** - Commit migration files to Git

### DON'T ❌

- **Don't manually edit the knex_migrations table** - Let Knex manage it
- **Don't skip migrations** - Run them in order
- **Don't run migrations directly on production DB** - Use Kubernetes Jobs
- **Don't delete migration files** - They're part of your schema history
- **Don't run multiple migration jobs simultaneously** - Helm prevents this

## Advanced: Multi-Environment Setup

### Development Environment

```bash
helm upgrade cliscale-dev ./cliscale-chart \
  --set migrations.knexEnv=development \
  --set migrations.backoffLimit=1  # Fail fast in dev
```

### Staging Environment

```bash
helm upgrade cliscale-staging ./cliscale-chart \
  --set migrations.knexEnv=staging \
  --set migrations.backoffLimit=2
```

### Production Environment

```bash
helm upgrade cliscale-prod ./cliscale-chart \
  --set migrations.knexEnv=production \
  --set migrations.backoffLimit=3  # More retries in prod
```

## Migration Workflow Example

### Adding a New Migration

1. **Create migration locally**:
   ```bash
   cd controller
   npm run migrate:make add_user_preferences_table
   ```

2. **Edit the migration file**:
   ```typescript
   // controller/src/migrations/20250126120000_add_user_preferences_table.ts
   export async function up(knex: Knex): Promise<void> {
     await knex.schema.createTable('user_preferences', (table) => {
       table.text('user_id').primary();
       table.jsonb('preferences').notNullable();
       table.timestamp('updated_at').defaultTo(knex.fn.now());
     });
   }

   export async function down(knex: Knex): Promise<void> {
     await knex.schema.dropTableIfExists('user_preferences');
   }
   ```

3. **Test locally**:
   ```bash
   npm run migrate:latest   # Apply migration
   npm run migrate:rollback  # Test rollback
   npm run migrate:latest   # Re-apply
   npm test                 # Run tests
   ```

4. **Commit and push**:
   ```bash
   git add controller/src/migrations/
   git commit -m "feat: add user preferences table"
   git push
   ```

5. **Deploy** (migrations run automatically):
   ```bash
   skaffold run
   # Or let your CI/CD handle it
   ```

6. **Verify**:
   ```bash
   kubectl logs -n ws-cli -l app.kubernetes.io/component=migration --tail=50
   ```

## FAQ

### Q: Can I run migrations multiple times?
**Yes!** Knex tracks applied migrations in the `knex_migrations` table. Re-running `migrate:latest` is safe and will only apply new migrations.

### Q: What happens if a migration fails?
The Job retries up to 3 times (configurable via `backoffLimit`). If all retries fail, Helm deployment stops. Fix the migration, rebuild the image, and redeploy.

### Q: Do I need to manually run migrations?
**No.** Helm hooks run them automatically before deployment. Only run manually if you disabled `migrations.enabled`.

### Q: Can I skip migrations?
Not recommended. You can disable migrations with `--set migrations.enabled=false`, but then you must run them manually before the application starts.

### Q: How do I see which migrations have been applied?
```bash
kubectl exec -n ws-cli deployment/cliscale-controller -- \
  psql $DATABASE_URL -c "SELECT * FROM knex_migrations;"
```

### Q: What if two people deploy at the same time?
Helm hooks run sequentially, and the Job has `parallelism: 1`. Only one migration Job runs at a time.

### Q: Can I run migrations in a separate namespace?
Yes, but ensure the migration Job has access to the same database secrets and service accounts.

## Resources

- [Knex.js Migrations Guide](https://knexjs.org/guide/migrations.html)
- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [controller/MIGRATIONS.md](../controller/MIGRATIONS.md) - Local development guide
