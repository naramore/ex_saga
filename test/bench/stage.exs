defmodule ExSaga.Bench.Stage do
  @moduledoc false

  def run(inputs, opts \\ []) do
    {stage, opts} = Keyword.get(opts, :stage, stage())
    ExSaga.Step.mstep(stage(), {:ok, inputs}, opts)
  end

  def stage() do
    %ExSaga.Stage{
      name: :bench_stage,
      transaction: &__MODULE__.transaction/1,
      compensation: &__MODULE__.compensation/3,
      on_retry: ExSaga.Bench.Retry,
      on_error: ExSaga.Bench.ErrorHandler
    }
  end

  def transaction(effects) do
    %{inputs: inputs} = effects
    Enum.flat_map(inputs, fn i -> [i, i + 1] end)
  end

  def compensation(_reason, _effect, _effects) do
    :ok
  end

  def hook() do
    %ExSaga.Hook{
      name: :bench_hook,
      filter: fn _, _ -> true end,
      fun: fn
        _, nil -> {:ok, 0}
        _, i -> {:ok, i + 1}
      end
    }
  end

  def error_stage() do
    %ExSaga.Stage{
      name: :bench_error_stage,
      transaction: &__MODULE__.error_transaction/1,
      compensation: &__MODULE__.compensation/3,
      on_retry: ExSaga.Bench.Retry,
      on_error: ExSaga.Bench.ErrorHandler
    }
  end

  def error_transaction(_effects) do
    raise %ArgumentError{message: "contrived error!"}
  end

  def retry_compensation(_reason, _effect, _effects) do
    {:retry, []}
  end

  def retry_stage() do
    %ExSaga.Stage{
      name: :bench_error_stage,
      transaction: &__MODULE__.error_transaction/1,
      compensation: &__MODULE__.retry_compensation/3,
      on_retry: ExSaga.Bench.Retry,
      on_error: ExSaga.Bench.ErrorHandler
    }
  end
end

defmodule ExSaga.Bench.Retry do
  @moduledoc false
  use ExSaga.Retry

  def init(retry_opts) do
    retry_limit = Keyword.get(retry_opts, :retry_limit, 3)
    {:ok, {0, retry_limit}, retry_opts}
  end

  def handle_retry({c, l}, _retry_opts) when c >= l,
    do: {:noretry, {c, l}}

  def handle_retry({c, l}, _retry_opts),
    do: {:retry, 0, {c + 1, l}}

  def update(_retry_state, _origin_full_name, _retry_result) do
    :ok
  end
end

defmodule ExSaga.Bench.ErrorHandler do
  @moduledoc false
  use ExSaga.ErrorHandler

  def handle_error(error_reason, _origin_full_name, _effects_so_far) do
    error_reason
  end
end

map_fun = fn i -> [i, i + 1] end

inputs = %{
  "Tiny (1 hundred)" => Enum.to_list(1..100),
  "Small (1 Thousand)" => Enum.to_list(1..1_000),
  "Middle (100 Thousand)" => Enum.to_list(1..100_000),
  "Big (10 Million)" => Enum.to_list(1..10_000_000)
}

opts = [time: 15, warmup: 5, inputs: inputs, memory_time: 2]

Benchee.run(
  %{
    "flat_map" => fn inputs -> Enum.flat_map(inputs, map_fun) end,
    "map.flatten" => fn inputs -> inputs |> Enum.map(map_fun) |> List.flatten() end,
    "stage-successful" => &ExSaga.Bench.run/1,
    "stage-successful-with-hook" => &ExSaga.Bench.run(&1, extra_hooks: [ExSaga.Bench.hook()]),
    "stage-unsuccessful" => &ExSaga.Bench.run(&1, stage: ExSaga.Bench.error_stage()),
    "stage-unsuccessful-with-hook" =>
      &ExSaga.Bench.run(&1, stage: ExSaga.Bench.error_stage(), extra_hooks: [ExSaga.Bench.hook()]),
    "stage-unsuccessful-after-retries" =>
      &ExSaga.Bench.run(&1, stage: ExSaga.Bench.retry_stage(), extra_hooks: [ExSaga.Bench.hook()])
  },
  opts
)
