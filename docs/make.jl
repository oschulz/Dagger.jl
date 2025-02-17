using Dagger, TimespanLogging, DaggerWebDash
using Documenter

makedocs(;
    modules = [Dagger, TimespanLogging, DaggerWebDash],
    authors = "JuliaParallel and contributors",
    repo = "https://github.com/JuliaParallel/Dagger.jl/blob/{commit}{path}#L{line}",
    sitename = "Dagger.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://JuliaParallel.github.io/Dagger.jl",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Task Spawning" => "task-spawning.md",
        "Data Management" => "data-management.md",
        "Distributed Arrays" => "darray.md",
        "Scopes" => "scopes.md",
        "Processors" => "processors.md",
        "Task Queues" => "task-queues.md",
        "Option Propagation" => "propagation.md",
        "Logging and Graphing" => "logging.md",
        "Checkpointing" => "checkpointing.md",
        "Scheduler Visualization" => "scheduler-visualization.md",
        "Benchmarking" => "benchmarking.md",
        "Dynamic Scheduler Control" => "dynamic.md",
        "Scheduler Internals" => "scheduler-internals.md",
        "Dagger API" => [
            "Types" => "api-dagger/types.md",
            "Functions and Macros" => "api-dagger/functions.md",
        ],
        "TimespanLogging API" => [
            "Types" => "api-timespanlogging/types.md",
            "Functions and Macros" => "api-timespanlogging/functions.md",
        ],
        "DaggerWebDash API" => [
            "Types" => "api-daggerwebdash/types.md",
            "Functions and Macros" => "api-daggerwebdash/functions.md",
        ],
    ]
)

deploydocs(;
    repo="github.com/JuliaParallel/Dagger.jl",
)
