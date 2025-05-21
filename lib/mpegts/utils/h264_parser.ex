defmodule Membrane.MPEGTS.Utils.H264Parser do
  @moduledoc false

  alias Membrane.H264.AUSplitter
  alias Membrane.H264.NALuParser
  alias Membrane.H26x.NALuSplitter

  @aud <<0x00, 0x00, 0x00, 0x01, 0x09, 0x16>>

  @type t :: %{
          nalu_splitter: NALuSplitter.t(),
          nalu_parser: Membrane.H26x.NALuParser.t(),
          au_splitter: AUSplitter.t()
        }

  @doc """
  Returns a new instance of the H264 Parser.
  """
  @spec new() :: t()
  def new() do
    %{
      nalu_splitter: NALuSplitter.new(),
      nalu_parser: NALuParser.new(),
      au_splitter: AUSplitter.new()
    }
  end

  @doc """
  Parses an incoming H264 payload and returns a list of access units
  along the updated state of the parser.

  Please note that the parser is allowed to buffer incoming data.
  You can call: ``#{inspect(__MODULE__)}.flush/1` to flush out the buffers data (e.g.
  when the stream ends)
  """
  @spec parse(binary(), t()) :: {[binary()], t()}
  def parse(payload, state) do
    {nalu_payloads, nalu_splitter} = NALuSplitter.split(payload, state.nalu_splitter)
    {nalus, nalu_parser} = NALuParser.parse_nalus(nalu_payloads, state.nalu_parser)
    {aus, au_splitter} = AUSplitter.split(nalus, state.au_splitter)
    aus = join_nalus_in_aus(aus)

    {aus,
     %{state | nalu_splitter: nalu_splitter, nalu_parser: nalu_parser, au_splitter: au_splitter}}
  end

  @doc """
  Flushes out the data buffered in the internal state of the parser.
  """
  @spec flush(t()) :: {[binary()], t()}
  def flush(state) do
    {nalu_payloads, nalu_splitter} = NALuSplitter.split(<<>>, true, state.nalu_splitter)
    {nalus, nalu_parser} = NALuParser.parse_nalus(nalu_payloads, state.nalu_parser)
    {aus, au_splitter} = AUSplitter.split(nalus, true, state.au_splitter)
    aus = join_nalus_in_aus(aus)

    {aus,
     %{state | nalu_splitter: nalu_splitter, nalu_parser: nalu_parser, au_splitter: au_splitter}}
  end

  @doc """
  Adds an Access Unit Delimeter NAL unit if it's not present at
  the beginning of the binary.

  Please note that this function assumes that the provided payload
  is a single Access Unit.
  """
  @spec maybe_add_aud(binary()) :: binary()
  def maybe_add_aud(au) do
    if starts_with_aud(au), do: au, else: @aud <> au
  end

  defp starts_with_aud(@aud <> _rest), do: true
  defp starts_with_aud(_payload), do: false

  defp join_nalus_in_aus(aus) do
    annexb_prefix = <<0, 0, 0, 1>>

    Enum.map(aus, fn au ->
      %{
        payload: Enum.map_join(au, &(annexb_prefix <> &1.payload)),
        is_keyframe: Enum.any?(au, &(&1.type == :idr))
      }
    end)
  end
end
