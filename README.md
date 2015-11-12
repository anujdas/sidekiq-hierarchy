# Sidekiq::Hierarchy

Sidekiq-hierarchy is a gem that implements parent-child hierarchies between sidekiq jobs. Via several middlewares, it allows tracking complete workflows of multiple levels of sidekiq jobs, even across network calls, so long as a shared redis host is available.

You may want to use sidekiq-hierarchy if you:

- have complex (or simple) hierarchies of jobs triggering other jobs
- want to understand timing breakdowns (enqueued, run, and completed times) per job and per workflow
- are investigating how job requeues and retries impact your runtimes, e.g., to maintain SLAs
- would like to perform actions on job and workflow status changes via callbacks, for instance providing progress feedback or statistical trend data
- need to pass arbitrary data between parent and child jobs, in order to implement, e.g., prioritized workflows, or fail-fast workflows
- trigger jobs via network calls and want insight into the call graphs

![Web UI](img/in_progress_workflow.png?raw=true)

Disclaimer: Sidekiq-hierarchy supports MRI 2.0+ and JRuby; it may (and probably does) work on MRI 1.9, but this configuration is untested as the Sidekiq's unit testing support does not extend to it.

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

You're done! Any new instances of your root worker  will now record their child hierarchies. Some examples to try, given a root `JID`:

```ruby
# > root_jid = RootWorker.perform_async
# => "11c3ec3df251ebb646f910d7"

> workflow = Sidekiq::Hierarchy::Workflow.find_by_jid(root_jid)
=> <Sidekiq::Hierarchy::Workflow...>

> workflow.status  # [:running, :complete, :failed]
=> :complete
> [workflow.enqueued_at, workflow.run_at, workflow.complete_at]
=> [2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800, 2015-11-11 15:01:32 -0800]
> workflow.jobs.count  # lazily eval'd
=> 33
> workflow.jobs.map(&:jid)
=> ["11c3ec3df251ebb646f910d7", "f003db430a0eae99d72f1b7a", "bc2cf8f3de3b87f9a4c3c10e", ...]

> root_job = workflow.root
=> <Sidekiq::Hierarchy::Job...>
> root_job.info  # configurable hash
{"class"=>"WebWorker", "queue"=>"default"}
> [root_job.enqueued_at, root_job.run_at, root_job.complete_at]
=> [2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800, 2015-11-11 15:00:42 -0800]

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

## API

Todo

## Callbacks

Todo

## Advanced Options

Todo

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-hierarchy'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-hierarchy

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
