defmodule Membrane.SRT.Source do
  @moduledoc """
  Membrane Source acting as a SRT server.
  It listens for connection on given port.
  When the connection is estabilished, it start receiving stream
  with given `stream_id`.
  """
  use Membrane.Source
  require Membrane.Logger
  alias ExLibSRT.Server

  def_output_pad :output, accepted_format: Membrane.RemoteStream, flow_control: :push

  def_options ip: [
                default: nil,
                spec: String.t() | nil,
                default: "0.0.0.0",
                description: """
                Address on which the server starts listening.
                """
              ],
              port: [
                default: nil,
                spec: :inet.port_number() | nil,
                description: """
                Port on which the server starts listening.
                """
              ],
              stream_id: [
                default: nil,
                spec: String.t() | nil,
                description: """
                ID of the stream which will be accepted by this server.
                """
              ],
              server_awaiting_accept: [
                default: nil,
                spec: ExLibSRT.Server.t() | nil,
                description: """
                Reference to `ExLibSRT.Server` which is waiting for a connection accepting.

                When using this option, the other options (`ip`, `port` and `stream_id`)
                cannot be set.
                If you want to use `#{inspect(__MODULE__)}` with that option, remember to spawn
                the element right after receiving `{:srt_server_connect_request, address, stream_id}`
                message from the server - this way you will have a guarantee that the source will
                handle the desired client.

                Exemplary usage scenario:

                  # Start the server listening on desired address and port
                  {:ok, server} = ExLibSRT.Server.start(<ip>, <port>)

                  # Wait until a client with desired stream_id connects
                  receive do
                    {:srt_server_connect_request, _address, _stream_id} ->
                      pid = Membrane.RCPipeline.start_link!()

                      # Spawn the `#{inspect(__MODULE__)}` element and pass the server
                      # instance as an argument
                      spec =
                        child(:source, %Membrane.SRT.Source{server_awaiting_accept: server})
                        |> child(:sink, %Membrane.File.Sink{location: "output.ts"})
                      Membrane.RCPipeline.execute_actions(pid, spec: spec)
                  end
                """
              ]

  @impl true
  def handle_init(
        _ctx,
        %{ip: ip, port: port, stream_id: stream_id, server_awaiting_accept: nil} = opts
      )
      when not is_nil(ip) and not is_nil(port) and not is_nil(stream_id) do
    state = Map.merge(opts, %{mode: :built_in})
    {[], state}
  end

  @impl true
  def handle_init(
        _ctx,
        %{ip: nil, port: nil, stream_id: nil, server_awaiting_accept: server_awaiting_accept} =
          opts
      )
      when not is_nil(server_awaiting_accept) do
    state = Map.merge(opts, %{mode: :external})
    {[], state}
  end

  @impl true
  def handle_init(_ctx, opts) do
    raise """
      `#{inspect(__MODULE__)}` accepts the following excluding sets of options:
      * `port`, 'ip' and `stream_id`
      * 'server_awaiting_accept`
      while you provided: #{inspect(opts)}
    """
  end

  @impl true
  def handle_playing(_ctx, %{mode: :built_in} = state) do
    {:ok, server} = Server.start(state.ip, state.port)
    state = Map.put_new(state, :server, server)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    :ok = Server.accept_awaiting_connect_request(state.server_awaiting_accept)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_info(
        {:srt_server_connect_request, _address, stream_id},
        _ctx,
        %{mode: :built_in} = state
      ) do
    if stream_id == state.stream_id do
      :ok = Server.accept_awaiting_connect_request(state.server)
    else
      Membrane.Logger.warning(
        "Received connection request for stream with ID: #{inspect(stream_id)} which is not accepted
        by this server. Server expects stream with ID: #{inspect(state.stream_id)}"
      )
    end

    {[], state}
  end

  @impl true
  def handle_info({:srt_server_conn, _id, _stream_id}, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:srt_data, _conn_id, payload}, _ctx, state) do
    {[buffer: {:output, %Membrane.Buffer{payload: payload}}], state}
  end

  @impl true
  def handle_info({:srt_server_conn_closed, _conn_id}, _ctx, state) do
    {[end_of_stream: :output], state}
  end

  @impl true
  def handle_info(message, _ctx, state) do
    Membrane.Logger.warning("Received unknown message: #{inspect(message)}")
    {[], state}
  end
end
