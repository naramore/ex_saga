defprotocol ExSaga.Stepable do
  @moduledoc """
  """

  alias ExSaga.{Event, Hook, Stage}

  @typedoc """
  """
  @type opt ::
    {:id, Stage.id} |
    {:dry_run?, boolean} |
    {:dry_run_result, term} |
    {:timeout, timeout} |
    {:extra_hooks, [Hook.t | {Hook.t, Hook.opts}]} |
    {:retry_updates, [{Stage.full_name, module}]} |  # TODO: auto-gen these from full_name?
    {:parent_full_name, Stage.full_name}

  @typedoc """
  """
  @type opts :: [opt]

  @typedoc """
  """
  @type stage_result ::
    {:ok, Stage.effects} |
    {:error | :abort, reason :: term, Stage.effects}

  @typedoc """
  """
  @type step_result :: {:continue, Event.t | nil, t}

  @doc """
  """
  @spec step_from(t, stage_result, opts) :: step_result
  def step_from(stepable, stage_result, opts \\ [])

  @doc """
  """
  @spec step(t, Event.t, opts) :: step_result | stage_result
  def step(stepable, event, opts \\ [])
end
