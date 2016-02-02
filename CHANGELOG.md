# Change Log
All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [2.0.1] - 2016-02-02
### Added
- Support Sidekiq 4.x (tests pass and basic usage shows no errors)

## [2.0.1] - 2015-12-07
### Changed
- Collapse job tree in web UI in case of huge workflows, keeping things snappy
- Allow lazy loading of workflow subtrees in web UI for easy navigation of large trees
- Display jobs with their runtime instead of their time of completion to ease spotting of bottlenecks

## [2.0.0] - 2015-12-04
### Changed
- HTTP headers renamed to make roles more clear
- Thread locals renamed to make collisions less likely

### Added
- Track workflow timings directly to avoid iteration
- Record per-subtree job counts and finished job counts
- Add subtree iteration


## [1.1.0] - 2015-12-04
### Changed
- Use Sinatra template helpers to get template caching for views

### Added
- Support using a separate Redis connection/pool for workflow storage

## [1.0.0] - 2015-11-19
### Changed
- Nothing: bumping for first production release

## [0.1.4] - 2015-11-19
### Changed
- Added display of additional workflow keys (i.e., args) on web UI

## [0.1.3] - 2015-11-19
### Changed
- Fixed workflow-enabled jobs spawned by untracked jobs, which should therefore be considered roots on their own
- Modified web view to display total size of each workflow set

## [0.1.2] - 2015-11-17
### Changed
- Fixed compatibility with older Sidekiq/middleware versions that don't support alternate redis pools

## [0.1.1] - 2015-11-16
### Added
- This changelog

### Changed
- Allowed pushing to rubygems.org

## [0.1.0] - 2015-11-16
### Initial Release
- Shipping all launch features: tree tracking, network bridging, etc.
