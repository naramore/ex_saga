defmodule ExSaga.RetryTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest ExSaga.Retry

  alias ExSaga.Generators, as: Gen
  alias ExSaga.{Event, Retry}

  describe "ExSaga.Retry.start_retry/3" do
    property "should return [:starting, :retry, :init] event when uninitialized" do
      check all %{effects_so_far: effects} = acc <- Gen.retry_accumulator(length: 1..3),
                event <- Gen.event() do
        acc = %{acc | effects_so_far: %{effects | __retry__: %{}},
                      on_retry: ExSaga.RetryWithExpoentialBackoff,
                      abort?: false}
        next_event = Retry.start_retry(acc, event, [])
        assert match?(%Event{name: [:starting, :retry, :init]}, next_event)
      end
    end

    property "should return [:starting, :retry, :handler] event when already initialized" do
      check all %{effects_so_far: effects} = acc <- Gen.retry_accumulator(length: 1..3),
                retry_state <- Gen.retry_state(),
                event <- Gen.event() do
        acc = %{acc | effects_so_far: %{effects | __retry__: %{event.name => retry_state}},
                      on_retry: ExSaga.RetryWithExpoentialBackoff,
                      abort?: false}
        next_event = Retry.start_retry(acc, event, [])
        assert match?(%Event{name: [:starting, :retry, :init]}, next_event)
      end
    end

    property "should return event for any non-aborting input" do
      check all acc <- Gen.retry_accumulator(length: 1..3),
                event <- Gen.event(),
                opts <- list_of(tuple({atom(:alphanumeric), Gen.simple()}), length: 1..3) do
        acc = %{acc | on_retry: ExSaga.RetryWithExpoentialBackoff,
                      abort?: false}
        assert match?(%Event{}, Retry.start_retry(acc, event, opts))
      end
    end

    property "should return nil for any aborting input" do
      check all acc <- Gen.retry_accumulator(length: 1..3),
                event <- Gen.event(),
                opts <- list_of(tuple({atom(:alphanumeric), Gen.simple()}), length: 1..3) do
        acc = %{acc | on_retry: ExSaga.RetryWithExpoentialBackoff,
                      abort?: true}
        assert is_nil(Retry.start_retry(acc, event, opts))
      end
    end
  end

  describe "ExSaga.Retry.step/3" do
    property "returns [:completed, :retry, _] event after [:starting, :retry, _] event" do
      check all effects <- Gen.effects(length: 1..3),
                event_suffix <- member_of([:init, :handler]),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: [],
                  hooks_left: [],
                  update: nil,
                  abort?: false
                },
                retry_opts <- Gen.retry_opts(length: 1..3),
                event <- Gen.event() do
        event = %{event | context: {0, retry_opts}}
        result = Retry.step(acc, %{event | name: [:starting, :retry, event_suffix]})
        assert match?({:continue, %Event{name: [:completed, :retry, ^event_suffix]}, _}, result)
      end
    end

    property "returns [:completed, :retry, :update] event after [:starting, :retry, :update] event" do
      check all effects <- Gen.effects(length: 1..3),
                retry_updates <- list_of(Gen.retry_update(), length: 0..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: retry_updates,
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                name <- Gen.full_name(length: 1..3),
                result <- Gen.retry_result() do
        event = %{event | context: {name, ExSaga.RetryWithExpoentialBackoff, result}}
        result = Retry.step(acc, %{event | name: [:starting, :retry, :update]})
        assert match?({_, %Event{name: [:completed, :retry, :update]}, _}, result)
      end
    end

    property "returns [:starting, :retry, :handler] event after successful [:completed, :retry, :init] event" do
      check all effects <- Gen.effects(length: 1..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: [],
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                state <- Gen.retry_state(),
                opts <- Gen.retry_opts(length: 1..3) do
        event = %{event | name: [:completed, :retry, :init],
                          context: {:ok, state, opts}}
        result = Retry.step(acc, event, [])
        assert match?({:continue, %Event{name: [:starting, :retry, :handler]}, _}, result)
      end
    end

    property "returns [:starting, :error_handler] event after failed [:completed, :retry, _] event" do
      check all effects <- Gen.effects(length: 1..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: [],
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                reason <- Gen.reason() do
        event = %{event | name: [:completed, :retry, :init],
                          context: {:error, reason}}
        result = Retry.step(acc, event, [])
        assert match?({:continue, %Event{name: [:starting, :error_handler]}, _}, result)
      end
    end

    property "returns [:starting, :retry, :update] event after [:completed, :retry, :handler] event w/ :retry" do
      check all effects <- Gen.effects(length: 1..3),
                retry_updates <- list_of(Gen.retry_update(), length: 1..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: retry_updates,
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                name <- Gen.full_name(length: 1..3),
                result <- tuple({constant(:retry), Gen.wait(), Gen.retry_state()}) do
        event = %{event | context: {name, ExSaga.RetryWithExpoentialBackoff, result}}
        result = Retry.step(acc, %{event | name: [:completed, :retry, :handler]})
        assert match?({_, %Event{name: [:starting, :retry, :update]}, _}, result)
      end
    end

    property "returns [:starting, :retry, :update] event after [:completed, :retry, :handler] event w/ :noretry" do
      check all effects <- Gen.effects(length: 1..3),
                retry_updates <- list_of(Gen.retry_update(), length: 1..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: retry_updates,
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                name <- Gen.full_name(length: 1..3),
                result <- tuple({constant(:noretry), Gen.retry_state()}) do
        event = %{event | context: {name, ExSaga.RetryWithExpoentialBackoff, result}}
        result = Retry.step(acc, %{event | name: [:completed, :retry, :handler]})
        assert match?({_, %Event{name: [:starting, :retry, :update]}, _}, result)
      end
    end

    property "returns [:starting, :retry, :update] event after [:completed, :retry, :update] event w/ updates" do
      check all effects <- Gen.effects(length: 1..3),
                retry_updates <- list_of(Gen.retry_update(), length: 1..3),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: retry_updates,
                  hooks_left: [],
                  update: {:retry, []},
                  abort?: false
                },
                event <- Gen.event(),
                result <- Gen.retry_update_result() do
        result = Retry.step(acc, %{event | name: [:completed, :retry, :update],
                                           context: result})
        assert match?({_, %Event{name: [:starting, :retry, :update]}, _}, result)
      end
    end

    property "returns {:retry | :noreply, _, _} after [:completed, :retry, :handler] event w/o updates" do
      check all effects <- Gen.effects(length: 1..3),
                update <- Gen.retry_result(),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: [],
                  hooks_left: [],
                  update: update,
                  abort?: false
                },
                event_suffix <- member_of([:handler, :update]),
                event <- Gen.event() do
        event = %{event | name: [:completed, :retry, event_suffix]}
        result = Retry.step(acc, event, [])
        assert match?({:retry, _, _}, result) or match?({:noretry, _, _}, result)
      end
    end

    property "returns {:retry | :noretry, _, _} after [:completed, :retry, :update] event w/o updates" do
      check all effects <- Gen.effects(length: 1..3),
                update <- Gen.retry_result(),
                acc = %{
                  effects_so_far: effects,
                  on_retry: ExSaga.RetryWithExpoentialBackoff,
                  retry_updates_left: [],
                  hooks_left: [],
                  update: update,
                  abort?: false
                },
                event <- Gen.event(),
                context <- Gen.retry_update_result() do
        result = Retry.step(acc, %{event | name: [:completed, :retry, :update],
                                           context: context}, [])
        assert match?({:retry, _, _}, result) or match?({:noretry, _, _}, result)
      end
    end

    property "returns event when given valid inputs" do
      check all acc <- Gen.retry_accumulator(length: 1..3),
                event <- Gen.event(),
                opts <- Gen.retry_opts(length: 1..3) do
        result = Retry.step(acc, event, opts)
        assert match?({s, %Event{}, %{}} when s in [:continue, :retry, :noretry], result)
      end
    end
  end
end
