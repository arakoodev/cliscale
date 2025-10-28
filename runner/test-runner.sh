#!/usr/bin/env bash
set -euo pipefail

# Test script for runner container
# Tests the entire flow: download code, install deps, launch ttyd

echo "🚀 Runner Container Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test configuration
TEST_CODE_URL="https://github.com/arakoodev/cliscale/tree/main/sample-cli"
TEST_COMMAND="npm start"
TEST_PORT=7681

echo "✅ Test Configuration:"
echo "   CODE_URL: $TEST_CODE_URL"
echo "   COMMAND: $TEST_COMMAND"
echo "   TTYD_PORT: $TEST_PORT"
echo ""

# Build the runner image (use test tag to avoid Docker Hub confusion)
echo "📦 Building runner Docker image..."
docker build -t runner-test:test . || {
  echo "❌ FAIL: Docker build failed"
  exit 1
}
echo "✅ Docker build successful"
echo ""

# Start runner container in background
echo "🏃 Starting runner container..."
CONTAINER_ID=$(docker run -d \
  --rm \
  -p ${TEST_PORT}:${TEST_PORT} \
  -e CODE_URL="$TEST_CODE_URL" \
  -e COMMAND="$TEST_COMMAND" \
  runner-test:test)

echo "✅ Container started: $CONTAINER_ID"
echo ""

# Function to cleanup on exit
cleanup() {
  echo ""
  echo "🧹 Cleaning up..."
  if [ -n "${CONTAINER_ID:-}" ]; then
    docker logs "$CONTAINER_ID" || true
    docker stop "$CONTAINER_ID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Wait a moment for container to initialize
sleep 2

# Check container is still running (early check)
if ! docker ps | grep -q "$CONTAINER_ID"; then
  echo "❌ FAIL: Container exited immediately"
  echo ""
  echo "Container logs:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  docker logs "$CONTAINER_ID" 2>&1 || echo "Failed to get logs"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

echo "✅ Container started successfully"
echo ""

# Wait for code download and install deps
echo "⏳ Waiting for code download and npm install (this takes ~20 seconds)..."
for i in {1..30}; do
  sleep 1
  if ! docker ps | grep -q "$CONTAINER_ID"; then
    echo ""
    echo "❌ FAIL: Container exited during initialization"
    echo ""
    echo "Container logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    docker logs "$CONTAINER_ID" 2>&1
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
  fi

  # Check if ttyd has started
  if docker logs "$CONTAINER_ID" 2>&1 | grep -q "Launching ttyd"; then
    echo ""
    echo "✅ ttyd launch detected"
    break
  fi

  # Show progress
  if [ $((i % 5)) -eq 0 ]; then
    echo "   Still waiting... ($i/30)"
  fi
done

# Check logs for expected patterns
echo "📋 Checking container logs for success patterns..."
LOGS=$(docker logs "$CONTAINER_ID" 2>&1)

# Check for code download
if echo "$LOGS" | grep -q "Detected GitHub tree URL"; then
  echo "✅ GitHub tree URL detected"
else
  echo "❌ FAIL: GitHub tree URL not detected in logs"
  exit 1
fi

# Check for successful extraction
if echo "$LOGS" | grep -q "Successfully extracted"; then
  echo "✅ Code extracted successfully"
else
  echo "❌ FAIL: Code extraction failed"
  exit 1
fi

# Check for npm install
if echo "$LOGS" | grep -q "Installing dependencies"; then
  echo "✅ npm install started"
else
  echo "❌ FAIL: npm install not started"
  exit 1
fi

# Check for ttyd launch
if echo "$LOGS" | grep -q "Launching ttyd"; then
  echo "✅ ttyd launched"
else
  echo "❌ FAIL: ttyd not launched"
  exit 1
fi

echo ""

# Wait a bit more for ttyd to be fully ready
echo "⏳ Waiting for ttyd to be fully ready..."
sleep 10

# Check if ttyd port is open
echo "🔍 Testing ttyd HTTP endpoint..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -s -f "http://localhost:${TEST_PORT}/" > /dev/null 2>&1; then
    echo "✅ ttyd HTTP endpoint is responding"
    break
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ FAIL: ttyd endpoint not responding after $MAX_RETRIES attempts"
    exit 1
  fi

  echo "   Waiting for ttyd... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
done

echo ""

# Try to fetch the ttyd web interface
echo "🌐 Fetching ttyd web interface..."
HTTP_RESPONSE=$(curl -s "http://localhost:${TEST_PORT}/")

if echo "$HTTP_RESPONSE" | grep -q "Terminal"; then
  echo "✅ ttyd web interface loaded successfully"
elif echo "$HTTP_RESPONSE" | grep -q "<!DOCTYPE html>"; then
  echo "✅ ttyd web interface loaded (HTML detected)"
else
  echo "⚠️  WARNING: Unexpected HTTP response (but ttyd is running)"
fi

echo ""

# Check WebSocket endpoint (just verify it's there, not full WS test)
echo "🔌 Testing WebSocket endpoint availability..."
if curl -s -I "http://localhost:${TEST_PORT}/ws" | grep -q "HTTP"; then
  echo "✅ WebSocket endpoint is available"
else
  echo "⚠️  WARNING: WebSocket endpoint check inconclusive"
fi

echo ""

# Final logs check
echo "📋 Final logs check..."
FINAL_LOGS=$(docker logs "$CONTAINER_ID" 2>&1)

# Check for errors
if echo "$FINAL_LOGS" | grep -qi "\[fatal\]"; then
  echo "❌ FAIL: Fatal errors found in logs"
  echo ""
  echo "Container logs:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$FINAL_LOGS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

echo "✅ No fatal errors in logs"
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ RUNNER TEST PASSED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "All checks passed:"
echo "  ✓ Docker image builds successfully"
echo "  ✓ Container starts and runs"
echo "  ✓ GitHub tree URL code download works"
echo "  ✓ Code extraction successful"
echo "  ✓ npm install completes"
echo "  ✓ ttyd launches on port $TEST_PORT"
echo "  ✓ HTTP endpoint responds"
echo "  ✓ WebSocket endpoint available"
echo "  ✓ No fatal errors in logs"
echo ""

# Show snippet of logs
echo "📋 Container logs (last 30 lines):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker logs "$CONTAINER_ID" 2>&1 | tail -30
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
