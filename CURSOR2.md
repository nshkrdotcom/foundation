home@Desktop:~/p/g/n/elixir_ml/foundation$ mix test
Compiling 2 files (.ex)
     warning: got "@impl true" for function handle_cast/2 but no behaviour specifies such callback. The known callbacks are:

       * DynamicSupervisor.init/1 (function)

     │
 377 │   def handle_cast({:track_agent, agent_id, pid}, state) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/mabeam/agent_supervisor.ex:377: MABEAM.AgentSupervisor (module)

     warning: got "@impl true" for function handle_cast/2 but no behaviour specifies such callback. The known callbacks are:

       * DynamicSupervisor.init/1 (function)

     │
 384 │   def handle_cast(_msg, state) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/mabeam/agent_supervisor.ex:384: MABEAM.AgentSupervisor (module

1) test agent deregistration stops running agent when deregistering (MABEAM.AgentRegistryTest)
     test/mabeam/agent_registry_test.exs:198
     Expected false or nil, got true
     code: refute Process.alive?(pid)
     arguments:

         # 1
         #PID<0.20425.0>

     stacktrace:
       test/mabeam/agent_registry_test.exs:211: anonymous fn/1 in MABEAM.AgentRegistryTest."test agent deregistration stops running agent when deregistering"/1
       test/mabeam/agent_registry_test.exs:211: (test)

     The following output was logged:
     [info] Registered agent stop_dereg_agent with module Elixir.TestAgent
     [info] Started agent stop_dereg_agent with PID #PID<0.20425.0>
     [info] Deregistered agent stop_dereg_agent

...................

  2) test agent lifecycle stops running agent gracefully (MABEAM.AgentRegistryTest)
     test/mabeam/agent_registry_test.exs:263
     Expected false or nil, got true
     code: refute Process.alive?(pid)
     arguments:

         # 1
         #PID<0.20597.0>

     stacktrace:
       test/mabeam/agent_registry_test.exs:275: anonymous fn/1 in MABEAM.AgentRegistryTest."test agent lifecycle stops running agent gracefully"/1
       test/mabeam/agent_registry_test.exs:275: (test)

     The following output was logged:
     [info] Registered agent stop_agent with module Elixir.TestAgent
     [info] Started agent stop_agent with PID #PID<0.20597.0>
     [info] Stopped agent stop_agent
     [info] Deregistered agent stop_agent

.[info] Deregistered agent stop_test_agent


  3) test agent supervision stops supervised agents cleanly (MABEAM.AgentSupervisorTest)
     test/mabeam/agent_supervisor_test.exs:76
     Assertion with == failed
     code:  assert length(children) == 0
     left:  132
     right: 0
     stacktrace:
       test/mabeam/agent_supervisor_test.exs:97: (test)

     The following output was logged:
     [info] Registered agent stop_test_agent with module Elixir.MABEAM.TestWorker
