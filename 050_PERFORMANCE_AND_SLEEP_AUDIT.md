
# Performance and Sleep Audit

This document provides a consolidated audit of all performance-related tests and all instances of `Process.sleep` within the test suite. The goal is to provide a clear, actionable list for a holistic refactoring effort.

## 1. Performance-Related Test Files

The following files are considered performance-related based on their naming (`performance` or `properties`):

*   `test/property/foundation/beam/processes_properties_test.exs`
*   `test/mabeam/performance_monitor_test.exs`
*   `test/foundation/process_registry_performance_test.exs`
*   `test/property/foundation/event_correlation_properties_test.exs`
*   `test/property/foundation/error_properties_test.exs`
*   `test/property/foundation/config_validation_properties_test.exs`
*   `test/foundation/process_registry/properties.ex`
*   `test/property/foundation/infrastructure/rate_limiter_properties_test.exs`
*   `test/property/foundation/infrastructure/circuit_breaker_properties_test.exs`

## 2. `Process.sleep` Usage Audit

The following is a list of all files in the test suite that use `Process.sleep`, with the corresponding line numbers. These represent opportunities for refactoring to more reliable, event-driven approaches.

*   `test_helper.exs`: 22, 130
*   `support/unified_registry_helpers.ex`: 300
*   `support/test_workers.exs`: 192, 299, 304, 314, 434
*   `support/test_supervisor.ex`: 159, 284
*   `support/test_process_manager.ex`: 40, 325
*   `support/test_agent.ex`: 164, 172
*   `support/telemetry_helpers.exs`: 357, 680
*   `support/support_infrastructure_test.exs`: 185, 187, 189, 347, 423
*   `support/foundation_test_helper.exs`: 179, 184, 390, 424
*   `support/concurrent_test_case.ex`: 137
*   `security/privilege_escalation_test.exs`: 49, 70, 170, 450
*   `mabeam/telemetry_test.exs`: 327
*   `mabeam/process_registry_test.exs`: 115, 140, 176
*   `mabeam/performance_monitor_test.exs`: 100
*   `mabeam/core_test.exs`: 352, 477
*   `mabeam/coordination_test.exs`: 303, 313, 334, 549, 600
*   `mabeam/comms_test.exs`: 203, 240, 280
*   `mabeam/agent_test.exs`: 398
*   `mabeam/agent_supervisor_test.exs`: 65
*   `mabeam/agent_registry_test.exs`: 87, 388, 419
*   `integration/graceful_degradation_integration_test.exs`: 105, 355
*   `integration/data_consistency_integration_test.exs`: 26, 157, 183, 551
*   `integration/cross_service_integration_test.exs`: 31, 65, 69, 108, 116, 166, 203, 227, 254, 276, 329
*   `foundation/process_registry_performance_test.exs`: 38, 74, 135, 208, 244, 304
*   `foundation/process_registry_optimizations_test.exs`: 39, 73, 91, 104, 115, 130, 139, 157, 196, 201, 202, 204, 231, 259, 260, 300
*   `property/foundation/event_correlation_properties_test.exs`: 235, 344, 481
*   `property/foundation/config_validation_properties_test.exs`: 297
*   `support/mabeam/test_helpers.exs`: 99, 211, 218, 408
*   `mabeam/integration/stress_test.exs`: 34, 377, 419, 438, 443
*   `mabeam/integration/simple_stress_test.exs`: 14
*   `integration/foundation/service_lifecycle_test.exs`: 32, 71, 119, 149, 179, 198, 211, 317, 377, 417, 436, 445, 505, 558, 564, 615, 1028, 1048
*   `integration/foundation/config_events_telemetry_test.exs`: 63, 112, 157, 184, 192, 197, 243
*   `foundation/services/service_behaviour_test.exs`: 100, 112, 123, 132, 164, 174, 180, 240
*   `foundation/process_registry/properties.ex`: 93, 100, 131, 164, 199, 229, 275, 307, 355, 362, 376, 390
*   `unit/foundation/service_registry_test.exs`: 353, 421, 516, 655
*   `unit/foundation/process_registry_test.exs`: 127, 441
*   `unit/foundation/process_registry_metadata_test.exs`: 156, 184, 189
*   `unit/foundation/graceful_degradation_test.exs`: 105, 166
*   `unit/foundation/error_context_test.exs`: 413, 425
*   `property/foundation/beam/processes_properties_test.exs`: 152, 320, 366
*   `property/foundation/infrastructure/rate_limiter_properties_test.exs`: 299
*   `property/foundation/infrastructure/circuit_breaker_properties_test.exs`: 426
*   `foundation/process_registry/backend/enhanced_ets_test.exs`: 40, 78, 116, 173, 220, 284, 339
*   `unit/foundation/services/config_server_test.exs`: 141
*   `unit/foundation/services/config_server_resilient_test.exs`: 136, 165, 191, 213, 235, 410, 444
*   `unit/foundation/process_registry/unified_test_helpers_test.exs`: 21, 22, 377, 378, 405
*   `unit/foundation/process_registry/backend_test.exs`: 122, 126, 175, 182, 328, 332
*   `unit/foundation/infrastructure/rate_limiter_test.exs`: 237, 391, 414
*   `unit/foundation/infrastructure/connection_manager_test.exs`: 382, 387, 646, 704
*   `unit/foundation/infrastructure/circuit_breaker_test.exs`: 230, 242, 273, 427
*   `unit/foundation/infrastructure/pool_workers/http_worker_test.exs`: 457
