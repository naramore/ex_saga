defmodule ExSaga.TestSaga do
  @moduledoc false

  alias ExSaga.{Saga, State, TestStage}

  def create(name \\ __MODULE__) do
    %Saga{
      stages_left: [
        TestStage.create(:a),
        TestStage.create(:b),
        TestStage.create(:c),
        TestStage.create(:d),
      ],
      compensation: compensation(name),
      state: %State{
        name: name,
        hooks: TestStage.hooks(),
        on_retry: TestStage.TestRetry,
        on_error: TestStage.ErrorHandler
      }
    }
  end

  def compensation(name) do
    fn
      _, %{cmp: %{^name => :abort}} -> :abort
      _, %{cmp: %{^name => :retry}} -> {:retry, []}
      _, %{cmp: %{^name => :continue}} -> {:continue, :success!}
      _, _ -> :ok
    end
  end
end
