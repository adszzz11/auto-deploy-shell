# Missing Modules Analysis

## Overview

This document identifies modules that exist in `_shell/` but have not yet been refactored into the `renew/` directory structure, along with recommendations for whether they should be implemented.

---

## 1. setup_logs Module

### Current Status: ⚠️ Partially Implemented (Inline)

### Location in _shell
- **Main Script**: `_shell/setup_logs/setup_logs_main.sh`
- **Functions**:
  - `setup_log_directory()`: Creates log directory structure
  - `create_log_link()`: Creates symbolic link from instance to log directory
  - `check_log_setup()`: Validates log configuration

### Current Implementation in renew/
**File**: `renew/deploy/func/execute_deployment.sh` (lines 80-92)

```bash
# 간소화된 인라인 구현
if [ -n "${LOG_BASE_DIR:-}" ]; then
    local log_dir="${LOG_BASE_DIR}/${SERVICE_NAME}/instances/${instance_num}"
    mkdir -p "$log_dir"

    local log_link="${instance_dir}/logs"
    if [ ! -L "$log_link" ]; then
        ln -s "$log_dir" "$log_link"
    fi
fi
```

### _shell/ Original Functionality
- **Comprehensive validation**: Checks LOG_BASE_DIR, SERVICE_NAME existence
- **Link verification**: Validates symbolic link creation and target
- **Status checking**: `check_log_setup()` function for verification
- **Error handling**: Detailed error messages for each failure point
- **Dry-run support**: Can simulate without making changes

### Gap Analysis
| Feature | renew/ (inline) | _shell/ (module) |
|---------|----------------|------------------|
| Directory creation | ✅ | ✅ |
| Symbolic link | ✅ | ✅ |
| Validation | ❌ | ✅ |
| Status checking | ❌ | ✅ |
| Error details | ❌ | ✅ |
| Standalone CLI | ❌ | ✅ |

### Recommendation: 🟡 Optional (Low Priority)

**Rationale**:
- Current inline implementation is sufficient for basic deployment needs
- Log setup is straightforward (mkdir + ln -s)
- No complex logic requiring separate module

**Benefits of Extracting**:
- Consistency with other modules
- Reusable across multiple deployment scenarios
- Independent testing and validation
- Standalone troubleshooting CLI

**Implementation Effort**: Low (~2 hours)

---

## 2. test_instance Module

### Current Status: ❌ Not Implemented

### Location in _shell
- **Main Script**: `_shell/test_instance/test_instance_main.sh`
- **Functions**:
  - `test_http_status()`: HTTP status code validation
  - `test_tcp_connection()`: TCP connectivity check
  - `test_response_time()`: Performance testing with timeout
  - `run_custom_tests()`: Execute custom test scripts

### Current Implementation in renew/
**Referenced in**: `renew/deploy/deploy.env`
```bash
# Optional test script to run after deployment
export TEST_SCRIPT=""  # 비어있음
```

**Used in**: `renew/deploy/func/execute_deployment.sh` (lines 118-132)
```bash
# 5단계: 테스트 실행 (TEST_SCRIPT가 설정된 경우)
if [ -n "${TEST_SCRIPT:-}" ] && [ -x "$TEST_SCRIPT" ]; then
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - Running deployment tests..."

    if "$TEST_SCRIPT" "$port" "$SERVICE_NAME"; then
        echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - Deployment tests passed"
    else
        echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - Deployment tests failed" >&2
        # Nginx UP 복구 후 실패 처리
        control_nginx_upstream "up" "$port" "$upstream_conf" "$script_dir"
        return 1
    fi
fi
```

### _shell/ Original Functionality

#### Test Types Supported
1. **HTTP Status Testing**
   ```bash
   test_http_status <port> [endpoint] [expected_status]
   # Default: GET localhost:PORT/actuator/health expects 200
   ```

2. **TCP Connection Testing**
   ```bash
   test_tcp_connection <port> [timeout]
   # Validates port is listening and accepting connections
   ```

3. **Response Time Testing**
   ```bash
   test_response_time <port> [endpoint] [max_time_ms]
   # Ensures response within acceptable latency
   ```

4. **Custom Test Execution**
   ```bash
   run_custom_tests <port> <test_script>
   # Executes user-defined test scenarios
   ```

#### Test Modes
- **Simple Test**: Basic connectivity check (used during deployment)
- **Full Test**: Comprehensive validation (HTTP + TCP + response time)
- **Custom Test**: User-defined test scenarios

### Gap Analysis

| Capability | renew/ | _shell/ |
|------------|--------|---------|
| HTTP status validation | ❌ | ✅ |
| TCP connectivity | ❌ | ✅ |
| Response time check | ❌ | ✅ |
| Custom test support | ⚠️ (basic) | ✅ (advanced) |
| Test modes (simple/full) | ❌ | ✅ |
| Detailed test reports | ❌ | ✅ |
| Retry mechanism | ❌ | ✅ |
| Timeout configuration | ❌ | ✅ |

### Current Limitation Impact

**Without test_instance module**:
- Deploy process relies on external `TEST_SCRIPT` (if provided)
- No built-in health validation after deployment
- No standardized testing framework
- Users must write custom test scripts
- No retry/timeout handling

**Deployment Risk**:
```bash
# Current: Deploy succeeds even if app is unhealthy
./deploy_control.sh deploy 0 app.env  # No validation

# Desired: Deploy validates app health
./deploy_control.sh deploy 0 app.env  # Auto-tests HTTP 200 response
```

### Recommendation: 🔴 High Priority (Should Implement)

**Rationale**:
- Testing is **critical** for production deployment validation
- Current approach requires manual test script creation
- _shell/ module provides comprehensive, reusable testing framework
- Integration with deploy module enhances reliability

**Benefits of Implementing**:
1. **Built-in Health Checks**: Automatic validation after deployment
2. **Standardized Testing**: Consistent test framework across instances
3. **Risk Reduction**: Catch deployment issues before Nginx UP
4. **Retry Logic**: Handle transient startup delays
5. **Performance Validation**: Ensure acceptable response times
6. **Extensibility**: Custom test support for app-specific checks

**Proposed Structure**:
```
renew/test_instance/
├── test_instance.env              # Test configuration
├── test_instance_control.sh       # Main CLI
├── SPEC.md                        # Documentation
└── func/
    ├── validate_test_params.sh    # Parameter validation
    ├── test_http_status.sh        # HTTP testing
    ├── test_tcp_connection.sh     # TCP testing
    ├── test_response_time.sh      # Performance testing
    └── run_custom_tests.sh        # Custom test execution
```

**Integration with Deploy**:
```bash
# In deploy.env
export TEST_INSTANCE_ENABLED="true"
export TEST_HTTP_ENDPOINT="/actuator/health"
export TEST_EXPECTED_STATUS="200"
export TEST_TIMEOUT="30"
export TEST_RETRY_COUNT="3"
export TEST_RETRY_DELAY="5"

# In execute_deployment.sh
if [ "${TEST_INSTANCE_ENABLED:-false}" = "true" ]; then
    local test_script="${script_dir}/../test_instance/test_instance_control.sh"

    if ! "$test_script" test "$port" "$env_file"; then
        echo "[ERROR] Instance health check failed"
        control_nginx_upstream "up" "$port" "$upstream_conf" "$script_dir"
        return 1
    fi
fi
```

**Implementation Effort**: Medium (~4-6 hours)

---

## 3. common_utils Module

### Current Status: ✅ Exists in _shell/ (Used by All Modules)

### Location
- **Main Script**: `_shell/common_utils/common_utils_main.sh`
- **Functions**:
  - `log_info()`, `log_warn()`, `log_success()`, `error_exit()`
  - `current_timestamp()`, `validate_port()`, `validate_directory()`

### Analysis
This module is **NOT missing** - it's intentionally kept in `_shell/common_utils/` as a shared utility library used by all modules in both `_shell/` and `renew/`.

**Usage Pattern in renew/ modules**:
```bash
# All renew/*_control.sh scripts source common_utils
source "${SCRIPT_DIR}/../_shell/common_utils/common_utils_main.sh"
```

### Recommendation: ✅ No Action Required

This is a foundational utility module that should remain in `_shell/` as a central shared library.

---

## Summary

| Module | Priority | Status | Recommendation |
|--------|----------|--------|----------------|
| setup_logs | 🟡 Low | Inline in deploy | Optional extraction for consistency |
| test_instance | 🔴 High | Not implemented | **Should implement** - critical for deployment validation |
| common_utils | ✅ N/A | Shared library | Keep in _shell/ (no action needed) |

---

## Next Steps

### Recommended Implementation Order

1. **Immediate**: Implement `renew/test_instance` module
   - Critical for production deployment safety
   - Provides standardized health validation
   - Reduces deployment risk

2. **Optional**: Extract `renew/setup_logs` module
   - Low priority (current inline implementation works)
   - Benefits: consistency, testability, reusability
   - Can be deferred if time-constrained

---

## Appendix: Feature Comparison

### Setup Logs - Detailed Comparison

**Current (Inline in deploy)**:
```bash
# Minimal implementation
mkdir -p "$log_dir"
ln -s "$log_dir" "$log_link"
```

**_shell/ Module**:
```bash
# Comprehensive implementation
validate_parameters "$instance_num" "$env_file"
load_environment "$instance_num" "$env_file"
validate_log_configuration
create_log_directory_structure  # mkdir -p with validation
create_log_symbolic_link        # ln -s with verification
verify_log_link_target          # readlink validation
fix_permissions                 # chmod/chown if needed
check_log_setup                 # Status command
```

### Test Instance - Detailed Comparison

**Current (External Script Only)**:
```bash
# User must provide TEST_SCRIPT
export TEST_SCRIPT="/path/to/custom_test.sh"

# No built-in capabilities
```

**_shell/ Module**:
```bash
# Built-in test framework
test_instance_control.sh test 8080 app.env
  ├─ HTTP Status: GET /actuator/health → 200 OK
  ├─ TCP Connection: localhost:8080 → Connected
  ├─ Response Time: 45ms (< 1000ms limit)
  └─ Custom Tests: ./custom_test.sh → Passed

# Configuration options
export TEST_HTTP_ENDPOINT="/actuator/health"
export TEST_EXPECTED_STATUS="200"
export TEST_TIMEOUT="30"
export TEST_RETRY_COUNT="3"
export TEST_RETRY_DELAY="5"
export TEST_MAX_RESPONSE_TIME="1000"
export TEST_MODE="full"  # simple|full|custom
```

---

**Document Version**: 1.0
**Last Updated**: 2025-10-04
**Author**: Analysis based on _shell/ and renew/ codebase comparison
