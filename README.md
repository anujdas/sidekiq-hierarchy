# Sidekiq::Hierarchy


[![Build Status](https://travis-ci.org/anujdas/sidekiq-hierarchy.png?branch=master)](https://travis-ci.org/anujdas/sidekiq-hierarchy)

[![Gem Version](https://badge.fury.io/rb/sidekiq-hierarchy.png)](http://badge.fury.io/rb/sidekiq-hierarchy)

Sidekiq-hierarchy is a gem that implements parent-child hierarchies between sidekiq jobs. Via several middlewares, it allows tracking complete workflows of multiple levels of sidekiq jobs, even across network calls, so long as a shared redis host is available.

You may want to use sidekiq-hierarchy if you:

- have complex (or simple) hierarchies of jobs triggering other jobs
- want to understand timing breakdowns (enqueued, run, and completed times) per job and per workflow
- are investigating how job requeues and retries impact your runtimes, e.g., to maintain SLAs
- would like to perform actions on job and workflow status changes via callbacks, for instance providing progress feedback or statistical trend data
- need to pass arbitrary data between parent and child jobs, in order to implement, e.g., prioritized workflows, or fail-fast workflows
- trigger jobs via network calls and want insight into the call graphs

![Web UI](img/in_progress_workflow.png?raw=true)

Disclaimer: Sidekiq-hierarchy supports Sidekiq 3.x and 4.x, and thus MRI 2.0+ and JRuby; it may work on MRI 1.9, but this configuration is untested as Sidekiq's unit testing support does not extend to it.

## Table of Contents

- [Sidekiq::Hierarchy](#sidekiqhierarchy)
    - [Table of Contents](#table-of-contents)
    - [Quickstart](#quickstart)
    - [Web Interface](#web-interface)
    - [Architecture and API](#architecture-and-api)
    - [Callbacks](#callbacks)
    - [Network integration](#network-integration)
    - [Advanced Options](#advanced-options)
        - [Additional Job Info](#additional-job-info)
        - [CompleteSet and FailedSet](#completeset-and-failedset)
        - [Separate Redis Storage](#separate-redis-storage)
    - [More Examples](#more-examples)
        - [Fail-fast workflow cancellation](#fail-fast-workflow-cancellation)
        - [Workflow Metrics Dashboard](#workflow-metrics-dashboard)
    - [Installation](#installation)
    - [Development](#development)
    - [License](#license)

## Quickstart

Sidekiq-hierarchy is designed to be as unobtrusive as possible. The simplest possible use case, in which jobs trigger other jobs directly (via `#perform_async`), can be realized via a few lines of code. First, set up Sidekiq and make sure that the gem is installed (see Installation, below). Then:

- Add the Sidekiq middlewares to your global Sidekiq configuration, usually in an initializer (e.g., `config/initializers/sidekiq.rb`):

```ruby
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Client::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Client::Middleware
  end
  config.server_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Server::Middleware
  end
end
```

Note that the Client middleware must be added to both the server and client configs.

_Since instrumentation occurs in these middlewares, other middlewares you write that make use of Sidekiq-hierarchy's capabilities must be nested appropriately (inside or outside, depending on whether they make use of workflow data-passing or they modify queuing behaviour)._

- Mark your workflow entry points, the jobs that are the root nodes of your work trees. Only the roots need to be modified: any children (or children or children, etc.) will automatically inherit the setting (though it won't hurt if you add them too). Simply append to the sidekiq_options in the worker class:

```ruby
class RootWorker
  include Sidekiq::Worker
  sidekiq_options workflow: true

# def perform(*args)
#   5.times do |n|
#     ChildWorker.perform_async(n, *args)
#   end
# end
```

The main concern is Redis storage space: if you are fine instrumenting all jobs (because your Redis instance is huge, or your job throughput is not very high, or you're debugging), you can set this in your global options:

```ruby
Sidekiq.default_worker_options = { 'workflow' => true }
```

You're done! Any new instances of your root worker  will now record their child hierarchies.

---

Some examples to try, given a root `JID`:

```ruby
# > root_jid = RootWorker.perform_async
# => "11c3ec3df251ebb646f910d7"

> workflow = Sidekiq::Hierarchy::Workflow.find_by_jid(root_jid)
=> <Sidekiq::Hierarchy::Workflow...>

> workflow.status  # [:running, :complete, :failed]
=> :complete

> [workflow.enqueued_at, workflow.run_at, workflow.complete_at]
=> [2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800, 2015-11-11 15:01:32 -0800]
```
```ruby
> workflow.job_count  # stored value, no iteration necessary
=> 33

> workflow.jobs.count  # lazily eval'd
=> 33

> workflow.jobs.map(&:jid)
=> ["11c3ec3df251ebb646f910d7", "f003db430a0eae99d72f1b7a", "bc2cf8f3de3b87f9a4c3c10e", ...]

> workflow.finished_job_count
=> 33
```
```ruby
> root_job = workflow.root
=> <Sidekiq::Hierarchy::Job...>

> root_job.info  # configurable hash
{"class"=>"WebWorker", "queue"=>"default"}

> [root_job.enqueued_at, root_job.run_at, root_job.complete_at]
=> [2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800]
```
```ruby
> root_job.leaf?  # tree traversal helpers
 => false
 
> root_job.children
 => [<Sidekiq::Hierarchy::Job...>, <Sidekiq::Hierarchy::Job...>, ...]
 
> root_job.leaves.count
=> 19

> root_job.leaves.last.root == root_job
=> true
```

## Web Interface

Sidekiq-hierarchy comes with a full-featured web UI that integrates into the standard sidekiq-web interface. Use it to investigate your workflows without dropping to the console. Keep in mind, displaying workflows is expensive (Redis-command-count-wise), so it may not be the best idea to leave this live-polling a very large workflow on production over the weekend...

If you've already got sidekiq-web running, just

```ruby
require 'sidekiq/hierarchy/web'
```

and you're done; click the "Hierarchy" tab on the web UI and dig in. If you don't, follow the steps at https://github.com/mperham/sidekiq/wiki/Monitoring#web-ui first, then add the `require`. Among the things you can do:

- See overall metrics and search for jobs/workflows:
![Dashboard](img/dashboard.png?raw=true) 

- Summarize running, complete, and failed workflows:
![Workflow set](img/workflow_set.png?raw=true)

- Introspect jobs and workflows
![Job](img/failed_workflow.png?raw=true)
![Workflow](img/job.png?raw=true)

And more! Try out live polling for even more fun.

## Architecture and API

Most of the API is contained in the `Sidekiq::Hierarchy::Job`, `Sidekiq::Hierarchy::Workflow`, and `Sidekiq::Hierarchy::WorkflowSet` classes. At a high level,

- Information is stored as a number of `Job`s that are identified by their JID (job id, randomly generated by Sidekiq).
- Each `Job` can have one (optional) parent `Job` and any number of children `Job`s.
- Together, one job tree constitutes a `Workflow`; workflow data is actually stored on the root `Job` node in Redis, but the workflow class provides a handy abstraction.
- Workflows are organized by status into the three `WorkflowSet`s: the obviously-named`RunningSet`, `CompleteSet`, and `FailedSet`.

Explore the classes to learn more you can access, including:

- current `#status` (`:enqueued`, `:running`, `:complete`, `:requeued`, `:failed`)
- timestamps for all status changes (`#enqueued_at`, `#run_at`, etc.)
- tree exploration (`#root`, `#parent`, `#children`, `#leaf?`, etc.)
- lazy enumerators over jobs and workflows (`Workflow#jobs`, `WorkflowSet#each`)
- current workflow and job context (`Sidekiq::Hierarchy.current_workflow`, `.current_job`)

Each `Workflow` can be treated as a Redis-backed hash (all values will be coerced to strings). Combined with the fact that the current workflow context can always be accessed via `Sidekiq::Hierarchy.current_workflow` (nil if not in a workflow), you can pass arbitrary information through a work tree.

---

As a quick example:

Say you wanted to push child jobs to a higher-priority queue if the root job was triggered by an admin user. We can implement this trivially using the Sidekiq-hierarchy infrastructure:

- When the root job is triggered, let's store the "high-priority" flag on the workflow.
```ruby
class RootWorker
  include Sidekiq::Worker
  sidekiq_options workflow: true
  def perform(user_id)
    if User.find(user_id).admin?
      # value will be turned into a string anyways
      Sidekiq::Hierarchy.current_workflow[:important] = '1'
    end
    5.times { ChildWorker.perform_async }
  end
end
```

- Now let's write a simple client middleware to read the flag and act accordingly:
```ruby
class PriorityMiddleware
  def call(worker_class, msg, queue, redis_pool)
    if Sidekiq::Hierarchy.current_workflow[:important]
      queue = :ultrahigh  # override worker's preset queue
    end
    yield worker_class, msg, queue, redis_pool
  end
end
```

- Make sure the middleware is nested **inside** the Sidekiq-hierarchy client middleware in the Sidekiq config.

That's all it takes! 

## Callbacks

Sidekiq-hierarchy implements a simple pub/sub events system that currently publishes on two topics: `Sidekiq::Hierarchy::Notifications::JOB_UPDATE` and `Sidekiq::Hierarchy::Notifications::WORKFLOW_UPDATE`. These topics see messages whenever a status change occurs for any job or workflow, respectively.

Observers on `:job_update` are called with `(job, status, old_status)`, while `:workflow_update` observers receive `(workflow, status, old_status)`. An observer can be anything that supports a #call method with the necessary signature: a class instance will suffice, as will a simple `Proc`. 

To register an observer, add it to the global callback registry at any point (initialization usually makes the most sense). For example, to subscribe to the `:job_update` event, you could do:

```ruby
class JobPrinter
  def call(job, status, old_status)
    Rails.logger.log "#{job.jid} switched from #{old_status} to #{status}"
  end
end
  
end
Sidekiq::Hierarchy.callback_registry
  .subscribe(Sidekiq::Hierarchy::Notifications::JOB_UPDATE, JobPrinter.new)
```

or

```ruby
job_printer = Proc.new do |job, status, old_status|
  Rails.logger.log "#{job.jid} switched from #{old_status} to #{status}"
end
Sidekiq::Hierarchy.callback_registry
  .subscribe(Sidekiq::Hierarchy::Notifications::JOB_UPDATE, job_printer)

```

Callbacks are triggered sequentially and synchronously, so if you are doing anything slow (e.g., a network call), you might consider moving it to an async task.

Note: Sidekiq-hierarchy makes use of callbacks internally to drive some of its own logic as well. Each subscriber is wrapped in an exception handler to ensure that all subscribers will run at each event publication, even if one or more raise errors.

## Network integration

A somewhat common pattern with Sidekiq is moving network calls to async jobs, preventing the network's synchronous nature from holding up workers. However, if the network endpoint triggers additional jobs, those child will no longer be linked to their parent, as the worker context is lost. Sidekiq-hierarchy solves this with a set of two optional middlewares: one for Rack (deciphering context from inbound requests) and one instrumenting Faraday (passing context in HTTP headers). Together, they transparently bridge the network gap, ensuring that jobs triggering other jobs over a network hop are recorded correctly.

The network integration is not loaded by default. To use it, require `sidekiq/hierarchy/rack/middleware` and `sidekiq/hierarchy/faraday/middleware` (making sure `Rack` and `Faraday` are loaded), then insert them in the appropriate places. For Rails, the Rack middleware will usually go in `config/application.rb`:
```ruby
class Application < Rails::Application
  # ...
  config.middleware.use Sidekiq::Hierarchy::Rack::Middleware
  # ...
end
```

For Faraday, the connection object should be modified before use:
```ruby
Faraday.new do |f|
  # ...
  f.use Sidekiq::Hierarchy::Faraday::Middleware
  # ...
end
```

In the background, Sidekiq-hierarchy inserts and decodes two headers:

- Sidekiq-Job: the job id of the parent worker, if any
- Sidekiq-Workflow: the workflow JID, if tracking is enabled (`workflow: true` in sidekiq_options)

Even if you are not using Faraday, adding these headers should be easy with your network library of choice.

## Advanced Options

There are a couple of additional configuration options you may want to use, depending on your needs:

###Additional Job Info

By default, Sidekiq-hierarchy only retains two pieces of information from each job, namely the class and queue. A full job hash in Sidekiq is much richer, but storing the full thing will take significantly more space (especially if you enable backtrace recording in the worker options). If there are additional pieces you need (for instance, the argument list could be quite useful), you can specify these per job:

```ruby
  sidekiq_options workflow_keys: ['args']
```

The list of keys must be an array of strings, which will be merged with `['class', 'queue']` (the default).

###CompleteSet and FailedSet

While the `RunningSet` is never pruned, so that in-progress workflows will never lose information, completed and failed workflows must be pruned to prevent running out of space in Redis (though note, all keys used expire in one month, so don't expect data to stick around past that time regardless!). Sidekiq itself does not have this issue, since jobs are thrown away after completion, but this is obviously impossible for Sidekiq-hierarchy (else workflows would lose jobs as they completed).

Two pruning strategies are employed, running on every workflow insertion: one which trims workflows older than a certain time, one which trims workflows past a certain count. These limits can be accessed as `CompleteSet.timeout` and `CompleteSet.max_workflows` (likewise for `FailedSet`, which shares the limits). These are set from global Sidekiq settings as follows:

- `timeout`: `:dead_timeout_in_seconds` setting, also used by Sidekiq to prune dead jobs (default 6 months)
- `max_workflows`: the first of `:dead_max_workflows` and `:dead_max_jobs`, whichever is set; the latter is used internally by Sidekiq to prune dead jobs (`:dead_max_jobs` default 10,000)

###Separate Redis Storage

Depending on the size of your workflows, the default storage of all information in Sidekiq's redis instance may not be right for you. Sidekiq-hierarchy makes an effort to use as little overhead as possible, about 200 bytes per job on average. Depending on factors like the length of your worker class names, the additional job info you choose to store, and the number of children each job has, you may see more or less space usage; test on your own data to be sure.

Because this data is usually less critical and more disposable than your Sidekiq queues or other Redis information, Sidekiq-hierarchy offers the option of using a separate Redis instance/cluster to store its metadata. This has three big advantages over the default of `Sidekiq.redis`:

- prevents memory pressure on your primary Redis instance,
- permits usage of a less robust, smaller, and/or cheaper Redis server for hierarchy data,
- and most importantly, allows sharing of the Redis instance between services, letting you track workflows between services (provided that network integration is set up).

Sidekiq-hierarchy accepts either a raw Redis connection or a ConnectionPool, though a ConnectionPool with appropriate size and timeout is highly recommended (see [mperham/connection_pool](https://github.com/mperham/connection_pool) for details). In either case, configuration can be performed at initialization:

```ruby
# with a bare Redis connection
alt_redis = Redis.new(db: 1)
Sidekiq::Hierarchy.redis = alt_redis

# with a Redis connection pool
conn_pool = ConnectionPool.new(size: 10, timeout: 2) { Redis.new(host: 'data-redis-master') }
Sidekiq::Hierarchy.redis = conn_pool
```

Using the same redis server with multiple services that talk to one another via async jobs is a quick and dirty way to get a map of your SOA, as long as you are aware of its limitations (no tracking connections not initiated through Sidekiq).

## More Examples

These are just a few ways in which Sidekiq-hierarchy could help you:

###Fail-fast workflow cancellation

Let's say you want to enable workflow cancellation: if one job in a workflow fails, you can safely avoid running any of the others. Assuming Sidekiq-hierarchy is installed and running, we can do this with two middlewares.

On the server side, _inside_ the hierarchy middleware to ensure variables are set:
```ruby
class FailFast::ServerMiddleware
  def call(worker, job, queue)
    current_job = Sidekiq::Hierarchy.current_job
    workflow = Sidekiq::Hierarchy.current_workflow
    return if workflow && workflow[:fail_fast]
    
    yield
    
  rescue => e
    if workflow && current_job.failed?
      workflow[:fail_fast] = '1'
    end
    raise  # make sure to propagate exception up
  end
end
```

On the client side, _inside_ the hierarchy middleware (remember to install client middleware on both the server and client):
```ruby
class FailFast::ClientMiddleware
  def call(worker_class, msg, queue, redis_pool)
    workflow = Sidekiq::Hierarchy.current_workflow
    return false if workflow && workflow[:fail_fast]  # don't bother queueing
    yield
  end
end
```

The server middleware will flag the workflow on any non-retriable failure. Meanwhile, the client middleware pre-emptively cancels queuing any job according to the flag, and the server middleware refuses to execute jobs on cancelled workflows.

###Workflow Metrics Dashboard

Every workflow has a canonical representation given by `#as_json`/`#to_s` (depending on desired format), which will be the same for a given set of tree of jobs regardless of their actual queuing and execution order. This representation disambiguates by job class and child set. For example, a `ParentWorker` that kicked off two `ChildWorker`s would have the representation

    "{\"k\":\"ParentWorker\",\"c\":[{\"k\":\"ChildWorker\",\"c\":[]},{\"k\":\"ChildWorker\",\"c\":[]}]}"

Let's put workflow metrics in [StatsD](https://github.com/etsy/statsd), an easy-to-use metrics collector. Assuming we've already set up our statsd client as `$statsd`, we can push the timing info collected by Sidekiq-hierarchy with a few lines of code in an initializer (plugging into the pub/sub system):

```ruby
require 'zlib'

metrics_pusher = Proc.new do |workflow, status, old_status|
  if status == :complete
    uniq_repr = Zlib.crc32(workflow.to_s)
    time_in_ms = (workflow.complete_at - workflow.run_at) * 1000
    $statsd.timing("workflows:#{uniq_repr}", time_in_ms)
  end
end

Sidekiq::Hierarchy.callback_registry.subscribe(Sidekiq::Hierarchy::Notifications::WORKFLOW_UPDATE, metrics_pusher)
```

Using something like [Graphite](http://graphite.wikidot.com/), we can then analyze the results in realtime, accessing stats like minimum, mean, maximum, and 95th percentile runtime. You'll probably want to keep a CRC32 -> workflow mapping handy; a simple hashmap (or Redis hash, hint hint) will suffice nicely.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-hierarchy'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-hierarchy

If you want to use the network bridge, you'll need `faraday` as well; if you're using the web UI, make sure `sinatra` is installed.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. 

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
