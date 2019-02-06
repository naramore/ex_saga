defmodule ExSaga.HookTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog
  doctest ExSaga.Hook

  alias ExSaga.Generators, as: Gen
  alias ExSaga.{Event, Hook}

  describe "ExSaga.Hook.merge_hooks/2" do
    property "should conserve hooks w/o overlapping extras" do
      check all acc <- Gen.hook_accumulator(length: 0..3),
                {hooks, extra_hooks} <- Gen.no_overlapping_hook_names(length: 0..3) do
        acc = %{acc | hooks: hooks}
        merged_hooks = Hook.merge_hooks(acc, extra_hooks: extra_hooks)
        assert length(merged_hooks) == length(hooks) + length(extra_hooks)
      end
    end

    property "should not conserve hooks w/ overlapping overrides" do
      check all acc <- Gen.hook_accumulator(length: 1..3),
                names = Enum.map(acc.hooks, & &1.name),
                extra_hooks <- Gen.extra_hooks_with_overrides(names, length: 0..3) do
        merged_hooks = Hook.merge_hooks(acc, extra_hooks: extra_hooks)
        assert length(merged_hooks) < length(acc.hooks) + length(extra_hooks)
      end
    end
  end

  describe "ExSaga.Hook.maybe_execute_hook/4" do
    property "should return hook result event when not rejected" do
      check all hook <- Gen.hook(),
                event <- Gen.event(),
                acc <- Gen.hook_accumulator(length: 1..3) do
        hook = %{hook | filter: fn _, _ -> true end}
        next_event = Hook.maybe_execute_hook(hook, event, acc, [])
        assert next_event.name == [:completed, :hook, hook.name]
      end
    end

    property "should return hook skipped event when rejected" do
      check all hook <- Gen.hook(),
                event <- Gen.event(),
                acc <- Gen.hook_accumulator(length: 1..3) do
        hook = %{hook | filter: fn _, _ -> false end}
        next_event = Hook.maybe_execute_hook(hook, event, acc, [])
        assert next_event.name == [:skipped, :hook, hook.name]
      end
    end

    property "should return hook skipped event on bad filter return" do
      check all hook <- Gen.hook(),
                event <- Gen.event(),
                acc <- Gen.hook_accumulator(length: 1..3),
                filter <-
                  one_of([
                    constant(fn _, _ -> :wrong end),
                    constant(fn _, _ -> raise %ArgumentError{} end),
                    constant(fn _, _ -> throw(:this_is_bad) end),
                    constant(fn _, _ -> exit(:not_good) end)
                  ]) do
        hook = %{hook | filter: filter}
        # this is just to black hole all the expected exit, raise and throw logs that will appear
        capture_log(fn ->
          next_event = Hook.maybe_execute_hook(hook, event, acc, [])
          assert next_event.name == [:skipped, :hook, hook.name]
        end)
      end
    end

    property "should always skip when filter dry run set to false" do
      check all hook <- Gen.hook(),
                event <- Gen.event(),
                acc <- Gen.hook_accumulator(length: 1..3) do
        skip_event = %{event | name: [:skipped, :hook, hook.name]}

        opts = [
          dry_run?: true,
          dry_run_results: [skip_event]
        ]

        next_event = Hook.maybe_execute_hook(hook, event, acc, opts)
        assert next_event.name == [:skipped, :hook, hook.name]
      end
    end

    property "should return dry run result when filter dry run set to true" do
      check all hook <- Gen.hook(),
                event <- Gen.event(),
                hook_result <- Gen.hook_result(),
                acc <- Gen.hook_accumulator(length: 1..3) do
        completed_event = %{event | name: [:completed, :hook, hook.name], context: hook_result}

        opts = [
          dry_run?: true,
          dry_run_results: [completed_event]
        ]

        next_event = Hook.maybe_execute_hook(hook, event, acc, opts)
        assert next_event.name == [:skipped, :hook, hook.name]
      end
    end
  end

  describe "ExSaga.Hook.step/3" do
    property "should return {nil, new_state} on last hook" do
      check all %{hooks_left: [h | _]} = acc <- Gen.hook_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- tuple({Gen.event(), Gen.hook_result()}) do
        acc = %{acc | hooks_left: h}
        assert match?({nil, _}, Hook.step(%{event | context: context}, acc))
      end
    end

    property "should return error on any hook error" do
      check all acc <- Gen.hook_accumulator(length: 1..3),
                event <- Gen.event(),
                next_event <- Gen.event(),
                result <-
                  one_of([
                    tuple({constant(:error), Gen.reason()}),
                    tuple({constant(:error), Gen.reason(), Gen.hook_state()})
                  ]),
                context = {next_event, result} do
        assert match?(
                 {%Event{name: nil, context: {:error, _, _, _}}, _},
                 Hook.step(%{event | context: context}, acc)
               )
      end
    end

    property "should reduce number of hooks by 1 if > 0" do
      check all acc <- Gen.hook_accumulator(length: 1..3),
                event <- Gen.event(),
                next_event <- Gen.event(),
                result <- one_of([constant(:ok), tuple({constant(:ok), Gen.hook_state()})]),
                context = {next_event, result} do
        {_, new_acc} = Hook.step(%{event | context: context}, acc)
        assert Enum.count(new_acc.hooks_left) + 1 == Enum.count(acc.hooks_left)
      end
    end

    property "should execute hook if any are left" do
      check all %{hooks_left: [h | hs]} = acc <- Gen.hook_accumulator(length: 1..3),
                event <- Gen.event(),
                next_event <- Gen.event(),
                result <- one_of([constant(:ok), tuple({constant(:ok), Gen.hook_state()})]),
                context = {next_event, result} do
        pid = self()

        acc = %{
          acc
          | hooks_left: [
              %{
                h
                | filter: fn _, _ -> true end,
                  fun: fn _, _ ->
                    send(pid, :hook_executed!)
                    :ok
                  end
              }
              | hs
            ]
        }

        {next_event, _} = Hook.step(%{event | context: context}, acc)

        receive do
          :hook_executed! ->
            assert next_event.name == [:completed, :hook, h.name]

          otherwise ->
            flunk("received: #{inspect(otherwise)}")
        after
          5000 -> flunk("timeout")
        end
      end
    end
  end
end
