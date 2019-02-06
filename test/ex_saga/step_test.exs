defmodule ExSaga.StepTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  doctest ExSaga.Step

  alias ExSaga.Generators, as: Gen

  describe "ExSaga.Step.mstep" do
    @tag :skip
    property "_from/3 should return valid result" do
      check all stepable <- Gen.stepable_module(),
                result <- Gen.executable_stepable_result(stepable, length: 0..3) do
        {resp, _} = Step.mstep_from(stepable, result, [])
        assert match?({:ok, %{}}, resp) or match?({status, _, %{}} when status in [:error, :abort], resp)
      end
    end

    @tag :skip
    property "_at/3 should return valid result" do
      check all stepable <- Gen.executable_stepable(length: 0..3),
                %{__struct__: stage_type} = stepable,
                event <- Gen.executable_event(stage_type, length: 0..3) do
        {resp, _} = Step.mstep_at(stepable, event, [])
        assert match?({:ok, %{}}, resp) or match?({status, _, %{}} when status in [:error, :abort], resp)
      end
    end

    @tag :skip
    property "_after/3 should return valid result" do
      check all stepable <- Gen.stepable_module(),
                events <- Gen.executable_events(stepable, length: 0..3) do
        {resp, _} = Step.mstep_after(stepable, events, [])
        assert match?({:ok, %{}}, resp) or match?({status, _, %{}} when status in [:error, :abort], resp)
      end
    end
  end

  describe "ExSaga.Step.mstep breakpoint" do
  end

  describe "ExSaga.Step.mstep subscribers" do
  end
end
