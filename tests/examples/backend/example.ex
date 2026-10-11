defmodule Locales do
  @moduledoc """
  Picks the best locale for an `Accept-Language` header.
  """

  @default_code "en"
  @max_tags 8

  defstruct code: @default_code, name: "English"

  @type t :: %__MODULE__{code: String.t(), name: String.t()}

  @doc "The first requested locale we know, or the default one."
  @spec requested([t()], String.t()) :: {t(), :exact | :fallback}
  def requested(locales, header) when is_binary(header) do
    tags = parse_tags(header)

    case Enum.find(locales, &matches_any?(&1, tags)) do
      nil -> {List.first(locales), :fallback}
      locale -> {locale, :exact}
    end
  end

  def requested(locales, _header), do: {List.first(locales), :fallback}

  defp parse_tags(header) do
    header
    |> String.split(",")
    |> Enum.map(fn raw -> raw |> String.split(";") |> hd() |> String.trim() end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_tags)
  end

  defp matches_any?(%__MODULE__{code: code}, tags) do
    Enum.any?(tags, fn tag -> String.downcase(tag) == String.downcase(code) end)
  end

  # A sigil with a regex: injected as `regex`.
  defp strip_quality(tag), do: Regex.replace(~r/;q=[\d.]+$/, tag, "")
end

locales = [%Locales{code: "en", name: "English"}, %Locales{code: "pt-BR", name: "Português"}]
{found, how} = Locales.requested(locales, "pt-BR,pt;q=0.9,en;q=0.8")
IO.puts("#{found.name} (#{how})")
