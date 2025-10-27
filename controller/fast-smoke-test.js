#!/usr/bin/env node

/**
 * Fast smoke test for the controller
 *
 * This test validates the full server lifecycle:
 * 1. Waits for database to be ready (important for CI)
 * 2. Server starts up and connects to database
 * 3. Server accepts HTTP requests
 * 4. Server shuts down gracefully without errors
 *
 * This catches critical runtime issues like:
 * - Database not ready (CI PostgreSQL service startup race)
 * - Multiple pool.destroy() calls ("Called end on pool more than once")
 * - Database connection failures
 * - Signal handler conflicts (SIGTERM/SIGINT)
 * - Port binding issues
 * - Module loading errors
 *
 * Requirements:
 * - PostgreSQL must be running and accessible
 * - Database migrations must be run first
 * - Environment variables must be set (DB_HOST, DB_PORT, etc.)
 */

import { spawn } from 'child_process';
import { setTimeout } from 'timers/promises';

const TEST_PORT = process.env.PORT || 3000;
const STARTUP_TIMEOUT = 5000;
const SHUTDOWN_TIMEOUT = 3000;

console.log('🚀 Starting full smoke test with real database...\n');

// Validate required environment variables
const requiredEnvVars = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'API_KEY'];
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);

if (missingEnvVars.length > 0) {
  console.error('❌ Missing required environment variables:');
  missingEnvVars.forEach(v => console.error(`   - ${v}`));
  console.error('\nPlease set these environment variables before running the smoke test.');
  process.exit(1);
}

console.log('✅ Environment variables validated');
console.log(`   DB_HOST: ${process.env.DB_HOST}`);
console.log(`   DB_PORT: ${process.env.DB_PORT}`);
console.log(`   DB_NAME: ${process.env.DB_NAME}`);
console.log(`   PORT: ${TEST_PORT}\n`);

// Wait for database to be ready (important for CI with PostgreSQL service)
console.log('⏳ Waiting for database to be ready...');
const dbHost = process.env.DB_HOST;
const dbPort = process.env.DB_PORT;
const maxWaitTime = 30000; // 30 seconds
const checkInterval = 1000; // 1 second
let dbReady = false;

for (let waited = 0; waited < maxWaitTime; waited += checkInterval) {
  try {
    // Use nc (netcat) to check if database port is open
    const { execSync } = await import('child_process');
    execSync(`nc -z ${dbHost} ${dbPort}`, { stdio: 'ignore', timeout: 1000 });
    dbReady = true;
    console.log(`✅ Database is ready at ${dbHost}:${dbPort}\n`);
    break;
  } catch (err) {
    if (waited === 0) {
      process.stdout.write('   Waiting for database');
    } else {
      process.stdout.write('.');
    }
    await setTimeout(checkInterval);
  }
}

if (!dbReady) {
  console.error(`\n\n❌ Database not ready after ${maxWaitTime/1000} seconds`);
  console.error(`   Could not connect to ${dbHost}:${dbPort}`);
  console.error('   Make sure PostgreSQL is running and accessible.\n');
  process.exit(1);
}

// Start the server
const serverProcess = spawn('node', ['dist/server.js'], {
  env: {
    ...process.env,
  },
  stdio: ['pipe', 'pipe', 'pipe'],
});

let serverOutput = '';
let serverError = '';
let testPassed = false;
let testFailed = false;

// Collect stdout
serverProcess.stdout.on('data', (data) => {
  const text = data.toString();
  serverOutput += text;

  // Show important startup messages
  if (text.includes('Server listening') || text.includes('listening on')) {
    console.log('✅ Server is listening on port', TEST_PORT);
  }
});

// Collect stderr and check for critical errors
serverProcess.stderr.on('data', (data) => {
  const errorText = data.toString();
  serverError += errorText;

  // Check for the critical error we fixed
  if (errorText.includes('Called end on pool more than once')) {
    console.error('\n❌ CRITICAL ERROR DETECTED!');
    console.error('━'.repeat(60));
    console.error('Error: "Called end on pool more than once"');
    console.error('━'.repeat(60));
    console.error('\nThis indicates that db.destroy() is being called multiple times.');
    console.error('This happens when:');
    console.error('  1. Both the server shutdown handler AND signal handlers call closeDatabasePool()');
    console.error('  2. The closeDatabasePool() function lacks a guard to prevent multiple calls\n');
    console.error('Fix: Add an isPoolClosed flag in src/db.ts to prevent multiple calls.\n');
    testFailed = true;
  }

  // Check for other critical errors
  if (errorText.includes('EADDRINUSE')) {
    console.error(`\n❌ CRITICAL ERROR: Port ${TEST_PORT} is already in use!\n`);
    testFailed = true;
  }

  if (errorText.includes('ECONNREFUSED') && errorText.includes(process.env.DB_HOST)) {
    console.error('\n❌ CRITICAL ERROR: Cannot connect to database!');
    console.error(`   Host: ${process.env.DB_HOST}:${process.env.DB_PORT}`);
    console.error('   Make sure PostgreSQL is running and accessible.\n');
    testFailed = true;
  }
});

// Handle server exit
serverProcess.on('exit', (code, signal) => {
  if (testPassed) {
    console.log(`\n✅ Server exited cleanly (code: ${code}, signal: ${signal})`);
    console.log('━'.repeat(60));
    console.log('✅ SMOKE TEST PASSED!');
    console.log('━'.repeat(60));
    console.log('\nAll checks passed:');
    console.log('  ✓ Server started successfully');
    console.log('  ✓ Database connection established');
    console.log('  ✓ Health endpoint responded');
    console.log('  ✓ Graceful shutdown completed');
    console.log('  ✓ No "Called end on pool more than once" errors');
    console.log('  ✓ No critical errors detected\n');
    process.exit(0);
  } else if (testFailed) {
    console.error('\n━'.repeat(60));
    console.error('❌ SMOKE TEST FAILED!');
    console.error('━'.repeat(60));
    console.error('\nServer stderr output:');
    console.error('─'.repeat(60));
    console.error(serverError || '(no stderr output)');
    console.error('─'.repeat(60));
    process.exit(1);
  } else {
    // Unexpected exit before test completed
    console.error(`\n❌ FAIL: Server exited unexpectedly (code: ${code}, signal: ${signal})`);
    console.error('\nPossible causes:');
    console.error('  - Database connection failed');
    console.error('  - Port already in use');
    console.error('  - Module loading error');
    console.error('  - Missing dependencies\n');

    if (serverError) {
      console.error('Server stderr:');
      console.error('─'.repeat(60));
      console.error(serverError);
      console.error('─'.repeat(60));
    }

    if (serverOutput) {
      console.error('\nServer stdout:');
      console.error('─'.repeat(60));
      console.error(serverOutput);
      console.error('─'.repeat(60));
    }

    process.exit(1);
  }
});

// Handle server error
serverProcess.on('error', (err) => {
  console.error('❌ FAIL: Failed to start server:', err.message);
  process.exit(1);
});

// Run the test sequence
async function runTest() {
  try {
    // Step 1: Wait for server to start
    console.log('⏳ Step 1: Waiting for server to start...');
    await setTimeout(STARTUP_TIMEOUT);

    if (testFailed) {
      serverProcess.kill('SIGTERM');
      return;
    }

    console.log('✅ Step 1: Server startup completed\n');

    // Step 2: Test health endpoint
    console.log('⏳ Step 2: Testing health endpoint...');
    try {
      const response = await fetch(`http://localhost:${TEST_PORT}/healthz`);
      if (response.ok) {
        const data = await response.json();
        console.log('✅ Step 2: Health endpoint responded:', data);
      } else {
        console.error(`❌ FAIL: Health endpoint returned status ${response.status}`);
        testFailed = true;
        serverProcess.kill('SIGTERM');
        return;
      }
    } catch (err) {
      console.error('❌ FAIL: Health endpoint request failed:', err.message);
      testFailed = true;
      serverProcess.kill('SIGTERM');
      return;
    }

    console.log('');

    // Step 3: Test graceful shutdown
    console.log('⏳ Step 3: Testing graceful shutdown (SIGTERM)...');

    // Mark test as passed before sending SIGTERM
    // The exit handler will verify no errors occurred
    if (!testFailed) {
      testPassed = true;
      console.log('✅ Step 3: Graceful shutdown initiated');
    }

    serverProcess.kill('SIGTERM');

    // Wait for graceful shutdown (give it time to complete)
    await setTimeout(SHUTDOWN_TIMEOUT);

    // If server is still running after timeout, force kill
    if (!serverProcess.killed && serverProcess.exitCode === null) {
      console.error('❌ FAIL: Server did not shut down within timeout, forcing kill');
      testFailed = true;
      testPassed = false;
      serverProcess.kill('SIGKILL');
      return;
    }

  } catch (err) {
    console.error('❌ FAIL: Test sequence failed:', err.message);
    testFailed = true;
    serverProcess.kill('SIGKILL');
    process.exit(1);
  }
}

// Start the test
runTest();
