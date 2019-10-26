defmodule WikiParser do
  @moduledoc """
  Documentation for WikiParser.
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://en.wikipedia.org"
  plug Tesla.Middleware.JSON

  def search_for_game(game) do
    game =
      String.downcase(game)

    result =
      get("/w/api.php?action=query&list=search&utf8=&format=json&srprop=snippet&srsearch=#{URI.encode(game)}%20video%20game")
      |> get_search_results()
      |> filter_search_results(game)
      |> handle_search_result

    case result do
      {:ok, game} ->
        canonicalurl =
          get_page_info(game["pageid"])
          |> get_canonicalurl()

        game =
          Map.put(game, "wikipedia_url", canonicalurl)

        game_details = get_game_details(game)

        Map.merge(game_details, game)


      error ->
        error
    end

  end

  def get_search_results({:ok, response}) do
    response
    |> Map.get(:body)
    |> Map.get("query")
    |> Map.get("search")
  end

  def filter_search_results(search_results, game) do
    filtered_results =
      search_results
      |> Enum.reject(fn result ->
        title = String.downcase(result["title"])

        !String.contains?(title, game)
      end)
      |> Enum.reject(fn result ->
        title = String.downcase(result["title"])

        if title != game do
          !String.contains?(title, "video game")
        else
          false
        end
      end)

    if length(filtered_results) > 1 do
      Enum.reject(filtered_results, fn result ->
        !String.contains?(result["title"], "video game")
      end)
    else
      filtered_results
    end
  end

  def handle_search_result([]), do: {:error, "No games found"}

  def handle_search_result([game | _ ]) do
    game =
      game
      |> Map.take(["pageid", "snippet", "title"])
      |> Map.put("title", String.replace(Map.get(game, "title"), " (video game)", ""))
      |> Map.put("snippet", HtmlSanitizeEx.strip_tags(Map.get(game, "snippet")))

    {:ok, game}
  end

  def get_page_info(pageid) do
    get("/w/api.php?action=query&prop=info&pageids=#{pageid}&inprop=url&format=json")
    |> handle_page_result(pageid)
  end

  def get_canonicalurl(page) do
    Map.get(page, "canonicalurl")
  end

  def handle_page_result({:ok, response}, pageid) do
    response
    |> Map.get(:body)
    |> Map.get("query")
    |> Map.get("pages")
    |> Map.get("#{pageid}")
  end



  def get_game_details(game) do
    get("https://en.wikipedia.org/w/api.php?action=parse&pageid=#{game["pageid"]}&prop=wikitext&section=0&format=json")
    |> handle_game_result()
  end

  def handle_game_result({:ok, response}) do
    response
    |> Map.get(:body)
    |> Map.get("parse")
    |> Map.get("wikitext")
    |> Map.get("*")
    |> HtmlSanitizeEx.strip_tags()
    |> parse_wikitext()
  end





  def parse_wikitext(wikitext) do

    wikitext =
      wikitext
      |> remove_citations
      |> remove_notes
      |> get_infobox

    wikitext =
      Regex.split(~r{([\s\S]+?)(?=\n\|[\s]*[\w]+[\s]*=)}, wikitext, trim: true, include_captures: true)
      |> Enum.reject(fn s ->
        !String.contains?(s, "=")
      end)

    game_details =
      wikitext
      |> Enum.map(fn v ->
        String.trim(v)
        |> String.replace(~r{^\|[\s]*}, "")
      end)
      |> Enum.map(fn v ->
          [key | [value | _ ]] = String.split(v, "=", parts: 2)

          Map.put(%{}, String.trim(key), String.trim(value))
      end)
      |> IO.inspect
      |> Enum.reduce(fn x, acc ->
        Map.merge(x, acc)
      end)

    game_details
    |> parse("composer")
    |> parse("developer")
    |> parse("director")
    |> parse("publisher")
    |> parse_list("genre")
    |> parse_list("modes")
    |> parse_release_dates()
  end

  def parse(game, key) do
    value =
      game
      |> Map.get(key)
      |> case do
        nil -> nil
        val -> val
      end
      |> remove_free_link

    game
    |> Map.put(key, value)
  end

  def parse_list(game, key) do
    value =
      game
      |> Map.get(key)
      |> String.split(", ")
      |> Enum.map(fn item ->
        remove_free_link(item)
      end)

    game
    |> Map.put(key, value)
  end


  def parse_release_dates(%{"released" => released} = game) do
    case String.contains?(released, "{{") do
      true ->
        parse_release_dates(game, :is_list)
      _ ->
        game
    end
  end

  def parse_release_dates(%{"released" => released} = game, :is_list) do

    IO.inspect {"BEGINNING", released}

    parsed = released |> remove_free_link

    parsed =
      Regex.replace(~r/([A-Z]{2,3})\|([\s\S]*?)(?=\||})/, parsed, fn _, x, y ->
        "#{x}: #{y}"
      end)

    parsed =
    Regex.replace(~r/([A-Z]{2,3})\/([A-Z]{2,3}):[\s]([\s\S]*?)\|/, parsed, fn _, a, b, c ->
      "#{a}: #{c}|#{b}: #{c}|"
    end)

    IO.inspect {"PRE-NORMALIZATION", parsed}

    parsed =
      Regex.replace(~r/'''([\s\S]*?)'''[\s]*?:[\s]*?(\||)/, parsed, fn _, console ->
        console =
          Regex.replace(~r/[\s]*?{{[\s\S]*?}}/, console, "")

        "#{console}: "
      end)


    IO.inspect {"NORMALIZED CONSOLES", parsed}

    parsed =
      Regex.replace(~r/({{[\s\w]*?\|)((?=[A-Z]{2,3})[\s\S]*?)}}/, parsed, fn _, _, dates ->
        "{{#{dates}}}"
      end)

    IO.inspect {"AFTER DATE NORMALIZATION", parsed}

    parsed =
      Regex.replace(~r/(\||^)(){{(?=[A-Z]{2,3}:)/, parsed, fn _, _ ->
        "|Main Console: {{"
      end)


    IO.inspect {"AFTER FILL MAIN CONSOLE", parsed}

    parsed =
    Regex.split(~r/\|([\s\w]*?:[\s\S]*?}})/, parsed, include_captures: true)
    |> Enum.reject(fn s ->
      !Regex.match?(~r/\|([\s\w]*?:[\s\S]*?}})/, s)
    end)
    |> Enum.map(fn s ->
      s = String.trim(s, "|")
      Regex.replace(~r/[\s]*([\w\s]*?):[\s]*/, s, fn _, console ->
        "#{console}: "
      end)
    end)
    |> Enum.map(fn s ->
      [key | [value | _]] =
        String.split(s, ": ", parts: 2)

      value =
        value
        |> String.replace("{{", "")
        |> String.replace("}}", "")
        |> String.split("|")
        |> Enum.reject(fn s ->
          !String.contains?(s, ": ")
        end)
        |> Enum.map(fn v ->
          [key | [value | _]] =
            String.split(v, ": ")

          Map.put(%{}, key, value)
        end)

      Map.put(%{}, key, value)
    end)


    IO.inspect {"AFTER DATES", parsed}

    game
    |> Map.put("released", parsed)
  end

  def get_infobox(wikitext) do
    Regex.named_captures(~r/(?<infobox>{{Infobox video game[\s\S]+?\n}}\n[\s]*\n)/, wikitext)
    |> Map.get("infobox")
    |> String.replace(~r/\n}}\n[\s]*\n/, "")
  end

  def parse_video_game_release(text) do

  end

  def remove_citations(string) do
    string
    |> String.replace(~r/{{cite web[\s\S]+?}}/, "")
  end

  def remove_notes(string) do
    string
    |> String.replace(~r/{{efn[\s\S]+?}}/, "")
  end

  def remove_free_link(nil), do: nil
  def remove_free_link(string) do
    Regex.replace(~r/\[\[([\s\S]*?)\|*?([\s\S]*?)\]\]/, string, fn _, g1, g2 ->
      case g2 do
        "" -> g1
        val -> val
      end
    end)
  end

end
