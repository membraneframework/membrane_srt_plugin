defmodule Membrane.MPEGTS.Muxer.Engine do
  @moduledoc """
  A module with functionalities allowing for muxing stream into the MPEG-TS container.
  """
  require Logger
  alias Membrane.MPEGTS.Muxer.{AACParser, H264Parser, PAT, PES, PMT, TS}

  @pat_pid 0x0
  @pmt_pid 0x1000
  @program_number 0x1
  @clock_rate 90_000

  @type track :: :audio | :video
  @type t :: %{ts: TS.t(), tracks_pids: [{track(), pos_integer()}], next_es_pid: pos_integer()}

  @doc """
  Creates a new muxer instance and returns initial payload with container metadata.
  """
  @spec new() :: {binary(), t()}
  def new() do
    ts_state = TS.new() |> TS.add_pid(@pat_pid) |> TS.add_pid(@pmt_pid)
    {pat_payload, ts_state} = create_pat(ts_state)

    state = %{
      ts: ts_state,
      tracks_pids: [],
      next_es_pid: 32
    }

    {pat_payload, state}
  end

  @doc """
  Adds a new track to the muxer and returns track metadata.
  """
  @spec register_track(track(), t()) :: {binary(), t()}
  def register_track(track_type, state) when track_type in [:audio, :video] do
    {new_track_pid, state} = generate_new_track_pid(state)
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
    {frame, is_keyframe} = preprocess_frame(frame, track_type)
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
      |> TS.serialize_pes(pid, state.ts, is_keyframe)

    {Enum.join(ts_packets), %{state | ts: ts_state}}
  end

  defp generate_new_track_pid(state) do
    {state.next_es_pid, Map.update(state, :next_es_pid, 0, &(&1 + 1))}
  end

  defp create_pat(ts_state) do
    {pat_packets, ts_state} =
      PAT.serialize(@program_number, @pmt_pid)
      |> TS.serialize_psi(@pat_pid, ts_state)

    {Enum.join(pat_packets), ts_state}
  end

  defp preprocess_frame(frame, :video) do
    {frames, parser} = H264Parser.parse(frame, H264Parser.new())
    {rest_of_frames, _parser} = H264Parser.flush(parser)
    frames = frames ++ rest_of_frames

    is_keyframe =
      case frames do
        [frame] ->
          frame.is_keyframe

        frames ->
          Logger.warning("""
          You provided an H264 payload that consists of #{length(frames)} access
          units. `#{inspect(__MODULE__)}.put_frame/5` should be called with a payload of a single frame.
          """)

          false
      end

    {H264Parser.maybe_add_aud(frame), is_keyframe}
  end

  defp preprocess_frame(frame, :audio) do
    parser = AACParser.new()
    {frames, _parser} = AACParser.parse(frame, parser)

    is_keyframe =
      case frames do
        [_frame] ->
          true

        frames ->
          Logger.warning("""
          You provided an AAC payload that consists of #{length(frames)} frames.
            `#{inspect(__MODULE__)}.put_frame/5` should be called with a payload of a single frame.
          """)

          false
      end

    {frame, is_keyframe}
  end
end
