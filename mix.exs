defmodule Membrane.SRT.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework-labs/membrane_srt_plugin"

  def project do
    [
      app: :membrane_srt_plugin,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description: "SRT Source and Sink for Membrane Framework",
      package: package(),

      # docs
      name: "Membrane SRT plugin",
      source_url: @github_url,
      docs: docs(),
      homepage_url: "https://membrane.stream"
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 1.2.3"},
      {:ex_libsrt, github: "membraneframework-labs/ex_libsrt", branch: "varsill/sleep_before_closing_socket"},
      {:membrane_mpeg_ts_plugin, github: "kim-company/membrane_mpeg_ts_plugin"},
      {:crc, "~> 0.10"},
      {:membrane_aac_plugin, "~> 0.19.0", optional: true},
      {:membrane_h26x_plugin, "~> 0.10.0", optional: true},
      {:membrane_mp4_plugin, "~> 0.35.0", optional: true},
      {:membrane_file_plugin, "~> 0.17.0", optiona: true},
      {:membrane_realtimer_plugin, "~> 0.10.1", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.Template]
    ]
  end
end
