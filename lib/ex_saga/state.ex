defmodule ExSaga.State do
  @moduledoc """
  """

  alias ExSaga.{Hook, Retry, Stage}

  defstruct name: nil,
            on_retry: ExSaga.RetryWithExpoentialBackoff,
            on_error: ExSaga.RaiseErrorHandler,
            hooks: [],
            hooks_left: [],
            retry_updates_left: [],
            update: nil,
            effects_so_far: %{},
            abort?: false,
            reason: nil,
            sublevel?: false

  @type t :: %__MODULE__{
          name: Stage.name(),
          on_retry: module,
          on_error: module,
          hooks: [Hook.t() | {Hook.t(), Hook.opts()}],
          hooks_left: [Hook.t()],
          retry_updates_left: [{Stage.full_name(), module}],
          update: Retry.retry_result() | nil,
          effects_so_far: Stage.effects(),
          abort?: boolean,
          reason: term,
          sublevel?: boolean
        }

  @doc """
  """
  @spec reset(t) :: t
  def reset(state) do
    %{
      state
      | hooks_left: [],
        retry_updates_left: [],
        update: nil,
        effects_so_far: %{},
        abort?: false,
        reason: nil,
        sublevel?: false
    }
  end
end
