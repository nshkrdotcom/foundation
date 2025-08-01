[
  # circuit_breaker.ex contract_supertype warnings
  {"lib/foundation/infrastructure/circuit_breaker.ex", :contract_supertype},

  # connection_manager.ex contract_supertype warnings
  {"lib/foundation/infrastructure/connection_manager.ex", :contract_supertype},

  # infrastructure.ex contract_supertype warnings
  {"lib/foundation/infrastructure/infrastructure.ex", :contract_supertype},

  # infrastructure.ex pattern_match_cov warnings - expected for comprehensive guards
  {"lib/foundation/infrastructure/infrastructure.ex", :pattern_match_cov},

  # infrastructure.ex pattern_match warnings - unified config error handling is comprehensive but some cases unreachable
  {"lib/foundation/infrastructure/infrastructure.ex", :pattern_match},

  # infrastructure.ex extra_range warnings - specs are comprehensive but some return types unreachable due to validation
  {"lib/foundation/infrastructure/infrastructure.ex", :extra_range},

  # rate_limiter.ex contract_supertype warnings
  {"lib/foundation/infrastructure/rate_limiter.ex", :contract_supertype},

  # pool_workers contract_supertype warnings
  {"lib/foundation/infrastructure/pool_workers/http_worker.ex", :contract_supertype},

  # event_store.ex pattern_match warnings - test_mode conditional compilation
  {"lib/foundation/services/event_store.ex", :pattern_match},

  # telemetry_service.ex pattern_match warnings - test_mode conditional compilation
  {"lib/foundation/services/telemetry_service.ex", :pattern_match},

  # Removed unused MABEAM pattern_match filters

  # Removed unused legacy pattern_match filters
]
