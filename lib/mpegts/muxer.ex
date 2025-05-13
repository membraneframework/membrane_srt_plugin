defmodule Membrane.MPEGTS.Muxer do
  @moduledoc """
  A module with functionalities allowing for muxing stream into the MPEG-TS container.
  """
  alias Membrane.MPEGTS.{PAT, PMT, PES, TS}

  @pat_pid 0x0
  @pmt_pid 0x1000
  @program_number 0x1
  @clock_rate 90_000

  defmodule H264Parser do
    @moduledoc false
    alias Membrane.H26x.NALuSplitter
    alias Membrane.H264.NALuParser
    alias Membrane.H264.AUSplitter

    @aud <<0x00, 0x00, 0x00, 0x01, 0x09, 0x16>>

    def maybe_add_aud(au) do
      if starts_with_aud(au), do: au, else: @aud <> au
    end

    defp starts_with_aud(@aud <> _rest), do: true
    defp starts_with_aud(_payload), do: false

    def new() do
      %{
        nalu_splitter: NALuSplitter.new(),
        nalu_parser: NALuParser.new(),
        au_splitter: AUSplitter.new()
      }
    end

    def parse(payload, state) do
      {nalu_payloads, nalu_splitter} = NALuSplitter.split(payload, state.nalu_splitter)
      {nalus, nalu_parser} = NALuParser.parse_nalus(nalu_payloads, state.nalu_parser)

      {aus, au_splitter} = AUSplitter.split(nalus, state.au_splitter)

      {aus,
       %{state | nalu_splitter: nalu_splitter, nalu_parser: nalu_parser, au_splitter: au_splitter}}
    end

    def flush(state) do
      {[last_au], au_splitter} = AUSplitter.split([], true, state.au_splitter)
      {[last_au], %{state | au_splitter: au_splitter}}
    end
  end

  @type track :: :audio | :video
  @type t :: %{ts: TS.t(), tracks_pids: [{track(), pos_integer()}]}

  @doc """
  Creates a new muxer instance and returns initial payload with container metadata.
  """
  @spec new() :: t()
  def new() do
    ts_state = TS.new() |> TS.add_pid(@pat_pid) |> TS.add_pid(@pmt_pid)
    {pat_payload, ts_state} = create_pat(ts_state)

    state = %{
      ts: ts_state,
      tracks_pids: []
    }

    {pat_payload, state}
  end

  @doc """
  Adds a new track to the muxer and returns track metadata.
  """
  @spec register_track(track(), t()) :: {binary(), t()}
  def register_track(track_type, state) when track_type in [:audio, :video] do
    new_track_pid = generate_new_track_pid()
    tracks_pids = [{track_type, new_track_pid} | state.tracks_pids]
    ts_state = TS.add_pid(state.ts, new_track_pid)

    {pmt_packets, ts_state} =
      PMT.serialize(@program_number, length(tracks_pids) - 1, tracks_pids)
      |> TS.serialize_psi(@pmt_pid, ts_state)

    {Enum.join(pmt_packets), %{state | tracks_pids: tracks_pids, ts: ts_state}}
  end

  @doc """
  Adds a frame to a given track and returns next part of the container payload.
  """
  @spec put_frame(binary(), track(), non_neg_integer(), non_neg_integer(), t()) :: {binary(), t()}
  def put_frame(frame, track_type, pts_ms, dts_ms, state) do
    frame = preprocess_frame(frame, track_type)
    pid = state.tracks_pids[track_type]

    {pts, dts} =
      if pts_ms != nil and dts_ms != nil do
        {ceil(pts_ms * @clock_rate / 1000), ceil(dts_ms * @clock_rate / 1000)}
      else
        {nil, nil}
      end

    {ts_packets, ts_state} =
      PES.serialize(
        frame,
        pid,
        pts,
        dts
      )
      |> TS.serialize_pes(pid, state.ts)

    {Enum.join(ts_packets), %{state | ts: ts_state}}
  end

  defp generate_new_track_pid() do
    System.unique_integer(~w[monotonic positive]a)
  end

  defp create_pat(ts_state) do
    {pat_packets, ts_state} =
      PAT.serialize(@program_number, @pmt_pid)
      |> TS.serialize_psi(@pat_pid, ts_state)

    {Enum.join(pat_packets), ts_state}
  end

  def preprocess_frame(frame, :video) do
    H264Parser.maybe_add_aud(frame)
  end

  def preprocess_frame(frame, _other) do
    frame
  end
end
