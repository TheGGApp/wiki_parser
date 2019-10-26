defmodule WikiParser.MixProject do
  use Mix.Project

  def project do
    [
      app: :wiki_parser,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:hackney, "~> 1.14.0"},
      {:html_sanitize_ex, "~> 1.3"},
      {:jason, ">= 1.0.0"},
      {:tesla, "~> 1.2.1"}
    ]
  end
end
