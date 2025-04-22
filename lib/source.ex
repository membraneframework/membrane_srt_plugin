defmodule Membrane.SRT.Source do
  @moduledoc false
  use Membrane.Source

  require Membrane.Logger

  alias ExLibSRT.Server

  def_output_pad(:output, accepted_format: Membrane.RemoteStream, flow_control: :push)

  def_options(port: [spec: :inet.port_number()], ip: [spec: String.t(), default: "0.0.0.0"])

  @impl true
  def handle_playing(_ctx, opts) do
    {:ok, server} = Server.start(opts.ip, opts.port)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], %{server: server}}
  end

  @impl true
  def handle_info({:srt_server_connect_request, _address, _stream_id}, _ctx, state) do
    :ok = Server.accept_awaiting_connect_request(state.server)
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
