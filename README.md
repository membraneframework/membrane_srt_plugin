# Membrane SRT Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_srt_plugin.svg)](https://hex.pm/packages/membrane_srt_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_srt_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_srt_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_srt_plugin)


It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_srt_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_srt_plugin, "~> 0.1.0"}
  ]
end
```

## Usage

First start the receiving pipeline:
```
elixir examples/receiver.exs
```
The receiver will be waiting for the SRT connection on port 1234 for all the available network interfaces.
When the SRT client connects, the content of stream sent via SRT will be demuxed and saved to MP4 file.

Then start another shell and run the sending pipeline:
```
elixir examples/sender.exs
```

The sender will send a fixture content of MPEG-TS file via SRT on `127.0.0.1:1234` with stream id:
`some_stream_id`.
When the processeses terminate, you should be able to run `output.mp4` file with the streamed
content.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
