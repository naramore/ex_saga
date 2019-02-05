defmodule ExSaga.Generators do
  @moduledoc false
  import ExUnitProperties
  import StreamData

  alias ExSaga.TestStage

  def no_overlapping_hook_names(opts \\ []) do
    bind(uniq_list_of(atom(:alphanumeric), opts), fn
      [] -> constant({[], []})
      ns ->
        bind(integer(0..Enum.count(ns)), fn i ->
          {hns, ehns} = Enum.split(ns, i)
          bind(
            tuple({
              list_of(hook(), length: Enum.count(hns)),
              extra_hooks(length: Enum.count(ehns))
            }),
            fn {hs, ehs} ->
              constant({
                Enum.zip(hns, hs) |> Enum.map(fn {n, h} -> %{h | name: n} end),
                Enum.zip(ehns, ehs) |> Enum.map(fn
                  {n, {h, o}} -> {%{h | name: n}, o}
                  {n, h} -> %{h | name: n}
                end)
              })
            end
          )
        end)
    end)
  end

  # Stepables

  def executable_stepable(opts \\ []) do
    one_of([
      executable_stage(opts),
    ])
  end

  def executable_stepable_result(_stage_type, _opts \\ []) do
    # TODO
  end

  def stepable_module() do
    member_of([TestStage])
  end

  def executable_event(stage_type, event_name, opts \\ [])
  def executable_event(TestStage, [:starting, :stage, :transaction], opts) do
    gen all event <- event(),
            context <- effects(opts) do
      %{event | name: [:starting, :stage, :transaction],
                context: context,
                module: TestStage}
    end
  end
  def executable_event(TestStage, [:completed, :stage, :transaction], _opts) do
  end
  def executable_event(TestStage, [:starting, :stage, :compensation], _opts) do
  end
  def executable_event(TestStage, [:completed, :stage, :compensation], _opts) do
  end
  def executable_event(TestStage, [_, :hook, _] = _event_name, _opts) do
  end
  def executable_event(TestStage, [_, :retry, _] = _event_name, _opts) do
  end
  def executable_event(TestStage, [_, :error_handler] = _event_name, _opts) do
  end

  def executable_events(TestStage, opts \\ []) do
    gen all event_names <- list_of(member_of([
      [:starting, :stage, :transaction],
      [:completed, :stage, :transaction],
      [:starting, :stage, :compensation],
      [:completed, :stage, :compensation],
      [:skipped, :hook, :log_event],
      [:completed, :hook, :log_event],
      [:starting, :retry, :init],
      [:completed, :retry, :init],
      [:starting, :retry, :handler],
      [:completed, :retry, :handler],
      [:starting, :retry, :update],
      [:completed, :retry, :update],
      [:starting, :error_handler],
      [:completed, :error_handler],
    ]), opts) do
      Enum.map(event_names, fn en ->
        executable_event(TestStage, en, opts)
      end)
    end
  end

  def stepable(opts \\ []) do
    one_of([stage(opts)])
  end

  def stepable_opts(opts \\ []) do
    list_of(tuple({atom(:alphanumeric), simple()}), opts)
  end

  def executable_stage(opts \\ []) do
    executable = TestStage.create()
    ub = executable.hooks |> Enum.count()
    gen all stg <- stage(opts),
            n <- integer(0..ub) do
      %{stg | name: executable.name,
              transaction: executable.transaction,
              compensation: executable.compensation,
              hooks: Enum.take(executable.hooks, n),
              on_retry: executable.on_retry,
              on_error: executable.on_error}
    end
  end

  def executable_stage_result() do
    one_of([
      tuple({constant(:ok), TestStage.test_effects()}),
      tuple({member_of([:error, :abort]), reason(), TestStage.test_effects()})
    ])
  end

  def stage(opts \\ []) do
    gen all transaction <- transaction(opts),
            compensation <- compensation(opts),
            state <- state(opts) do
      %ExSaga.Stage{
        transaction: transaction,
        compensation: compensation,
        state: state,
      }
    end
  end

  def state(opts \\ []) do
    gen all name <- one_of([atom(:alphanumeric), atom(:alias)]),
            hooks <- list_of(hook(), opts),
            hooks_left <- list_of(hook(), opts),
            retry_updates <- list_of(retry_update(), opts),
            update <- retry_result(),
            effects_so_far <- effects(opts),
            abort? <- boolean(),
            reason <- reason(),
            on_retry <- atom(:alias),
            on_error <- atom(:alias) do
      %ExSaga.State{
        name: name,
        hooks: hooks,
        hooks_left: hooks_left,
        retry_updates_left: retry_updates,
        update: update,
        effects_so_far: effects_so_far,
        abort?: abort?,
        reason: reason,
        on_retry: on_retry,
        on_error: on_error
      }
    end
  end

  def full_name(opts \\ []) do
    list_of(name(), Keyword.merge([length: 1..5], opts))
  end

  def name(), do: atom(:alphanumeric)

  def transaction(opts \\ []) do
    function1(effects(opts), one_of([
      tuple({constant(:ok), effect()}),
      tuple({member_of([:error, :abort]), reason()})
    ]))
  end

  def compensation(opts \\ []) do
    function3(reason(), effect(), effects(opts), one_of([
      constant(:ok),
      constant(:abort),
      tuple({constant(:retry), retry_opts(opts)}),
      tuple({constant(:continue), effect()})
    ]))
  end

  # Hooks

  def hook_accumulator(opts \\ []) do
    gen all hooks <- list_of(hook(), opts),
            hooks_left <- list_of(hook(), opts),
            effects_so_far <- effects(opts) do
      %{
        hooks: hooks,
        hooks_left: hooks_left,
        effects_so_far: effects_so_far
      }
    end
  end

  def hook() do
    gen all name <- atom(:alphanumeric),
            filter <- hook_filter(),
            fun <- hook_function() do
      %ExSaga.Hook{
        name: name,
        filter: filter,
        fun: fun
      }
    end
  end

  def hook_function() do
    function2(event(), hook_state(), hook_result())
  end

  def hook_result() do
    one_of([
      constant(:ok),
      tuple({constant(:ok), hook_state()}),
      tuple({constant(:error), reason()}),
      tuple({constant(:error), reason(), hook_state()})
    ])
  end

  def hook_filter() do
    function2(event(), hook_state(), boolean())
  end

  def hook_state(opts \\ []) do
    # technically more like `term()`, but that is costly...
    map_of(atom(:alphanumeric), simple(), opts)
  end

  def hook_opts() do
    # technically more like `keyword_of(term())`, but that is costly...
    keyword_of(simple())
  end

  def extra_hooks(opts \\ []) do
    list_of(one_of([
      hook(),
      tuple({hook(), hook_opts()})
    ]), opts)
  end

  def extra_hooks_with_overrides(names, opts \\ []) do
    gen all name <- member_of(names),
            hook <- hook(),
            extra_hooks <- extra_hooks(opts) do
      [{%{hook | name: name}, [override: true]}|extra_hooks]
    end
  end

  # Events

  def event() do
    gen all id <- id(),
            timestamp <- timestamp(),
            stage_name <- full_name(),
            name <- event_name(),
            context <- event_context(),
            metadata <- event_metadata(),
            stage <- atom(:alias) do
      %ExSaga.Event{
        id: id,
        timestamp: timestamp,
        stage_name: stage_name,
        name: name,
        context: context,
        metadata: metadata,
        stage: stage
      }
    end
  end

  def event_metadata(string_kind \\ :ascii, opts \\ []) do
    gen all app <- atom(:alias),
            mod <- atom(:alphanumeric),
            fun <- atom(:alphanumeric),
            line <- positive_integer(),
            file <- string(string_kind, opts) do
      [
        application: app,
        module: mod,
        function: fun,
        line: line,
        file: file,
        pid: self()
      ]
    end
  end

  def effects(opts \\ []) do
    tree(
      flat_effects(effect(), opts),
      &flat_effects(&1, opts)
    )
  end

  def flat_effects(effect \\ effect(), opts \\ []) do
    bind({static_effects(opts), map_of(name(), effect, opts)}, fn {static, dynamic} ->
      constant(Map.merge(static, dynamic))
    end)
  end

  def static_effects(opts \\ []) do
    fixed_map(%{
      __retry__: retry_state_map(opts),
      __hookstate__: hook_state()
    })
  end

  def retry_state_map(opts \\ []) do
    map_of(retry_state_name(), retry_state(), opts)
  end

  def retry_state_name() do
    one_of([atom(:alias), full_name()])
  end

  def effect() do
    # technically more like `term()`, but that is costly...
    simple()
  end

  def event_name(opts \\ []) do
    list_of(atom(:alphanumeric), Keyword.merge([length: 1..5], opts))
  end

  def id() do
    atom(:alphanumeric)
  end

  def timestamp() do
    tuple({atom(:alphanumeric), datetime()})
  end

  def datetime() do
    gen all year <- integer(0..9999),
            month <- integer(1..12),
            day <- integer(1..31),
            hour <- integer(0..23),
            minute <- integer(0..59),
            second <- integer(0..59),
            microsecond <- microseconds() do
      %DateTime{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        microsecond: microsecond,
        time_zone: "Etc/UTC",
        zone_abbr: "UTC",
        utc_offset: 0,
        std_offset: 0
      }
    end
  end

  def microseconds() do
    gen all ms <- integer(0..999_999) do
      {ms, decimal_precision(ms)}
    end
  end

  defp decimal_precision(num) do
    digits = Integer.digits(num)
    trailing_zeros = digits
    |> Enum.reverse()
    |> Enum.take_while(fn x -> x == 0 end)
    |> Enum.count()

    Enum.count(digits) - trailing_zeros
  end

  def event_context() do
    # technically more like `term()`, but that is costly...
    one_of([
      effect(),
      tuple({event(), effect()})
    ])
  end

  # Retrys

  def retry_accumulator(opts \\ []) do
    gen all on_retry <- atom(:alphanumeric),
            hooks <- list_of(hook(), opts),
            hooks_left <- list_of(hook(), opts),
            retry_updates <- list_of(retry_update(), opts),
            update <- retry_result(),
            effects_so_far <- effects(opts),
            abort? <- boolean() do
      %{
        on_retry: on_retry,
        hooks: hooks,
        hooks_left: hooks_left,
        retry_updates_left: retry_updates,
        update: update,
        effects_so_far: effects_so_far,
        abort?: abort?
      }
    end
  end

  def retry_update() do
    tuple({full_name(), atom(:alphanumeric)})
  end

  def retry_result() do
    one_of([
      tuple({constant(:retry), wait(), retry_state()}),
      tuple({constant(:noretry), retry_state()})
    ])
  end

  def retry_update_result() do
    one_of([
      constant(:ok),
      tuple({constant(:ok), retry_state()})
    ])
  end

  def retry_state do
    # technically more like `term()`, but that is costly...
    simple()
  end

  def retry_opts(opts \\ []) do
    list_of(tuple({atom(:alphanumeric), simple()}), opts)
  end

  def wait(range \\ 0..100_000, unit \\ time_unit()) do
    tuple({integer(range), unit})
  end

  def time_unit() do
    one_of([
      constant(:second),
      constant(:millisecond),
      constant(:microsecond),
      constant(:nansecond),
      positive_integer()
    ])
  end

  # Miscellaneous

  def error_handler_accumulator(opts) do
    gen all on_error <- atom(:alias),
            hooks <- list_of(hook(), opts),
            hooks_left <- list_of(hook(), opts),
            effects_so_far <- effects(opts),
            reason <- reason() do
              %{
                on_error: on_error,
                hooks: hooks,
                hooks_left: hooks_left,
                effects_so_far: effects_so_far,
                reason: reason
              }
            end
  end

  def error_handler_event(opts \\ []) do
    gen all event <- event(),
            {name, context} <- error_handler_event_context(opts) do
              %{event | name: name,
                        context: context}
            end
  end

  def error_handler_event_context(opts \\ []) do
    one_of([
      tuple({
        constant([:starting, :error_handler]),
        error_handler_starting_event_context(opts)
      }),
      tuple({
        constant([:completed, :error_handler]),
        error_handler_completed_event_context()
      })
    ])
  end

  def error_handler_starting_event_context(opts \\ []) do
    tuple({reason(), event(), effects(opts)})
  end

  def error_handler_completed_event_context() do
    tuple({event(), error_handler_result()})
  end

  def error_handler_result() do
    one_of([
      tuple({constant(:ok), simple()}),
      tuple({constant(:raise), reason(), stacktrace()}),
      tuple({constant(:throw), reason()}),
      tuple({constant(:exit), simple()}),
    ])
  end

  def stacktrace(opts \\ []) do
    list_of(simple(), opts)
  end

  def reason() do
    # technically more like `term()`, but that is costly...
    one_of([
      atom(:alphanumeric),
      tuple({atom(:alphanumeric), atom(:alphanumeric)}),
      tuple({atom(:alphanumeric), atom(:alphanumeric), atom(:alphanumeric)})
    ])
  end

  def breakpoint() do
    function2(event(), stepable(), stepable())
  end

  def dry_run_result() do
    # TODO
  end

  def simple() do
    one_of([
      integer(),
      binary(),
      float(),
      boolean(),
      atom(:alias),
      atom(:alphanumeric)
    ])
  end

  def function0(result) do
    bind(result, fn r ->
      constant(fn -> r end)
    end)
  end

  def function1(_arg1, result) do
    bind(result, fn r ->
      constant(fn _ -> r end)
    end)
  end

  def function2(_arg1, _arg2, result) do
    bind(result, fn r ->
      constant(fn _, _ -> r end)
    end)
  end

  def function3(_arg1, _arg2, _arg3, result) do
    bind(result, fn r ->
      constant(fn _, _, _ -> r end)
    end)
  end

  def function4(_arg1, _arg2, _arg3, _arg4, result) do
    bind(result, fn r ->
      constant(fn _, _, _, _ -> r end)
    end)
  end
end
