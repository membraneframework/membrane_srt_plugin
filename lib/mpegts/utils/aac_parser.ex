defmodule Membrane.MPEGTS.Utils.AACParser do
  @moduledoc false

  require Logger

  @header_size 7

  @type t() :: %{acc: binary()}

  @doc """
  Returns a new instance of the AAC parser.
  """
  @spec new() :: t()
  def new() do
    %{acc: <<>>}
  end

  @doc """
  Parses an incoming AAC stream and returns
  a list of AAC frames and the updated parser state.
  """
  @spec parse(binary(), t()) :: {[binary()], t()}
  def parse(payload, state) do
    payload = state.acc <> payload
    state = %{state | acc: <<>>}

    with {:ok, parsing_state} <- read_header(payload),
         {:ok, parsing_state} <- read_crc(parsing_state),
         {:ok, frame, rest} <- read_frame(parsing_state) do
      {frames, state} = parse(rest, state)
      {[frame | frames], state}
    else
      _error ->
        {[], %{state | acc: payload}}
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

        {:ok,
         %{
           left_to_parse: rest,
           frame_payload: header,
           next_frame_length: frame_length,
           header_crc_absence: crc_absence
         }}

      _other ->
        :error
    end
  end

  defp read_header(_other) do
    :error
  end

  defp read_crc(
         %{left_to_parse: <<crc::binary-size(2), rest::binary>>, header_crc_absence: 0} =
           parsing_state
       ) do
    {:ok,
     %{parsing_state | left_to_parse: rest, frame_payload: parsing_state.frame_payload <> crc}}
  end

  defp read_crc(%{header_crc_absence: 1} = parsing_state) do
    {:ok, parsing_state}
  end

  defp read_crc(_parsing_state) do
    :error
  end

  defp read_frame(parsing_state) do
    frame_length = parsing_state.next_frame_length - @header_size

    case parsing_state.left_to_parse do
      <<frame::binary-size(frame_length), rest::binary>> ->
        {:ok, parsing_state.frame_payload <> frame, rest}

      _other ->
        :error
    end
  end
end
