#!/bin/bash
set -e
set -x

# Build and install the ic-python-logging package from source
echo "Building and installing ic-python-logging wheel..."
cd /app/ic-python-logging-source
python -m pip install --upgrade pip wheel build
python -m build --wheel
pip install dist/*.whl

# Ensure latest basilisk is installed
pip install --upgrade ic-basilisk

# Pre-download CPython canister template if not cached
BASILISK_VERSION=$(python3 -c "import basilisk; print(basilisk.__version__)")
TEMPLATE_DIR="$HOME/.config/basilisk/${BASILISK_VERSION}"
TEMPLATE_FILE="${TEMPLATE_DIR}/cpython_canister_template.wasm"
if [ ! -f "$TEMPLATE_FILE" ]; then
    mkdir -p "$TEMPLATE_DIR"
    curl -Lf "https://github.com/smart-social-contracts/basilisk/releases/download/cpython-wasm-3.13.0/cpython_canister_template.wasm" \
        -o "$TEMPLATE_FILE"
fi
cd /app

# Start dfx in the background
echo "Starting dfx..."
dfx start --background --clean > /tmp/log.txt 2>&1

# Build and deploy the test canister
echo "Building and deploying test canister..."
CANISTER_CANDID_PATH=./test.did python -m basilisk test src/main.py
dfx deploy

# Define a list of test identifiers
TEST_IDS=( 'basic_logging' 'named_loggers' 'level_filtering' 'global_level' 'disable_enable' )

# Loop through each test identifier
for TEST_ID in "${TEST_IDS[@]}"; do
  echo "Testing test_${TEST_ID} module..."
  dfx canister call test run_test ${TEST_ID}
  sleep 2
  
  (cd src && PYTHONPATH=. python tests/test_functions.py assert ${TEST_ID})
  TEST_RESULT=$?
  
  if [ "$TEST_RESULT" != '0' ]; then
    echo "Error: test_${TEST_ID}.run() function returned unexpected result: $TEST_RESULT"
    dfx stop
    exit 1
  else
    echo "test_${TEST_ID}.run() function test passed!"
  fi

done

# Run variable tests
echo "Testing variable storage module..."
TEST_RESULT=$(dfx canister call test run_var_test)
if [ "$TEST_RESULT" != '(0 : int)' ]; then
  echo "Error: run_var_test test returned unexpected result: $TEST_RESULT"
  dfx stop
  exit 1
else
  echo "run_var_test test passed!"
fi

# Run memory logging tests
echo "Testing memory logging module..."
TEST_RESULT=$(dfx canister call test run_memory_logs_test)
if [ "$TEST_RESULT" != '(0 : int)' ]; then
  echo "Error: run_memory_logs_test returned unexpected result: $TEST_RESULT"
  dfx stop
  exit 1
else
  echo "run_memory_logs_test test passed!"
fi

# Test the canister query function directly
echo "Testing get_canister_logs query function..."
# Generate some logs first
dfx canister call test run_test basic_logging > /dev/null

# Call the query function directly
QUERY_RESULT=$(dfx canister call test get_canister_logs)
LOG_COUNT=$(echo "$QUERY_RESULT" | grep -o "record" | wc -l)

echo "Retrieved $LOG_COUNT log entries via query function"
if [ "$LOG_COUNT" -lt 1 ]; then
  echo " Error: get_canister_logs query returned no logs"
  dfx stop
  exit 1
else
  echo " get_canister_logs query test passed!"
fi

# Test the CLI tool
echo "Testing CLI tool..."

# Create some logs for testing
dfx canister call test run_test basic_logging > /dev/null
CANISTER_ID=$(dfx canister id test)

# Run simple test to fetch logs using CLI
echo "Testing CLI basic functionality..."
kslog $CANISTER_ID --tail 5 > /tmp/cli_test_output.txt

# Check the output
LOG_COUNT=$(cat /tmp/cli_test_output.txt | wc -l)
if [ "$LOG_COUNT" -lt 1 ]; then
  echo " Error: CLI returned no logs"
  dfx stop
  exit 1
else
  echo " CLI basic test passed!"
fi

# Clean up test output
rm -f /tmp/cli_test_output.txt
rm -f /tmp/cli_level_test.txt

# Deploy the example canister
echo "Deploying example canister..."
cd /app/ic-python-logging-source/example
dfx deploy
echo "Example canister deployed successfully!"
sleep 5
dfx canister logs kslog_example  # Show example canister logs
cd /app

echo "Stopping dfx..."
dfx stop

echo "All done!"