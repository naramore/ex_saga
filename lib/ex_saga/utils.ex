defmodule ExSaga.Utils do
  @moduledoc """
  """

  import Kernel, except: [get_in: 2]
  alias ExSaga.Stage

  @doc """
  """
  @spec get_effects(Stage.effects(), Stage.full_name()) :: Stage.effects() | Stage.effect() | nil
  def get_effects(effects, []), do: effects

  def get_effects(effects, path) do
    Kernel.get_in(effects, Enum.map(path, fn x -> put_or_insert_map(x) end))
  end

  @doc """
  """
  @spec insert_effect(Stage.effects(), Stage.full_name(), Stage.effect()) :: Stage.effects()
  def insert_effect(effects, path, effect) do
    put_in(
      effects,
      Enum.map(path, fn x -> put_or_insert_map(x) end),
      effect
    )
  end

  @doc """
  """
  @spec put_or_insert_map(Stage.name()) :: Access.access_fun(map(), term())
  def put_or_insert_map(name) do
    fn
      :get, data, next ->
        next.(Map.get(data, name, %{}))

      :get_and_update, data, next ->
        value = Map.get(data, name, %{})

        case next.(value) do
          {get, update} -> {get, Map.put(data, name, update)}
          :pop -> Map.pop(data, name)
        end
    end
  end

  @doc """
  """
  @spec get_local_metadata(Macro.Env.t()) :: Keyword.t()
  def get_local_metadata(env \\ __ENV__) do
    [
      application:
        case :application.get_application() do
          :undefined -> nil
          otherwise -> otherwise
        end,
      module: env.module,
      function: env.function,
      line: env.line,
      file: env.file,
      pid: self()
    ]
  end

  @doc """
  """
  @spec get_in(term, [term]) :: term
  def get_in(data, []), do: data
  def get_in(data, path), do: get_in(data, path)
end
