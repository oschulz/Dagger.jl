# Dagger: A framework for out-of-core and parallel execution

Dagger.jl is a framework for parallel computing across all kinds of resources,
like CPUs and GPUs, and across multiple threads and multiple servers.

-----

## Quickstart: Task Spawning

For more details: [Task Spawning](@ref)

### Launch a task

If you want to call a function `myfunc` with arguments `arg1`, `arg2`, `arg3`,
and keyword argument `color=:red`:

```julia
function myfunc(arg1, arg2, arg3; color=:blue)
    arg_total = arg1 + arg2 * arg3
    printstyled(arg_total; color)
    return arg_total
end
t = Dagger.@spawn myfunc(arg1, arg2, arg3; color=:red)
```

This will run the function asynchronously; you can fetch its result with
`fetch(t)`, or just wait on it to complete with `wait(t)`. If the call to
`myfunc` throws an error, `fetch(t)` will rethrow it.

If running Dagger with multiple workers, make sure to define `myfunc` with
`@everywhere` from the `Distributed` stdlib.

### Launch a task with an anonymous function

It's more convenient to use `Dagger.spawn` for anonymous functions. Taking the
previous example, but using an anonymous function instead of `myfunc`:

```julia
Dagger.spawn((arg1, arg2, arg3; color=:blue) -> begin
    arg_total = arg1 + arg2 * arg3
    printstyled(arg_total; color)
    return arg_total
end, arg1, arg2, arg3; color=:red)
```

`spawn` is functionally identical to `@spawn`, but can be more or less
convenient to use, depending on what you're trying to do.

### Launch many tasks and wait on them all to complete

`@spawn` participates in `@sync` blocks, just like `@async` and
`Threads.@spawn`, and will cause `@sync` to wait until all the tasks have
completed:

```julia
@sync for result in simulation_results
    Dagger.@spawn send_result_to_database(result)
end
nresults = length(simulation_results)
wait(Dagger.@spawn update_database_result_count(nresults))
```

Above, `update_database_result_count` will only run once all
`send_result_to_database` calls have completed.

Note that other APIs (including `spawn`) do not participate in `@sync` blocks.

### Run a task on a specific Distributed worker

Dagger uses [Scopes](@ref) to control where tasks can execute. There's a handy
constructor, `Dagger.scope`, that makes defining scopes easy:

```julia
w2_only = Dagger.scope(worker=2)
Dagger.@spawn scope=w2_only myfunc(arg1, arg2, arg3; color=:red)
```

Now the launched task will *definitely* execute on worker 2 (or if it's not
possible to run on worker 2, Dagger will throw an error when you try to `fetch`
the result).

-----

## Quickstart: Data Management

For more details: [Data Management](@ref)

### Operate on mutable data in-place

Dagger usually assumes that you won't be modifying the arguments passed to your
functions, but you can tell Dagger you plan to mutate them with `@mutable`:

```julia
A = Dagger.@mutable rand(1000, 1000)
Dagger.@spawn accumulate!(+, A, A)
```

This will lock `A` (and any tasks that use it) to the current worker. You can
also lock it to a different worker by creating the data within a task:

```julia
A = Dagger.spawn() do
    Dagger.@mutable rand(1000, 1000)
end
```

or by specifying the `worker` argument to `@mutable`:

```julia
A = Dagger.@mutable worker=2 rand(1000, 1000)
```

### Operate on distributed data

Often we want to work with more than one piece of data; the common case of
wanting one piece of data per worker is easy to do by using `@shard`:

```julia
X = Dagger.@shard myid()
```

This will execute `myid()` independently on every worker in your Julia
cluster, and place references to each within a `Shard` object called `X`. We
can then use `X` in task spawning, but we'll only get the result of
`myid()` that corresponds to the worker that the task is running on:

```julia
for w in workers()
    @show fetch(Dagger.@spawn scope=Dagger.scope(worker=w) identity(X))
end
```

The above should print the result of `myid()` for each worker in `worker()`, as
`identity(X)` receives only the value of `X` specific to that worker.

### Reducing over distributed data

Reductions are often parallelized by reducing a set of partitions on each
worker, and then reducing those intermediate reductions on a single worker.
Dagger supports this easily with `@shard`:

```julia
A = Dagger.@shard rand(1:20, 10000)
temp_bins = Dagger.@shard zeros(20)
hist! = (bins, arr) -> for elem in arr
    bins[elem] += 1
end
wait.([Dagger.@spawn scope=Dagger.scope(;worker) hist!(temp_bins, A) for worker in procs()])
final_bins = sum(map(b->fetch(Dagger.@spawn copy(b)), temp_bins); dims=1)[1]
```

Here, `A` points to unique random arrays, one on each worker, and `temp_bins`
points to a set of histogram bins on each worker. When we `@spawn hist!`,
Dagger passes in the random array and bins for only the specific worker that
the task is run on; i.e. a call to `hist!` that runs on worker 2 will get a
different `A` and `temp_bins` from a call to `hist!` on worker 3. All of the
calls to `hist!` may run in parallel.

By using `map` on `temp_bins`, we then make a copy of each worker's bins that
we can safely return back to our current worker, and sum them together to get
our total histogram.

-----

## Quickstart: File IO

Dagger has support for loading and saving files that integrates seamlessly with
its task system, in the form of `Dagger.File` and `Dagger.tofile`.

!!! warn
    These functions are not yet fully tested, so please make sure to take backups of any files that you load with them.

### Loading files from disk

In order to load one or more files from disk, Dagger provides the `File`
function, which creates a lazy reference to a file:

```julia
f = Dagger.File("myfile.jls")
```

`f` is now a lazy reference to `"myfile.jls"`, and its contents can be loaded
automatically by just passing the object to a task:

```julia
wait(Dagger.@spawn println(f))
# Prints the loaded contents of the file
```

By default, `File` assumes that the file uses Julia's Serialization format;
this can be easily changed to assume Arrow format, for example:

```julia
using Arrow
f = Dagger.File("myfile.arrow"; serialize=Arrow.write, deserialize=Arrow.Table)
```

### Writing data to disk

Saving data to disk is as easy as loading it; `tofile` provides this capability
in a similar manner to `File`:

```julia
A = rand(1000)
f = Dagger.tofile(A, "mydata.jls")
```

Like `File`, `f` can still be used to reference the file's data in tasks. It is
likely most useful to use `tofile` at the end of a task to save results:

```julia
function make_data()
    A = rand(1000)
    return Dagger.tofile(A, "mydata.jls")
end
fetch(Dagger.@spawn make_data())
# Data was also written to "mydata.jls"
```

`tofile` takes the same keyword arguments as `File`, allowing the format of
data on disk to be specified as desired.

-----

## Quickstart: Distributed Arrays

Dagger's `DArray` type represents a distributed array, where a single large
array is implemented as a set of smaller array partitions, which may be
distributed across a Julia cluster.

For more details: [Distributed Arrays](@ref)

### Distribute an existing array

Distributing any kind of array into a `DArray` is easy, just use `distribute`,
and specify the partitioning you desire with `Blocks`. For example, to
distribute a 16 x 16 matrix in 4 x 4 partitions:

```julia
A = rand(16, 16)
DA = distribute(A, Blocks(4, 4))
```

### Allocate a distributed array directly

To allocate a `DArray`, just pass your `Blocks` partitioning object into the
appropriate allocation function, such as `rand`, `ones`, or `zeros`:

```julia
rand(Blocks(20, 20), 100, 100)
ones(Blocks(20, 100), 100, 2000)
zeros(Blocks(50, 20), 300, 200)
```

### Convert a `DArray` back into an `Array`

To get back an `Array` from a `DArray`, just call `collect`:

```julia
DA = rand(Blocks(32, 32), 256, 128)
collect(DA) # returns a `Matrix{Float64}`
```
