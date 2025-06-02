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
              server_waiting_for_connection_accept: [
                default: nil,
                spec: ExLibSRT.Server.t() | nil,
                description: """
                Reference to `ExLibSRT.Server` which is waiting for a connection accepting.

                If you want to use `#{inspect(__MODULE__)}` with that option, remember to spawn
                the element right after receiving `{:srt_server_connect_request, address, stream_id}`
                message from the server - this way you will have a guarantee that the source will
                handle the desired client.
                """
              ]

  defmodule ClientHandlerImpl do
    @behaviour ExLibSRT.Connection.Handler

    @impl true
    def init(__MODULE__) do
      %{source_pid: nil, buffered: []}
    end

    @impl true
    def handle_connected(_id, _stream_id, state) do
      {:ok, state}
    end

    @impl true
    def handle_disconnected(state) do
      send(state.source_pid, :client_handler_end_of_stream)
      :ok
    end

    @impl true
    def handle_data(payload, %{source_pid: nil} = state) do
      state = %{state | buffered: [payload | state.buffered]}
      {:ok, state}
    end

    @impl true
    def handle_data(payload, state) do
      send(state.source_pid, {:client_handler_data, payload})
      {:ok, state}
    end

    @impl true
    def handle_info({:source_pid, pid}, state) do
      if state.source_pid != nil do
        Membrane.Logger.warning("Overwritting of the source pid.")
      end

      Enum.reverse(state.buffered)
      |> Enum.each(send(pid, &{:client_handler_data, &1}))

      state = %{state | source_pid: pid, buffered: []}
      {:ok, state}
    end
  end

  defguardp is_builtin_server(state)
            when not is_nil(state.ip) and not is_nil(state.port) and not is_nil(state.stream_id) and
                   is_nil(state.server_waiting_for_connection_accept)

  defguardp is_external_server(state)
            when is_nil(state.ip) and is_nil(state.port) and
                   is_nil(state.stream_id) and
                   not is_nil(state.server_waiting_for_connection_accept)

  @impl true
  def handle_init(_ctx, opts) do
    state = Map.merge(opts, %{})

    if not is_builtin_server(state) and not is_external_server(state) do
      raise """
        `#{inspect(__MODULE__)}` accepts the following excluding sets of options:
        * `port`, 'ip' and `stream_id`
        * 'server' waiting fo connection accepting
        while you provided: #{inspect(opts)}
      """
    end

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) when is_builtin_server(state) do
    {:ok, server} = Server.start(state.ip, state.port)
    state = Map.put_new(state, :server, server)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_playing(_ctx, state) when is_external_server(state) do
    Server.accept_awaiting_connect_request(state.server_waiting_for_connection_accept)
    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_info({:srt_server_connect_request, _address, stream_id}, _ctx, state)
      when is_builtin_server(state) do
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

  # @impl true
  # def handle_info({:client_handler_data, payload}, _ctx, state) when is_external_server(state) do
  #   {[buffer: {:output, %Membrane.Buffer{payload: payload}}], state}
  # end
  #
  # @impl true
  # def handle_info(:client_handler_end_of_stream, _ctx, state) when is_external_server(state) do
  #   {[end_of_stream: :output], state}
  # end

  @impl true
  def handle_info(message, _ctx, state) do
    Membrane.Logger.warning("Received unknown message: #{inspect(message)}")
    {[], state}
  end
end
