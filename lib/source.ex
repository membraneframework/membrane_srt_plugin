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
              password: [
                default: nil,
                spec: String.t() | nil,
                description: """
                Password used to authenticate the connection.
                If set, the server will require clients to provide this password
                when connecting.
                If not set, the server will accept connections without authentication.
                Note that if you set this option, you must also set the same password
                on the client side when connecting to this server.
                Password needs to have between 10 and 79 characters.

                Please note that it can only be used along `ip`, `port` and `stream_id`
                options (password cannot be set when `server` and `conn_id` are provided).
                """
              ],
              server: [
                default: nil,
                spec: ExLibSRT.Server.t() | nil,
                description: """
                Reference to an already-running `ExLibSRT.Server`.
                Must be provided together with `conn_id`.

                When using this option, the other options (`ip`, `port`, `stream_id` and `password`)
                cannot be set.
                If you want to use `#{inspect(__MODULE__)}` with that option, remember to spawn
                the element right after receiving `{:srt_server_conn, conn_id, stream_id}`
                message from the server - this way you will have a guarantee that the source will
                bind to the desired connection within the 1-second timeout.

                Exemplary usage scenario:

                  # Start the server listening on desired address and port
                  {:ok, server} = ExLibSRT.Server.start(<ip>, <port>, accept_mode: :accept_all)

                  # Wait until a client with desired stream_id connects
                  receive do
                    {:srt_server_conn, conn_id, _stream_id} ->
                      pid = Membrane.RCPipeline.start_link!()

                      # Spawn the `#{inspect(__MODULE__)}` element and pass the server
                      # and connection ID as arguments
                      spec =
                        child(:source, %Membrane.SRT.Source{server: server, conn_id: conn_id})
                        |> child(:sink, %Membrane.File.Sink{location: "output.ts"})
                      Membrane.RCPipeline.exec_actions(pid, spec: spec)
                  end
                """
              ],
              conn_id: [
                default: nil,
                spec: ExLibSRT.Server.connection_id() | nil,
                description: """
                Connection ID received via `{:srt_server_conn, conn_id, stream_id}`.
                Must be provided together with `server`.
                """
              ]

  @impl true
  def handle_init(
        _ctx,
        %{ip: ip, port: port, stream_id: stream_id, server: nil, conn_id: nil} = opts
      )
      when not is_nil(ip) and not is_nil(port) and not is_nil(stream_id) do
    state = Map.merge(%{mode: :built_in}, opts)
    {[], state}
  end

  @impl true
  def handle_init(
        _ctx,
        %{
          ip: nil,
          port: nil,
          stream_id: nil,
          password: nil,
          server: server,
          conn_id: conn_id
        } =
          opts
      )
      when not is_nil(server) and not is_nil(conn_id) do
    state = Map.merge(%{mode: :external}, opts)
    {[], state}
  end

  @impl true
  def handle_init(_ctx, opts) do
    raise """
      `#{inspect(__MODULE__)}` accepts the following disjoint sets of options:
      * `port`, 'ip', `stream_id` and optionally `password`
      * `server` and `conn_id`
      while you provided: #{inspect(opts)}
    """
  end

  @impl true
  def handle_playing(ctx, %{mode: :built_in} = state) do
    password_opt = if state.password, do: [password: state.password], else: []
    opts = [accept_mode: {:whitelist, [state.stream_id]}] ++ password_opt
    {:ok, server} = Server.start(state.ip, state.port, opts)
    state = Map.put_new(state, :server, server)

    Membrane.ResourceGuard.register(ctx.resource_guard, fn ->
      Server.stop(server)
    end)

    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_playing(_ctx, %{mode: :external} = state) do
    :ok = Server.bind_with_process(state.server, state.conn_id, self())
    {[stream_format: {:output, %Membrane.RemoteStream{}}], state}
  end

  @impl true
  def handle_info({:srt_server_conn, conn_id, _stream_id}, _ctx, %{mode: :built_in} = state) do
    :ok = Server.bind_with_process(state.server, conn_id)
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
