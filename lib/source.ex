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

  def_output_pad(:output, accepted_format: Membrane.RemoteStream, flow_control: :push)

  def_options(
    port: [
      spec: :inet.port_number(),
      description: """
      Port on which the server starts listening.
      """
    ],
    ip: [
      spec: String.t(),
      default: "0.0.0.0",
      description: """
      Address on which the server starts listening.
      """
    ],
    stream_id: [
      spec: String.t(),
      description: """
      ID of the stream which will be accepted by this server.
      """
    ]
  )

  @impl true
  def handle_playing(_ctx, opts) do
    {:ok, server} = Server.start(opts.ip, opts.port)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], %{server: server}}
  end

  @impl true
  def handle_info({:srt_server_connect_request, _address, stream_id}, _ctx, state) do
    if stream_id == state.stream_id do
      :ok = Server.accept_awaiting_connect_request(state.server)
    else
      Membrane.Logger.warning(
        "Received connection request for stream with ID: #{inspect(stream_id)} which is not accepted
        by this server. Server expects stream with ID: #{inspect(stream_id)}"
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
