defmodule ExSaga.Event do
  @moduledoc """
  """

  alias ExSaga.{Stage, Utils}

  @typedoc """
  """
  @type name :: [atom]

  defstruct id: nil,
            timestamp: nil,
            stage_name: nil,
            name: nil,
            context: nil,
            metadata: nil,
            stage: nil

  @type t :: %__MODULE__{
          id: Stage.id(),
          # timestamp: [{Stage.full_name, non_neg_integer, {Node.t, DateTime.t}}, ...],
          timestamp: {Node.t(), DateTime.t()},
          stage_name: Stage.full_name(),
          name: name | nil,
          context: term,
          metadata: Keyword.t(),
          stage: module
        }

  @doc """
  """
  @spec defaults(Macro.Env.t()) :: Keyword.t()
  def defaults(env \\ __ENV__) do
    [
      timestamp: {Node.self(), DateTime.utc_now()},
      metadata: Utils.get_local_metadata(env)
    ]
  end

  @doc """
  """
  @spec create(Keyword.t()) :: t
  def create(opts \\ []) do
    {env, opts} = Keyword.pop(opts, :env, __ENV__)

    defaults(env)
    |> Keyword.merge(opts)
    |> (&struct(__MODULE__, &1)).()
  end

  @doc """
  """
  @spec update(t, Keyword.t()) :: t
  def update(event, opts \\ []) do
    {env, opts} = Keyword.pop(opts, :env, __ENV__)

    defaults(env)
    |> Keyword.merge(opts)
    |> Enum.reduce(event, fn {k, v}, e ->
      if Map.has_key?(e, k) do
        Map.put(e, k, v)
      else
        e
      end
    end)
  end

  @doc """
  """
  @spec get_effect(t, Stage.effects()) :: Stage.effect() | nil
  def get_effect(event, effects) do
    event.stage_name
    |> Enum.reverse()
    |> hd()
    |> (&Map.get(effects, &1)).()
  end
end
