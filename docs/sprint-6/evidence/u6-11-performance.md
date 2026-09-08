# U6-11 — Performance

`ProductionPerformanceInstrumentation` records monotonic event-to-action-start and overlay-calculation timings, completed-action/topology counters, and process memory through production call sites. `PerformanceBudgetPolicy` also evaluates idle CPU p95 and fails closed on invalid, missing, or undersized workloads. Production live measurement remains `PENDING — HUMAN` because physical input, Accessibility, CPU sampling, and display topology are session-dependent gates.
