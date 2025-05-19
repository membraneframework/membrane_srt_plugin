defmodule Membrane.MPEGTS.Utils.H264Parser do
  @moduledoc false

  alias Membrane.H26x.NALuSplitter
  alias Membrane.H264.NALuParser
  alias Membrane.H264.AUSplitter

  @aud <<0x00, 0x00, 0x00, 0x01, 0x09, 0x16>>

  @type t :: %{
          nalu_splitter: NALuSplitter.t(),
          nalu_parser: NALuParser.t(),
          au_splitter: AUSplitter.t()
        }

  @spec new() :: t()
  def new() do
    %{
      nalu_splitter: NALuSplitter.new(),
      nalu_parser: NALuParser.new(),
      au_splitter: AUSplitter.new()
    }
  end

  @spec parse(binary(), t()) :: {[binary()], t()}
  def parse(payload, state) do
    {nalu_payloads, nalu_splitter} = NALuSplitter.split(payload, state.nalu_splitter)
    {nalus, nalu_parser} = NALuParser.parse_nalus(nalu_payloads, state.nalu_parser)

    {aus, au_splitter} = AUSplitter.split(nalus, state.au_splitter)

    {aus,
     %{state | nalu_splitter: nalu_splitter, nalu_parser: nalu_parser, au_splitter: au_splitter}}
  end

  @spec flush(t()) :: {[binary()], t()}
  def flush(state) do
    {nalu_payloads, nalu_splitter} = NALuSplitter.split(<<>>, true, state.nalu_splitter)
    {nalus, nalu_parser} = NALuParser.parse_nalus(nalu_payloads, state.nalu_parser)

    {to_return, au_splitter} = AUSplitter.split(nalus, true, state.au_splitter)

    {to_return,
     %{state | nalu_splitter: nalu_splitter, nalu_parser: nalu_parser, au_splitter: au_splitter}}
  end

  def maybe_add_aud(au) do
    if starts_with_aud(au), do: au, else: @aud <> au
  end

  defp starts_with_aud(@aud <> _rest), do: true
  defp starts_with_aud(_payload), do: false
end
