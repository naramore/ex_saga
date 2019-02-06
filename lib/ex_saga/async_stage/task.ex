defmodule ExSaga.AsyncStage.Task do
  @moduledoc """
  """

  @typedoc """
  """
  @type status :: {:active, pid} |
                  {:waiting, [Stage.name]} |
                  {:paused, Stepable.step_result} |
                  {:complete, Stepable.stage_result}

  defstruct stage: nil,
            options: [],
            status: nil
  @type t :: %__MODULE__{
    stage: Stepable.t,
    options: AsyncStage.async_opts,
    status: status
  }
end
