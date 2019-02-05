# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased
### Added
- stepable protocol to be used as the foundation of saga executions
- error handling behaviour + default (re-throw/raise/exit)
- retry behaviour + default (exponential backoff)
- stage event hooks
- events to represent all occurances during a saga execution
- Step.mstep_from/3 (step from another stage's result), mstep_at/3 (step from a given acc + event), mstep_after/3 (step from a given list of events)
- dry run logic for stepable executions (i.e. not executing and returning given value instead)
- stepper behaviour to reuse hook, retry, and error handling logic for `ExSaga.Stepable.step/3`
- `ExSaga.Stepable` implemented for stages (leaf nodes)
- `ExSaga.Stepable` implemented for sagas (pipelines)
