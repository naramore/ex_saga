defmodule ExSaga.MixProject do
  use Mix.Project

  @in_production Mix.env() == :prod
  @version "0.0.1"
  @description """
  """

  def project do
    [
      app: :ex_saga,
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      build_embedded: @in_production,
      start_permanent: @in_production,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: @description,
      package: package(),

      # Docs
      name: "ExSaga",
      docs: docs(),

      # Custom testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.detail": :test, "coveralls.travis": :test],
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExSaga.Application, []},
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Docs dependencies
      {:ex_doc, "~> 0.19", only: :docs},
      {:inch_ex, github: "rrrene/inch_ex", only: [:dev, :docs]},

      # Test dependencies
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev, :test], runtime: false},
      {:propcheck, "~> 1.1", only: [:dev, :test]},
      {:stream_data, "~> 0.4", only: [:dev, :test]},
      {:benchee, "~> 0.13", only: :test},
      {:excoveralls, "~> 0.10", only: [:dev, :test]},
    ]
  end

  defp package do
    [
      ~w(lib CHANGELOG.md LICENSE.md mix.exs README.md .formatter.exs),
      contributors: ["Michael Naramore"],
      maintainers: ["Michael Naramore"],
      licenses: ["MIT"],
      source_ref: "v#{@version}",
      links: %{
        github: "https://github.com/naramore/ex_saga"
      },
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      homepage_url: "https://github.com/naramore/ex_saga",
      source_url: "https://github.com/naramore/ex_saga",
      extras: ["README.md", "CHANGELOG.md"],
    ]
  end

  defp aliases do
    []
  end
end

