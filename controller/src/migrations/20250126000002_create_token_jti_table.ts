import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  // Create token_jti table for one-time JWT validation
  await knex.schema.createTable('token_jti', (table) => {
    table.text('jti').primary();
    table.text('session_id').notNullable();
    table.timestamp('expires_at', { useTz: true }).notNullable();

    // Index for efficient expiration queries
    table.index('expires_at', 'idx_jti_expires');
  });
}

export async function down(knex: Knex): Promise<void> {
  await knex.schema.dropTableIfExists('token_jti');
}
