defmodule Membrane.MPEGTS.Muxer do
  @moduledoc """
  A module with functionalities allowing for muxing stream into the MPEG-TS container.
  """
  alias Membrane.MPEGTS.{PAT, PMT, PES, TS}
  require Logger

  @pat_pid 0x0
  @pmt_pid 0x1000
  @program_number 0x1
  @clock_rate 90_000

  defmodule AACParser do
    @header_size 7

    def new() do
      %{acc: <<>>}
    end

    def parse(payload, state) do
      payload = state.acc <> payload
      state = %{state | acc: <<>>}

      read_header(payload)
      |> read_crc()
      |> read_frame()
      |> case do
        :error ->
          {[], %{state | acc: payload}}

        {frame, rest} ->
          {frames, state} = parse(rest, state)
          {[frame | frames], state}
      end
    end

    defp read_header(<<header::binary-size(@header_size), rest::binary>>) do
      case header do
        <<0xFFF::12, _mpeg_version::1, _layer::2, crc_absence::1, _profile::2, _frequency::4,
          _priv::1, _channel_config::3, _originality::1, _home::1, _copyright_id_bit::1,
          _copyright_id_start::1, frame_length::13, _buffer_fullness::11, aac_frame_cnt::2>> ->
          if aac_frame_cnt != 0 do
            Logger.warning("Unsupported `aac_frame_cnt` value of: #{inspect(aac_frame_cnt)}")
          end

          %{
            left_to_parse: rest,
            frame_payload: header,
            next_frame_length: frame_length,
            header_crc_absence: crc_absence
          }

        _other ->
          :error
      end
    end

    defp read_header(_other), do: :error

    defp read_crc(
           %{left_to_parse: <<crc::binary-size(2), rest::binary>>, header_crc_absence: 0} =
             parsing_state
         ) do
      %{parsing_state | left_to_parse: rest, frame_payload: parsing_state.frame_payload <> crc}
    end

    defp read_crc(%{header_crc_absence: 1} = parsing_state) do
      parsing_state
    end

    defp read_crc(:error), do: :error

    defp read_frame(:error) do
      :error
    end

    defp read_frame(parsing_state) do
      frame_length = parsing_state.next_frame_length - @header_size

      case parsing_state.left_to_parse do
        <<frame::binary-size(frame_length), rest::binary>> ->
          {parsing_state.frame_payload <> frame, rest}

        _other ->
          :error
      end
    end
  end

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
