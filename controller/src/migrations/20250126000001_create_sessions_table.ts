import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  // Enable UUID generation extension
  await knex.raw('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"');

  // Create sessions table
  await knex.schema.createTable('sessions', (table) => {
    table.text('session_id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.text('owner_user_id').notNullable();
    table.text('job_name').notNullable().unique();
    table.text('pod_name');
    table.text('pod_ip');
    table.timestamp('created_at', { useTz: true }).defaultTo(knex.fn.now());
    table.timestamp('expires_at', { useTz: true }).notNullable();

    // Indexes
    table.index('owner_user_id', 'idx_sessions_owner');
    table.index('expires_at', 'idx_sessions_expires');
  });
}

export async function down(knex: Knex): Promise<void> {
  await knex.schema.dropTableIfExists('sessions');
  await knex.raw('DROP EXTENSION IF EXISTS "uuid-ossp"');
}
