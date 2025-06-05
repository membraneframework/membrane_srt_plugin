Mix.install([
  {:membrane_srt_plugin, path: "./"},
  :membrane_file_plugin
])

defmodule PipelinesSpawner do
  import Membrane.ChildrenSpec
  alias Membrane.RCPipeline
  require Logger

  @address "0.0.0.0"
  @port 1234

  def run() do
    Logger.warning("""
    Starting #{inspect(__MODULE__)} listening on: #{@address}:#{inspect(@port)}
    """)

    {:ok, server} = ExLibSRT.Server.start(@address, @port)
    wait_for_connections(server)
  end

  defp wait_for_connections(server) do
    receive do
      {:srt_server_connect_request, _address, stream_id} ->
        output_path = "output_#{stream_id}.ts"

        Logger.info("""
          Client with id: #{stream_id} connected.
          Starting a pipeline which will produce #{output_path} file.
        """)

        pid = RCPipeline.start_link!()

        spec =
          child(:source, %Membrane.SRT.Source{server_awaiting_accept: server})
          |> child(:sink, %Membrane.File.Sink{location: output_path})

        RCPipeline.exec_actions(pid, spec: spec)
        wait_for_connections(server)

      :shutdown ->
        ExLibSRT.Server.stop(server)
    end
  end
end

task = Task.async(fn -> PipelinesSpawner.run() end)
IO.gets("Press enter to terminate...")
send(task.pid, :shutdown)
Task.await(task)
