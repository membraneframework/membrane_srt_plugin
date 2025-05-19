defmodule Membrane.MPEGTS.Utils.AACParser do
  @moduledoc false

  require Logger

  @header_size 7

  @type t() :: %{acc: binary()}

  @spec new() :: t()
  def new() do
    %{acc: <<>>}
  end

  @spec parse(binary(), t()) :: {[binary()], t()}
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
