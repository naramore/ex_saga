defmodule ExSaga.AsyncStage do
  @moduledoc """
  """

  # %Event{name: [:starting, :async, :stages], context: %{started: [{name, pid}], waiting: %{name => [name]}}}
  # %Event{name: [:completed, :async, :stages], context: %{received: [{name, stage_result}], waiting: %{name => [name] | pid}}}
  # %Event{name: [:starting, :async, :compensation], context: {[{name, {:error | :abort, reason}}], effects_so_far}}
  # %Event{name: [:completed, :async, :compensation], context: compensation_result}
end
