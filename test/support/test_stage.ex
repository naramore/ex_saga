defmodule ExSaga.TestStage do
  @moduledoc false
  use ExUnitProperties
  import StreamData
  require Logger

  alias ExSaga.{Event, Hook, Stage, State}
  alias ExSaga.Generators, as: Gen

  # TODO: update to support more than 1 name given
  def test_effects(name \\ __MODULE__) do
    gen all txn <- one_of([
              tuple({constant(:raise), constant(%ArgumentError{})}),
              tuple({constant(:throw), Gen.simple()}),
              tuple({constant(:exit), atom(:alphanumeric)}),
              tuple({member_of([:error, :abort]), atom(:alphanumeric)}),
            ]),
            txn? <- boolean(),
            cmp <- member_of([:abort, :retry, :continue]),
            cmp? <- boolean() do
      [{txn?, %{txn: %{name => txn}}}, {cmp?, %{cmp: %{name => cmp}}}]
      |> Enum.reduce(%{}, fn
        {true, m}, acc -> Map.merge(acc, m)
        {false, _}, acc -> acc
      end)
    end
  end

  def create(name \\ __MODULE__) do
    %Stage{
      transaction: transaction(name),
      compensation: compensation(name),
      state: %State{
        name: name,
        hooks: hooks(),
        on_retry: __MODULE__.TestRetry,
        on_error: __MODULE__.ErrorHandler
      }
    }
  end

  def transaction(name) do
    fn
      %{txn: %{^name => {:raise, error}}} -> raise error
      %{txn: %{^name => {:throw, value}}} -> throw value
      %{txn: %{^name => {:exit, reason}}} -> exit reason
      %{txn: %{^name => {status, reason}}} -> {status, reason}
      _ -> {:ok, :success!}
    end
  end

  def compensation(name) do
    fn
      _, _, %{cmp: %{^name => :abort}} -> :abort
      _, _, %{cmp: %{^name => :retry}} -> {:retry, []}
      _, _, %{cmp: %{^name => :continue}} -> {:continue, :success!}
      _, _, _ -> :ok
    end
  end

  def hooks() do
    [
      %Hook{
        name: :log_compensation,
        filter: fn event, _ ->
          match?(%Event{name: [_, :compensation]}, event)
        end,
        fun: fn event, _ ->
          _ = Logger.warn(fn -> "compensation! -> #{inspect(event)}" end)
          :ok
        end
      },
      %Hook{
        name: :log_event,
        filter: fn _, _ -> true end,
        fun: fn event, _ ->
          _ = Logger.info(fn -> "log_event -> #{inspect(event)}" end)
          :ok
        end
      }
    ]
  end

  defmodule TestRetry do
    @moduledoc false
    use ExSaga.Retry

    @limit 3

    @impl ExSaga.Retry
    def init(opts), do: {:ok, 1, opts}

    @impl ExSaga.Retry
    def handle_retry(count, _retry_opts)
      when count < @limit do
        {:retry, {0, :millisecond}, count + 1}
    end
    def handle_retry(count, _retry_opts) do
      {:noretry, count}
    end

    @impl ExSaga.Retry
    def update(_retry_state, _origin_full_name, _retry_result) do
      :ok
    end
  end

  defmodule ErrorHandler do
    @moduledoc false
    use ExSaga.ErrorHandler

    @impl ExSaga.ErrorHandler
    def handle_error(_reason, %Event{name: [_, _, :compensation]}, _effects_so_far) do
      :ok
    end
    def handle_error(_reason, %Event{name: [_, _, :transaction]}, _effects_so_far) do
      {:ok, :fake_success!}
    end
    def handle_error(_reason, %Event{name: [_, :retry, :init]}, _effects_so_far) do
      {:ok, 0, []}
    end
    def handle_error(_reason, %Event{name: [_, :retry, :handler]}, _effects_so_far) do
      {:ok, :fake_success!}
    end
    def handle_error(_reason, %Event{name: [_, :retry, :update]}, _effects_so_far) do
      {:ok, :fake_success!}
    end
  end
end
