[
  # circuit_breaker.ex contract_supertype warnings
  {"lib/foundation/infrastructure/circuit_breaker.ex", :contract_supertype},

  # connection_manager.ex contract_supertype warnings
  {"lib/foundation/infrastructure/connection_manager.ex", :contract_supertype},

  # infrastructure.ex contract_supertype warnings
  {"lib/foundation/infrastructure/infrastructure.ex", :contract_supertype},

  # infrastructure.ex pattern_match_cov warnings - expected for comprehensive guards
  {"lib/foundation/infrastructure/infrastructure.ex", :pattern_match_cov},

  # rate_limiter.ex contract_supertype warnings
  {"lib/foundation/infrastructure/rate_limiter.ex", :contract_supertype},

  # pool_workers contract_supertype warnings
  {"lib/foundation/infrastructure/pool_workers/http_worker.ex", :contract_supertype},

  # event_store.ex pattern_match warnings - test_mode conditional compilation
  {"lib/foundation/services/event_store.ex", :pattern_match},

  # telemetry_service.ex pattern_match warnings - test_mode conditional compilation
  {"lib/foundation/services/telemetry_service.ex", :pattern_match},

  # MABEAM services pattern_match warnings - false positives from ServiceBehaviour macro expansion
  {"lib/foundation/mabeam/core.ex", :pattern_match},
  {"lib/foundation/mabeam/agent_registry.ex", :pattern_match},
  {"lib/foundation/mabeam/coordination.ex", :pattern_match},
  {"lib/foundation/mabeam/telemetry.ex", :pattern_match}
]
