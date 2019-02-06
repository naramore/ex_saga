defmodule ExSaga.SagaTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog
  doctest ExSaga.Saga

  alias ExSaga.{Step, TestSaga}

  describe "ExSaga.Stage.Stepable.step_from/3" do
    @tag :skip
    property "should return [:starting, :saga, :stage] event given {:ok, effects}" do
    end

    @tag :skip
    property "should return [:starting, :saga, :compensation] event given {:error, reason, effects}" do
    end
  end

  describe "ExSaga.Stage.Stepable.step/3" do
    @tag :skip
    property "should return valid output for valid input" do
    end
  end

  describe "ExSaga.Step.mstep_from/3" do
    @tag :skip
    property "should return valid result given %ExSaga.Stage{}" do
    end

    test "should successfully return when there are no problems" do
      capture_log(fn ->
        {mstep_result, events} = Step.mstep_from(TestSaga, {:ok, %{}}, [])
        assert match?({:ok, %{a: :success!, b: :success!, c: :success!, d: :success!}}, mstep_result)
        assert Enum.count(events) == 48

        assert match?(
                 [
                   {[ExSaga.TestSaga], [:starting, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :a], [:starting, :transaction]},
                   {[ExSaga.TestSaga, :a], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :a], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :a], [:completed, :transaction]},
                   {[ExSaga.TestSaga, :a], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :a], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:completed, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:starting, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :b], [:starting, :transaction]},
                   {[ExSaga.TestSaga, :b], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :b], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :b], [:completed, :transaction]},
                   {[ExSaga.TestSaga, :b], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :b], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:completed, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:starting, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :c], [:starting, :transaction]},
                   {[ExSaga.TestSaga, :c], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :c], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :c], [:completed, :transaction]},
                   {[ExSaga.TestSaga, :c], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :c], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:completed, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:starting, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :d], [:starting, :transaction]},
                   {[ExSaga.TestSaga, :d], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :d], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga, :d], [:completed, :transaction]},
                   {[ExSaga.TestSaga, :d], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga, :d], [:completed, :hook, :log_event]},
                   {[ExSaga.TestSaga], [:completed, :saga, :stage]},
                   {[ExSaga.TestSaga], [:skipped, :hook, :log_compensation]},
                   {[ExSaga.TestSaga], [:completed, :hook, :log_event]}
                 ],
                 Enum.map(events, fn e -> {e.stage_name, e.name} end)
               )
      end)
    end
  end
end
