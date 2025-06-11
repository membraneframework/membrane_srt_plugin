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

### Usage of the `Membrane.SRT.Source` with built-in server

In the simplest scenario `Membrane.SRT.Source` can be used in a built-in server mode.
It starts the `ExLibSRT.Server` on its own and then accept only a single client connection
with the assumed stream ID.
To see how it works you can run the following script:
```
elixir examples/receiver.exs

```
The receiver will be waiting for the SRT connection on port 1234 for all the available network interfaces.
When the SRT client with assumed stream ID (`some_stream_id`) connects, the content of stream sent via SRT
will be demuxed and saved to MP4 file named `output.mp4`.

### Usage of the `Membrane.SRT.Source` with external server

If you don't know the client's stream ID in advance or when you want to handle multiple client connections on the same server port,
you can use the `Membrane.SRT.Source` in external server mode.
Run the following script:
```
elixir examples/receiver_with_external_server.exs
```

It starts a standalone `ExLibSRT.Server` and then each time a new client connects, it spawns a pipeline with
`Membrane.SRT.Source` using the external server reference.

### Usage of the `Membrane.SRT.Client`

`Membrane.SRT.Client` connects on the given address and starts streaming with given stream ID.
To see it in action, run:
```
elixir examples/sender.exs
```

The sender will send a fixture content of MPEG-TS file via SRT on `127.0.0.1:1234` with stream id:
`some_stream_id`.

### Running examples

You can run one of the receiver scripts (`examples/receiver.exs` or
`examples/receiver_with_external_server.exs`) and then in a new shell you can run `examples/sender.exs`
to see how the SRT connection is estabilished.

Alternatively, you can run one of the receiver scripts (`examples/receiver.exs` or
`examples/receiver_with_external_server.exs`) and stream to `srt://127.0.0.1:1234?stream_id=some_stream_id` with the use of OBS. 

<img width="1437" alt="image" src="https://github.com/user-attachments/assets/d5841a09-4edc-4e0a-b25a-a33d91d8f271" />
 
## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
