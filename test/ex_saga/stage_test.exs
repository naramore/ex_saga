defmodule ExSaga.StageTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog
  doctest ExSaga.Stage

  alias ExSaga.Generators, as: Gen
  alias ExSaga.{Event, Stage, Step, Stepable, TestStage}

  describe "ExSaga.Stage.Stepable.step_from/3" do
    property "should return [:starting, :transaction] event given {:ok, effects}" do
      check all stage <- Gen.stage(length: 0..3),
                effects_so_far <- Gen.effects(length: 0..3),
                opts <- Gen.stepable_opts(length: 0..3) do
        result = Stepable.step_from(stage, {:ok, effects_so_far}, opts)
        assert match?({:continue, %Event{name: [:starting, :transaction]}, %Stage{}}, result)
      end
    end

    property "should return [:starting, :compensation] event given {:error, reason, effects}" do
      check all stage <- Gen.stage(length: 0..3),
                effects_so_far <- Gen.effects(length: 0..3),
                reason <- Gen.reason(),
                opts <- Gen.stepable_opts(length: 0..3) do
        result = Stepable.step_from(stage, {:error, reason, effects_so_far}, opts)
        assert match?({:continue, %Event{name: [:starting, :compensation]}, %Stage{}}, result)
      end
    end
  end

  describe "ExSaga.Stage.Stepable.step/3" do
    @tag :skip
    property "should return hook or next event given hook event" do
      flunk("not implemented yet...")
    end

    @tag :skip
    property "should return ??? given error handler event" do
      flunk("not implemented yet...")
    end

    @tag :skip
    property "should return ??? given [:starting, :transaction] event" do
      flunk("not implemented yet...")
    end

    @tag :skip
    property "should return ??? given [:completed, :transaction] event" do
      flunk("not implemented yet...")
    end

    @tag :skip
    property "should return ??? given [:starting, :compensation] event" do
      flunk("not implemented yet...")
    end

    @tag :skip
    property "should return ??? given [:completed, :compensation] event" do
      flunk("not implemented yet...")
    end

    property "should return valid output for valid input" do
      check all stage <- Gen.stage(length: 0..3),
                event <- Gen.event(),
                opts <- Gen.stepable_opts(length: 0..3) do
        result = Stepable.step(stage, event, opts)

        assert match?({:ok, %{}}, result) or match?({:error, _, %{}}, result) or match?({:continue, nil, %{}}, result) or
                 match?({:continue, %Event{}, %{}}, result)
      end
    end
  end

  describe "ExSaga.Step.mstep_from/3" do
    property "should return valid result given %ExSaga.Stage{}" do
      check all result <-
                  one_of([
                    tuple({constant(:ok), TestStage.test_effects()}),
                    tuple({member_of([:error, :abort]), Gen.reason(), TestStage.test_effects()})
                  ]),
                max_runs: 1000 do
        capture_log(fn ->
          {mstep_result, events} = Step.mstep_from(TestStage, result, [])
          assert Enum.all?(events, fn e -> match?(%Event{}, e) end)

          assert match?({:ok, %{}}, mstep_result) or
                   match?({status, _, %{}} when status in [:error, :abort], mstep_result)
        end)
      end
    end

    test "should successfully return when there are no problems" do
      capture_log(fn ->
        {mstep_result, events} = Step.mstep_from(TestStage, {:ok, %{}}, [])
        assert match?({:ok, %{ExSaga.TestStage => :success!}}, mstep_result)
        assert Enum.count(events) == 6

        assert match?(
                 [
                   %Event{name: [:starting, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]}
                 ],
                 events
               )
      end)
    end

    test "should return failure on the raising of an error" do
      capture_log(fn ->
        {mstep_result, events} =
          Step.mstep_from(TestStage, {:ok, %{txn: %{TestStage => {:raise, %ArgumentError{}}}}}, [])

        assert match?({:error, _, %{}}, mstep_result)
        assert Enum.count(events) == 12

        assert match?(
                 [
                   %Event{name: [:starting, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]}
                 ],
                 events
               )
      end)
    end

    test "should return failure after retry" do
      capture_log(fn ->
        {mstep_result, events} =
          Step.mstep_from(
            TestStage,
            {:ok, %{txn: %{TestStage => {:raise, %ArgumentError{}}}, cmp: %{TestStage => :retry}}},
            []
          )

        assert match?({:error, _, %{}}, mstep_result)
        assert Enum.count(events) == 60

        assert match?(
                 [
                   %Event{name: [:starting, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :retry, :init]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :retry, :init]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :transaction]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :compensation]},
                   %Event{name: [:completed, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:starting, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]},
                   %Event{name: [:completed, :retry, :handler]},
                   %Event{name: [:skipped, :hook, :log_compensation]},
                   %Event{name: [:completed, :hook, :log_event]}
                 ],
                 events
               )
      end)
    end
  end
end
