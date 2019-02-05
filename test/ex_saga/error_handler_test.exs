defmodule ExSaga.ErrorHandlerTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  import ExUnit.CaptureLog
  doctest ExSaga.ErrorHandler

  alias ExSaga.Generators, as: Gen
  alias ExSaga.{Event, ErrorHandler}

  defmodule SuccessErrorHandler do
    use ErrorHandler

    @impl ErrorHandler
    def handle_error(_, _, _) do
      {:ok, :stuff}
    end
  end

  defmodule InvalidErrorHandler do
    use ErrorHandler

    @impl ErrorHandler
    def handle_error(_, _, _) do
      {:error, :blah}
    end
  end

  def get_stacktrace(error \\ %ArgumentError{message: "default"}) do
    try do
      raise error
    rescue
      _ -> __STACKTRACE__
    end
  end

  describe "ExSaga.ErrorHandler.step/3" do
    property "should return error reason or {:ok, result} on successful error handler" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- Gen.error_handler_starting_event_context(length: 1..3) do
                  event = %{event | name: [:starting, :error_handler],
                                    context: context}
                  acc = %{acc | on_error: SuccessErrorHandler}
                  capture_log(fn ->
                    result = ErrorHandler.step(acc, event, [])
                    assert match?({:continue, %Event{context: {_, {:ok, _}}}, %{}}, result)
                  end)
                end
    end

    property "should return {:throw, _} on invalid error handler output" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- Gen.error_handler_starting_event_context(length: 1..3) do
                  event = %{event | name: [:starting, :error_handler],
                                    context: context}
                  acc = %{acc | on_error: InvalidErrorHandler}
                  capture_log(fn ->
                    result = ErrorHandler.step(acc, event, [])
                    assert match?({:continue, %Event{context: {_, {:throw, _}}}, %{}}, result)
                  end)
                end
    end

    property "should exit on [:error_handler, :complete] event w/ {:exit, _}" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- tuple({Gen.event(), tuple({constant(:exit), Gen.reason()})}) do
                  event = %{event | name: [:completed, :error_handler],
                                    context: context}
                  assert catch_exit(ErrorHandler.step(acc, event, []))
                end
    end

    property "should throw on [:error_handler, :complete] event w/ {:throw, _}" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- tuple({Gen.event(), tuple({constant(:throw), Gen.reason()})}) do
                  event = %{event | name: [:completed, :error_handler],
                                    context: context}
                  assert catch_throw(ErrorHandler.step(acc, event, []))
                end
    end

    property "should raise on [:completed, :error_handler] event w/ {:raise, _, _}" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                {origin, {:raise, error}} <- tuple({Gen.event(), tuple({constant(:raise), constant(%ArgumentError{message: "default"})})}) do
                  event = %{event | name: [:completed, :error_handler],
                                    context: {origin, {:raise, error, get_stacktrace()}}}
                  assert_raise ArgumentError, fn ->
                    ErrorHandler.step(acc, event, [])
                  end
                end
    end

    property "should continue on [:completed, :error_handler] event w/ {:ok, _}" do
      check all acc <- Gen.error_handler_accumulator(length: 1..3),
                event <- Gen.event(),
                context <- tuple({Gen.event(), tuple({constant(:ok), Gen.simple()})}) do
                  event = %{event | name: [:completed, :error_handler],
                                    context: context}
                  {%Event{name: name}, {:ok, result}} = context
                  assert match?({:continue, %Event{name: ^name, context: ^result}, %{}}, ErrorHandler.step(acc, event, []))
                end
    end
  end
end
